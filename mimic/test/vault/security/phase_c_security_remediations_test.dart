// mimic/test/vault/security/phase_c_security_remediations_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/billing_service.dart';
import 'package:mimic/vault/services/billing_verifier.dart';
import 'package:mimic/vault/services/intruder_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => store[key];
  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);
  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }
  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

class FakeBillingStore implements BillingStore {
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<PurchaseDetails> completed = [];

  void emit(List<PurchaseDetails> batch) => controller.add(batch);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: kProProductId,
          title: 'Mimic Pro',
          description: 'Lifetime access',
          price: '₱99.00',
          rawPrice: 99.0,
          currencyCode: 'PHP',
        ),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async => true;

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }
}

PurchaseDetails _createPurchase({
  required String productId,
  required String localVerification,
  required String serverVerification,
  PurchaseStatus status = PurchaseStatus.purchased,
}) {
  final details = PurchaseDetails(
    purchaseID: 'tx-1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: localVerification,
      serverVerificationData: serverVerification,
      source: 'google_play',
    ),
    transactionDate: '1700000000',
    status: status,
  );
  details.pendingCompletePurchase = true;
  return details;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AUDIT-06: Google Play Receipt Verification Hardening', () {
    test('BillingService rejects unverified receipt when allowUnverifiedWhenNoKey is false',
        () async {
      final fakePlatform = FakePlatformService();
      final proStatus = ProStatusService(
        fakePlatform,
        billingEnforced: true,
        flavor: AppDistributionFlavor.playStore,
      );
      final fakeStore = FakeBillingStore();

      // Configure BillingService with allowUnverifiedWhenNoKey = false and no public key
      final billingService = BillingService(
        proStatus: proStatus,
        store: fakeStore,
        allowUnverifiedWhenNoKey: false,
      );

      await billingService.init();

      // Emit a fake unverified purchase payload
      final fakeReceipt = json.encode({
        'orderId': 'FAKE.1234',
        'packageName': 'com.ibem.mimic',
        'productId': kProProductId,
      });

      fakeStore.emit([
        _createPurchase(
          productId: kProProductId,
          localVerification: fakeReceipt,
          serverVerification: 'forged_signature',
        ),
      ]);

      // Allow event loop to process purchaseStream
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Entitlement must remain NOT granted
      expect(await proStatus.isPro(), isFalse);
      // VULN-02: Kept pending (uncompleted) when public key is unconfigured so paying user's purchase is retried rather than burned.
      expect(fakeStore.completed.length, 0);
      expect(billingService.lastError, contains('Missing public key configuration'));
      billingService.dispose();
    });

    test('BillingService accepts validly signed receipt when key is configured',
        () async {
      // Generate RSA key pair
      final keyGen = RSAKeyGenerator()
        ..init(
          ParametersWithRandom(
            RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
            SecureRandom('Fortuna')..seed(KeyParameter(Uint8List(32))),
          ),
        );
      final pair = keyGen.generateKeyPair();
      final pubKey = pair.publicKey as RSAPublicKey;
      final privKey = pair.privateKey as RSAPrivateKey;

      // Encode public key to Base64 SPKI
      final pkcs1Seq = ASN1Sequence();
      pkcs1Seq.add(ASN1Integer(pubKey.modulus!));
      pkcs1Seq.add(ASN1Integer(pubKey.exponent!));
      final pkcs1Bytes = pkcs1Seq.encode();

      final algIdSeq = ASN1Sequence();
      algIdSeq.add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'));
      algIdSeq.add(ASN1Null());

      final spkiSeq = ASN1Sequence();
      spkiSeq.add(algIdSeq);
      spkiSeq.add(ASN1BitString(stringValues: pkcs1Bytes));
      final base64PubKey = base64.encode(spkiSeq.encode());

      // Create valid signature
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'productId': kProProductId,
      });

      final signer = RSASigner(SHA256Digest(), '06092a864886f70d01010b');
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privKey));
      final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(payload)));
      final validSigStr = base64.encode(sig.bytes);

      final fakePlatform = FakePlatformService();
      final proStatus = ProStatusService(
        fakePlatform,
        billingEnforced: true,
        flavor: AppDistributionFlavor.playStore,
      );
      final fakeStore = FakeBillingStore();

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: base64PubKey,
        expectedProductId: kProProductId,
        allowUnverifiedWhenNoKey: false,
      );

      final billingService = BillingService(
        proStatus: proStatus,
        store: fakeStore,
        verifier: verifier,
      );

      await billingService.init();

      fakeStore.emit([
        _createPurchase(
          productId: kProProductId,
          localVerification: payload,
          serverVerification: validSigStr,
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Entitlement must be granted
      expect(await proStatus.isPro(), isTrue);
      expect(fakeStore.completed.length, 1);
      billingService.dispose();
    });
  });

  group('AUDIT-07: Network Security Config for LAN Multiplayer', () {
    test('network_security_config.xml permits cleartext traffic for local LAN multiplayer',
        () async {
      final configFile = File('android/app/src/main/res/xml/network_security_config.xml');
      expect(await configFile.exists(), isTrue);

      final content = await configFile.readAsString();

      // Base config must permit cleartext traffic for P2P LAN websockets
      expect(content, contains('<base-config cleartextTrafficPermitted="true">'));

      // Must not contain invalid IP addresses in <domain> tags
      expect(content, isNot(contains('<domain includeSubdomains="true">192.168.43.1</domain>')));
    });
  });

  group('AUDIT-09: IntruderService Path Traversal Hardening', () {
    test('isValidIntruderFilename accepts valid timestamps and rejects path traversals', () {
      expect(IntruderService.isValidIntruderFilename('intruder_1728312345000000.enc'), isTrue);
      expect(IntruderService.isValidIntruderFilename('intruder_0.enc'), isTrue);

      // Path traversal attempts
      expect(IntruderService.isValidIntruderFilename('../intruder_123.enc'), isFalse);
      expect(IntruderService.isValidIntruderFilename('../../etc/passwd'), isFalse);
      expect(IntruderService.isValidIntruderFilename(r'..\intruder_123.enc'), isFalse);
      expect(IntruderService.isValidIntruderFilename('/intruder_123.enc'), isFalse);

      // Invalid filenames and formats
      expect(IntruderService.isValidIntruderFilename('intruder_.enc'), isFalse);
      expect(IntruderService.isValidIntruderFilename('intruder_abc.enc'), isFalse);
      expect(IntruderService.isValidIntruderFilename('secret.txt'), isFalse);
      expect(IntruderService.isValidIntruderFilename(''), isFalse);
    });

    test('decryptIntruderImage throws ArgumentError when given path traversal filename',
        () async {
      final intruderService = IntruderService();

      expect(
        () => intruderService.decryptIntruderImage('../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => intruderService.decryptIntruderImage('../intruder_123.enc'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteIntruderEntry throws ArgumentError when given path traversal filename',
        () async {
      final intruderService = IntruderService();

      expect(
        () => intruderService.deleteIntruderEntry('../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => intruderService.deleteIntruderEntry(r'..\intruder_123.enc'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
