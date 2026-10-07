// test/vault/services/billing_verifier_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimic/vault/services/billing_service.dart';
import 'package:mimic/vault/services/billing_verifier.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

void main() {
  late RSAPrivateKey testPrivateKey;
  late RSAPublicKey testPublicKey;
  late String testBase64PublicKey;

  setUpAll(() {
    // Generate an RSA key pair for testing
    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
          SecureRandom('Fortuna')..seed(KeyParameter(Uint8List(32))),
        ),
      );
    final pair = keyGen.generateKeyPair();
    testPublicKey = pair.publicKey as RSAPublicKey;
    testPrivateKey = pair.privateKey as RSAPrivateKey;

    // Encode test public key to X.509 SubjectPublicKeyInfo Base64
    final pkcs1Seq = ASN1Sequence();
    pkcs1Seq.add(ASN1Integer(testPublicKey.modulus!));
    pkcs1Seq.add(ASN1Integer(testPublicKey.exponent!));
    final pkcs1Bytes = pkcs1Seq.encode();

    final algIdSeq = ASN1Sequence();
    algIdSeq.add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'));
    algIdSeq.add(ASN1Null());

    final spkiSeq = ASN1Sequence();
    spkiSeq.add(algIdSeq);
    spkiSeq.add(ASN1BitString(stringValues: pkcs1Bytes));
    testBase64PublicKey = base64.encode(spkiSeq.encode());
  });

  String signData(String data, {bool useSha1 = false}) {
    final signer = useSha1
        ? RSASigner(SHA1Digest(), '06092a864886f70d010105')
        : RSASigner(SHA256Digest(), '06092a864886f70d01010b');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(testPrivateKey));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(data)));
    return base64.encode(sig.bytes);
  }

  PurchaseDetails createPurchase({
    required String localJson,
    required String signature,
  }) {
    return PurchaseDetails(
      purchaseID: 'tx-test-1',
      productID: kProProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: localJson,
        serverVerificationData: signature,
        source: 'google_play',
      ),
      transactionDate: '1700000000',
      status: PurchaseStatus.purchased,
    );
  }

  group('GooglePlaySignatureVerifier cryptographic checks', () {
    test('valid SHA-256 RSA signature over valid payload passes verification', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'packageName': 'com.example.mimic',
        'productId': kProProductId,
        'purchaseTime': 1700000000,
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
      );

      final purchase = createPurchase(localJson: payload, signature: sig);
      expect(verifier.verify(purchase), isTrue);
    });

    test('valid legacy SHA-1 RSA signature also passes verification', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'productId': kProProductId,
      });
      final sig = signData(payload, useSha1: true);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
      );

      final purchase = createPurchase(localJson: payload, signature: sig);
      expect(verifier.verify(purchase), isTrue);
    });

    test('tampered payload fails signature verification', () {
      final originalPayload = json.encode({
        'orderId': 'GPA.1234-5678',
        'productId': kProProductId,
      });
      final sig = signData(originalPayload);

      final tamperedPayload = json.encode({
        'orderId': 'GPA.9999-0000', // Tampered!
        'productId': kProProductId,
      });

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
      );

      final purchase =
          createPurchase(localJson: tamperedPayload, signature: sig);
      expect(verifier.verify(purchase), isFalse);
    });

    test('forged/random signature fails verification', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'productId': kProProductId,
      });
      final forgedSig = base64.encode(Uint8List(128)); // Garbage signature

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
      );

      final purchase = createPurchase(localJson: payload, signature: forgedSig);
      expect(verifier.verify(purchase), isFalse);
    });

    test('payload with wrong productId fails verification', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'productId': 'fake_product_sku',
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
      );

      final purchase = createPurchase(localJson: payload, signature: sig);
      expect(verifier.verify(purchase), isFalse);
    });

    test('payload with mismatched packageName fails verification', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678',
        'packageName': 'com.pirated.app',
        'productId': kProProductId,
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
        expectedPackageName: 'com.example.mimic',
      );

      final purchase = createPurchase(localJson: payload, signature: sig);
      expect(verifier.verify(purchase), isFalse);
    });

    test('malformed JSON local payload fails verification', () {
      const malformedPayload = 'not valid json at all';
      final sig = signData(malformedPayload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
      );

      final purchase =
          createPurchase(localJson: malformedPayload, signature: sig);
      expect(verifier.verify(purchase), isFalse);
    });

    test('empty signature string fails verification', () {
      final payload = json.encode({'productId': kProProductId});
      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
      );

      final purchase = createPurchase(localJson: payload, signature: '');
      expect(verifier.verify(purchase), isFalse);
    });

    test('missing public key rejects by default (allowUnverifiedWhenNoKey = false)',
        () {
      final payload = json.encode({'productId': kProProductId});
      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: null,
        allowUnverifiedWhenNoKey: false,
      );

      final purchase = createPurchase(localJson: payload, signature: 'any');
      expect(verifier.verify(purchase), isFalse);
    });

    test('missing public key allows in explicit dev fallback mode', () {
      final payload = json.encode({'productId': kProProductId});
      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: null,
        allowUnverifiedWhenNoKey: true,
      );

      final purchase = createPurchase(localJson: payload, signature: 'any');
      expect(verifier.verify(purchase), isTrue);
    });
  });

  group('DevelopmentPurchaseVerifier', () {
    test('allows non-empty verification data when allowAll is true', () {
      const verifier = DevelopmentPurchaseVerifier(allowAll: true);
      final purchase = createPurchase(localJson: 'any_payload', signature: '');
      expect(verifier.verify(purchase), isTrue);
    });

    test('blocks when allowAll is false', () {
      const verifier = DevelopmentPurchaseVerifier(allowAll: false);
      final purchase = createPurchase(localJson: 'any_payload', signature: '');
      expect(verifier.verify(purchase), isFalse);
    });
  });
}
