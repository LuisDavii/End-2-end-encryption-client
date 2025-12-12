import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:client_chat/database_helper.dart';

class E2EESession {
  final String myUsername;
  final String peerUsername;
  final Function(String type, dynamic payload) sendToServer;
  final Function(String plaintext) onMessageReceived;
  final bool Function() isPeerOnline; 

  bool isReady = false;

  final _dheAlgorithm = X25519();
  final _signAlgorithm = Ed25519();

  SecretKey? _sessionKeyAes;
  SecretKey? _sessionKeyHmac;

  SimpleKeyPair? _myDheKeyPair;
  List<int>? _myNonce; 
  List<int>? _tempSalt; 

  E2EESession({
    required this.myUsername,
    required this.peerUsername,
    required this.sendToServer,
    required this.onMessageReceived,
    required this.isPeerOnline, 
  });

  Future<void> init() async {
    final keys = await DatabaseHelper.instance.getSessionKeys(peerUsername);
    if (keys != null) {
      final aesBytes = base64Url.decode(keys['aes_key']!);
      final hmacBytes = base64Url.decode(keys['hmac_key']!);
      
      _sessionKeyAes = SecretKey(aesBytes);
      _sessionKeyHmac = SecretKey(hmacBytes);
      isReady = true;
      print("[E2EE $peerUsername] Chaves recuperadas do disco. Pronto para conversar.");
    }
  }

  Future<void> startHandshake() async {
    if (!isPeerOnline()) {
      print("[E2EE] Cancelando handshake: $peerUsername está offline.");
      return;
    }

    print("[E2EE $peerUsername] Iniciando handshake...");
    _myDheKeyPair = await _dheAlgorithm.newKeyPair();
    final pubKey = await _myDheKeyPair!.extractPublicKey();

    final rng = Random.secure();
    final salt = List<int>.generate(32, (_) => rng.nextInt(256));
    _tempSalt = salt;

    sendToServer("E2E_HANDSHAKE", {
      "subType": "INIT",
      "public_key": base64Url.encode(pubKey.bytes),
      "salt": base64Url.encode(salt),
    });
  }

  Future<void> handleSignal(Map<String, dynamic> packet) async {
    final type = packet['type'];
    final payload = packet['payload'];

    if (type == "E2E_HANDSHAKE") {
      final subType = payload['subType'];
      
      if (subType == "INIT") {
        await _handleHandshakeInit(payload);
      } else if (subType == "RESPONSE") {
        await _handleHandshakeResponse(payload);
      }
    } 
    else if (type == "E2E_AUTH") {
      await _handleAuthSignal(payload);
    } 
    else if (type == "E2E_MSG") {
      await _decryptAndNotify(payload);
    }
  }

  Future<void> _handleHandshakeInit(Map<String, dynamic> payload) async {
    print("[E2EE $peerUsername] Respondendo ao handshake...");
    
    _myDheKeyPair = await _dheAlgorithm.newKeyPair();
    final myPubKey = await _myDheKeyPair!.extractPublicKey();

    final peerPubKeyBytes = base64Url.decode(payload['public_key']);
    final salt = base64Url.decode(payload['salt']);

    await _deriveSessionKeys(peerPubKeyBytes, salt);

    sendToServer("E2E_HANDSHAKE", {
      "subType": "RESPONSE",
      "public_key": base64Url.encode(myPubKey.bytes),
    });

    await _startMutualAuth();
  }

  Future<void> _handleHandshakeResponse(Map<String, dynamic> payload) async {
    print("[E2EE $peerUsername] Handshake DHE finalizado. Derivando chaves...");
    final peerPubKeyBytes = base64Url.decode(payload['public_key']);
    
    if (_tempSalt == null) {
      print("Salt perdido. Ignorando resposta de handshake antigo.");
      return; 
    }

    await _deriveSessionKeys(peerPubKeyBytes, _tempSalt!);
  }
  
  Future<void> _deriveSessionKeys(List<int> peerPubKeyBytes, List<int> salt) async {
    if (_myDheKeyPair == null) return;

    final peerPubKey = SimplePublicKey(peerPubKeyBytes, type: KeyPairType.x25519);
    
    final sharedSecret = await _dheAlgorithm.sharedSecretKey(
      keyPair: _myDheKeyPair!,
      remotePublicKey: peerPubKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);
    final keyMaterial = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: salt,
      info: utf8.encode('E2EE_CHAT'),
    );
    final keyBytes = await keyMaterial.extractBytes();
    
    final aesBytes = keyBytes.sublist(0, 32);
    final hmacBytes = keyBytes.sublist(32, 64);

    _sessionKeyAes = SecretKey(aesBytes);
    _sessionKeyHmac = SecretKey(hmacBytes);

    await DatabaseHelper.instance.saveSessionKeys(
      peerUsername, 
      base64Url.encode(aesBytes), 
      base64Url.encode(hmacBytes)
    );
  }

  Future<void> _startMutualAuth() async {
    if (_sessionKeyAes == null) return;

    final rng = Random.secure();
    _myNonce = List<int>.generate(32, (_) => rng.nextInt(256));

    final encryptedNonce = await _encryptMessage(base64Url.encode(_myNonce!));
    
    sendToServer("E2E_AUTH", {
      "step": "CHALLENGE_A",
      "payload": encryptedNonce
    });
  }

  Future<void> _handleAuthSignal(Map<String, dynamic> payload) async {
    final step = payload['step'];
    final data = payload['payload']; 

    if (step == "CHALLENGE_A") {
      final nonceA = base64Url.decode(await _decryptMessage(data));
      
      final myIdentityKeyB64 = await DatabaseHelper.instance.getPrivateKey();
      final myPrivKey = base64Url.decode(myIdentityKeyB64!);
      final kp = await _signAlgorithm.newKeyPairFromSeed(myPrivKey);
      final signature = await _signAlgorithm.sign(nonceA, keyPair: kp);

      final rng = Random.secure();
      final nonceB = List<int>.generate(32, (_) => rng.nextInt(256));
      _myNonce = nonceB; 

      final content = jsonEncode({
        "sig": base64Url.encode(signature.bytes),
        "nonce": base64Url.encode(nonceB)
      });
      
      sendToServer("E2E_AUTH", {
        "step": "RESPONSE_A_CHALLENGE_B",
        "payload": await _encryptMessage(content)
      });

    } else if (step == "RESPONSE_A_CHALLENGE_B") {
      final contentJson = await _decryptMessage(data);
      final content = jsonDecode(contentJson);
      
      final nonceB = base64Url.decode(content['nonce']);

      final myIdentityKeyB64 = await DatabaseHelper.instance.getPrivateKey();
      final myPrivKey = base64Url.decode(myIdentityKeyB64!);
      final kp = await _signAlgorithm.newKeyPairFromSeed(myPrivKey);
      final signature = await _signAlgorithm.sign(nonceB, keyPair: kp);

      final finalSig = base64Url.encode(signature.bytes);
      sendToServer("E2E_AUTH", {
        "step": "RESPONSE_B",
        "payload": await _encryptMessage(finalSig)
      });

      isReady = true;
      print("[E2EE] Sessão segura estabelecida com $peerUsername!");

    } else if (step == "RESPONSE_B") {
      print("[E2EE] Minha assinatura foi aceita.");
      isReady = true;
    }
  }

  Future<Map<String, dynamic>> _encryptMessage(String plaintext) async {
    if (_sessionKeyAes == null) throw Exception("Chaves E2EE não existem");
    
    final cipher = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final nonce = cipher.newNonce();
    
    final secretBox = await cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: _sessionKeyAes!,
      nonce: nonce,
    );
    
    final hmac = Hmac(Sha256());
    final mac = await hmac.calculateMac(
      nonce + secretBox.cipherText,
      secretKey: _sessionKeyHmac!,
    );

    return {
      "iv": base64Url.encode(nonce),
      "ct": base64Url.encode(secretBox.cipherText),
      "mac": base64Url.encode(mac.bytes),
    };
  }

  Future<String> _decryptMessage(Map<String, dynamic> package) async {
    if (_sessionKeyHmac == null || _sessionKeyAes == null) {
       await init(); 
       if (_sessionKeyHmac == null) {
         throw Exception("Erro: Tentativa de descriptografar sem chaves de sessão.");
       }
    }

    final iv = base64Url.decode(package['iv']);
    final ct = base64Url.decode(package['ct']);
    final macBytes = base64Url.decode(package['mac']);

    final hmac = Hmac(Sha256());
    final calcMac = await hmac.calculateMac(
      iv + ct, 
      secretKey: _sessionKeyHmac!
    );
    
    if (calcMac != Mac(macBytes)) throw Exception("E2EE MAC Inválido");

    final cipher = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretBox = SecretBox(ct, nonce: iv, mac: Mac.empty);
    
    final plainBytes = await cipher.decrypt(secretBox, secretKey: _sessionKeyAes!);
    return utf8.decode(plainBytes);
  }
  
  Future<void> _decryptAndNotify(Map<String, dynamic> package) async {
    try {
      final msg = await _decryptMessage(package);
      onMessageReceived(msg);
    } catch (e) {
      print("Erro ao decifrar msg E2EE: $e");
    }
  }

  Future<void> sendChatMessage(String text) async {
    if (!isReady) {
      await init();
    }

    if (!isReady) {
      if (isPeerOnline()) {
        await startHandshake();
        throw Exception("Iniciando negociação segura... Tente novamente em alguns segundos.");
      } 
      else {
        throw Exception("Usuário offline e sem chaves de segurança negociadas. Não é possível enviar.");
      }
    }

    final encryptedPackage = await _encryptMessage(text);
    sendToServer("E2E_MSG", encryptedPackage);
  }
}