// test/vault/security/phase_e_security_remediations_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';
import 'package:mimic/vault/services/billing_service.dart';
import 'package:mimic/vault/services/billing_verifier.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNetworkService extends NetworkService {
  NetworkRole _role = NetworkRole.none;
  String? _hostIp;
  String? _assignedPlayerId;
  final List<String> _connectedPlayerIds = [];
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentMessages = [];
  final List<Map<String, dynamic>> sentToMessages = [];

  @override
  NetworkRole get role => _role;
  set role(NetworkRole val) {
    _role = val;
    notifyListeners();
  }

  @override
  String? get hostIp => _hostIp;
  set hostIp(String? val) => _hostIp = val;

  @override
  int get port => 4567;

  @override
  bool get isConnected => _isConnected;
  set isConnected(bool val) {
    _isConnected = val;
    notifyListeners();
  }

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  List<String> get connectedPlayerIds => _connectedPlayerIds;

  @override
  String? get assignedPlayerId => _assignedPlayerId;
  set assignedPlayerId(String? val) => _assignedPlayerId = val;

  void simulateMessageReceived(Map<String, dynamic> msg) {
    _messageController.add(msg);
  }

  void broadcast(Map<String, dynamic> msg) {
    sentMessages.add(msg);
  }

  @override
  void sendTo(String playerId, Map<String, dynamic> msg) {
    sentToMessages.add({'playerId': playerId, 'message': msg});
  }
}

PurchaseDetails _createPurchase({
  required String productId,
  required String localVerification,
  required String serverVerification,
  PurchaseStatus status = PurchaseStatus.purchased,
}) {
  return PurchaseDetails(
    purchaseID: 'tx-sec-phase-e',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: localVerification,
      serverVerificationData: serverVerification,
      source: 'google_play',
    ),
    transactionDate: '1700000000',
    status: status,
  );
}

void main() {
  late RSAPrivateKey testPrivateKey;
  late RSAPublicKey testPublicKey;
  late String testBase64PublicKey;

  setUpAll(() {
    // Generate an RSA key pair for cryptographic testing
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

  String signData(String data) {
    final signer = RSASigner(SHA256Digest(), '06092a864886f70d01010b');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(testPrivateKey));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(data)));
    return base64.encode(sig.bytes);
  }

  group('VULN-SEC-01: Remote startGame Frame Authorization', () {
    test('GameStateSyncNotifier discards startGame message sent by remote guest socket', () async {
      final fakeNetService = FakeNetworkService();
      fakeNetService.role = NetworkRole.host;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => fakeNetService),
        ],
      );
      addTearDown(container.dispose);

      final gameStateNotifier = container.read(gameStateProvider.notifier);
      gameStateNotifier.initializeMultiplayerPlayers([
        Player(id: 'host', name: 'Host Leader', color: 0xFF111111),
        Player(id: 'guest_1', name: 'Guest 1', color: 0xFF222222),
      ]);
      final initialWordPair = const WordPair(
        realWord: 'Crypt',
        mimicWord: 'Tomb',
        realWordContext: 'Burial vault',
        mimicWordContext: 'Stone grave',
      );
      gameStateNotifier.state = gameStateNotifier.state.copyWith(
        currentRound: 1,
        mimicIds: ['guest_1'],
        currentWordPair: initialWordPair,
      );

      // Initialize sync notifier
      container.read(gameStateSyncProvider.notifier);

      // A rogue guest socket transmits a startGame packet
      fakeNetService.simulateMessageReceived({
        'type': 'startGame',
        'senderId': 'rogue_guest_socket_uuid',
      });
      await Future<void>.delayed(Duration.zero);

      // Verify that the game state was NOT restarted / rerolled by the guest
      expect(gameStateNotifier.state.currentWordPair?.realWord, equals('Crypt'));
      expect(gameStateNotifier.state.mimicIds, equals(['guest_1']));
    });

    test('GameStateSyncNotifier permits local host or internal startGame execution', () async {
      final fakeNetService = FakeNetworkService();
      fakeNetService.role = NetworkRole.host;
      fakeNetService.connectedPlayerIds.add('guest_1');

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => fakeNetService),
        ],
      );
      addTearDown(container.dispose);

      final gameStateNotifier = container.read(gameStateProvider.notifier);
      gameStateNotifier.initializeMultiplayerPlayers([
        Player(id: 'host', name: 'Host Leader', color: 0xFF111111),
        Player(id: 'guest_1', name: 'Guest 1', color: 0xFF222222),
      ]);

      container.read(gameStateSyncProvider.notifier);

      // Local host execution (senderId: 'host' or null from local loop)
      fakeNetService.simulateMessageReceived({
        'type': 'startGame',
        'senderId': 'host',
      });
      await Future<void>.delayed(Duration.zero);

      // Word pair should now be populated by _initializeGame
      expect(gameStateNotifier.state.currentWordPair, isNotNull);
      expect(gameStateNotifier.state.mimicIds, isNotEmpty);
    });
  });

  group('VULN-SEC-03: Google Play Receipt Verification purchaseState and packageName checks', () {
    test('passes verification when purchaseState is 0 (purchased) and packageName matches', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678-0001',
        'packageName': 'com.ibem.mimic',
        'productId': kProProductId,
        'purchaseTime': 1700000000,
        'purchaseState': 0, // Purchased
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
        expectedPackageName: 'com.ibem.mimic',
      );

      final purchase = _createPurchase(
        productId: kProProductId,
        localVerification: payload,
        serverVerification: sig,
      );
      expect(verifier.verify(purchase), isTrue);
    });

    test('rejects verification when purchaseState is 1 (canceled/refunded)', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678-0002',
        'packageName': 'com.ibem.mimic',
        'productId': kProProductId,
        'purchaseTime': 1700000000,
        'purchaseState': 1, // Canceled / Refunded
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
        expectedPackageName: 'com.ibem.mimic',
      );

      final purchase = _createPurchase(
        productId: kProProductId,
        localVerification: payload,
        serverVerification: sig,
      );
      expect(verifier.verify(purchase), isFalse, reason: 'Canceled purchases must be rejected');
    });

    test('rejects verification when purchaseState is 2 (pending)', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678-0003',
        'packageName': 'com.ibem.mimic',
        'productId': kProProductId,
        'purchaseTime': 1700000000,
        'purchaseState': 2, // Pending
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
        expectedPackageName: 'com.ibem.mimic',
      );

      final purchase = _createPurchase(
        productId: kProProductId,
        localVerification: payload,
        serverVerification: sig,
      );
      expect(verifier.verify(purchase), isFalse, reason: 'Pending purchases must be rejected');
    });

    test('rejects verification when packageName does not match expected package', () {
      final payload = json.encode({
        'orderId': 'GPA.1234-5678-0004',
        'packageName': 'com.otherapp.unrelated',
        'productId': kProProductId,
        'purchaseTime': 1700000000,
        'purchaseState': 0,
      });
      final sig = signData(payload);

      final verifier = GooglePlaySignatureVerifier(
        base64PublicKey: testBase64PublicKey,
        expectedProductId: kProProductId,
        expectedPackageName: 'com.ibem.mimic',
      );

      final purchase = _createPurchase(
        productId: kProProductId,
        localVerification: payload,
        serverVerification: sig,
      );
      expect(verifier.verify(purchase), isFalse, reason: 'Mismatched package name must be rejected');
    });
  });

  group('VULN-SEC-04: ProStatusService Distribution Flavor Defaults', () {
    test('PlayStore flavor enforces billing by default and is not FOSS', () async {
      final fakePlatform = FakePlatformService();
      final proService = ProStatusService(
        fakePlatform,
        flavor: AppDistributionFlavor.playStore,
      );

      expect(proService.isFoss, isFalse);
      expect(proService.billingEnforced, isTrue);
      // Because billing is enforced and storage is empty, isPro() answers false
      expect(await proService.isPro(), isFalse);
    });

    test('FOSS flavor defaults to pre-billing unlocked state', () async {
      final fakePlatform = FakePlatformService();
      final proService = ProStatusService(
        fakePlatform,
        flavor: AppDistributionFlavor.foss,
      );

      expect(proService.isFoss, isTrue);
      expect(proService.billingEnforced, isFalse);
      expect(await proService.isPro(), isTrue);
    });
  });
}
