import 'dart:async';
import 'dart:convert';
import 'dart:math'; 
import 'dart:typed_data'; 
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cryptography/cryptography.dart';

class SecureChannelWrapper {
  late final WebSocketChannel _channel;
  final _algorithm = X25519();
  
  SimpleKeyPair? _clientKeyPair;
  SecretKey? _key1Aes;
  SecretKey? _key2Hmac;
  List<int>? _salt;

  late final StreamSubscription _channelSubscription;
  final _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;
  
  final _handshakeCompleter = Completer<String>();

  SimpleKeyPair? _tempKeyPair;
  List<int>? _tempSalt;

  Future<void> connectAndHandshake(String url) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channelSubscription = _channel.stream.listen(
      (message) {
        if (!_handshakeCompleter.isCompleted) {
          _handshakeCompleter.complete(message);
        } else {
          _handleIncomingMessage(message);
        }
      },
      onDone: () {
        _controller.close();
        if (!_handshakeCompleter.isCompleted) {
          _handshakeCompleter.completeError(Exception("Canal fechou."));
        }
      },
      onError: (e) {
        _controller.addError(e);
      },
    );

    await _performHandshakeLogic(isRenegotiation: false);
  }

  Future<void> _performHandshakeLogic({required bool isRenegotiation}) async {
    final newKeyPair = await _algorithm.newKeyPair();
    final newPublicKey = await newKeyPair.extractPublicKey();
    
    final rng = Random.secure();
    final newSalt = List<int>.generate(32, (_) => rng.nextInt(256));

    final payload = {
      "type": isRenegotiation ? "RENEGOTIATE_INIT" : "HANDSHAKE_START",
      "public_key": base64Url.encode(newPublicKey.bytes),
      "salt": base64Url.encode(newSalt),
    };

    if (isRenegotiation) {
      await send(jsonEncode(payload));
    } else {
      _channel.sink.add(jsonEncode(payload));
    }

    if (!isRenegotiation) {
       final response = await _handshakeCompleter.future;
       final data = jsonDecode(response);
       if (data['type'] == 'HANDSHAKE_RESPONSE') {
         await _deriveNewKeys(data, newKeyPair, newSalt);
       } else {
         throw Exception('Handshake inicial falhou.');
       }
    } else {
      _tempKeyPair = newKeyPair;
      _tempSalt = newSalt;
    }
  }

  Future<void> _deriveNewKeys(Map<String, dynamic> data, SimpleKeyPair keyPair, List<int> salt) async {
      final serverKeyB64 = data['public_key'];
      final serverKeyBytes = base64Url.decode(serverKeyB64);
      
      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(serverKeyBytes, type: KeyPairType.x25519),
      );
      
      final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);
      final sharedSecretBytes = await sharedSecret.extractBytes();

      final keyMaterial = await hkdf.deriveKey(
        secretKey: SecretKey(sharedSecretBytes),
        nonce: salt,
        info: utf8.encode('handshake_info'),
      );
      
      final keyMaterialBytes = await keyMaterial.extractBytes();
      
      _key1Aes = SecretKey(keyMaterialBytes.sublist(0, 32));
      _key2Hmac = SecretKey(keyMaterialBytes.sublist(32, 64));
      _clientKeyPair = keyPair;
      _salt = salt;

      print("[Canal Seguro] Chaves atualizadas!");
  }

  Future<void> _handleIncomingMessage(dynamic rawData) async {
    try {
      String decryptedString;
      try {
         decryptedString = await _decryptMessage(rawData);
      } catch (e) {
         print("Erro ao decifrar (pode ser mensagem de sistema): $e");
         return;
      }

      final data = jsonDecode(decryptedString);

      if (data['type'] == 'RENEGOTIATE_REQUEST') {
        print("[Sessão] Pedido de renovação recebido.");
        await _performHandshakeLogic(isRenegotiation: true);
        return; 
      } 
      else if (data['type'] == 'RENEGOTIATE_RESPONSE') {
        print("[Sessão] Resposta de renovação recebida.");
        await _deriveNewKeys(data, _tempKeyPair!, _tempSalt!);
        return; 
      }
      if (!_controller.isClosed) {
        _controller.add(decryptedString);
      } else {
        print("[AVISO] Mensagem recebida mas o controller já estava fechado: $decryptedString");
      }

    } catch (e) {
      print("[ERRO] Falha ao processar mensagem: $e");
    }
  }

  Future<String> _decryptMessage(dynamic data) async {
      final encryptedPackage = jsonDecode(data);
      final iv = base64Url.decode(encryptedPackage['iv']);
      final encryptedPayload = base64Url.decode(encryptedPackage['payload']);
      final receivedMacBytes = base64Url.decode(encryptedPackage['hmac']);

      final hmac = Hmac(Sha256());
      final calculatedMac = await hmac.calculateMac(
        iv + encryptedPayload,
        secretKey: _key2Hmac!,
      );

      if (calculatedMac != Mac(receivedMacBytes)) {
        throw Exception("HMAC verification failed!");
      }

      final cipher = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
      
      final secretBox = SecretBox(
        encryptedPayload, 
        nonce: iv, 
        mac: Mac.empty 
      );

      final decryptedBytes = await cipher.decrypt(
        secretBox,
        secretKey: _key1Aes!,
      );
      
      return utf8.decode(decryptedBytes);
  }

  Future<void> send(String jsonString) async {
    if (_key1Aes == null) throw Exception("Chaves não iniciadas");

    final cipher = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final nonce = cipher.newNonce(); 
    
    final secretBox = await cipher.encrypt(
      utf8.encode(jsonString),
      secretKey: _key1Aes!,
      nonce: nonce,
    );
    
    final encryptedPayload = secretBox.cipherText;

    final hmac = Hmac(Sha256());
    final mac = await hmac.calculateMac(
      nonce + encryptedPayload,
      secretKey: _key2Hmac!,
    );

    _channel.sink.add(jsonEncode({
      "iv": base64Url.encode(nonce),
      "payload": base64Url.encode(encryptedPayload), 
      "hmac": base64Url.encode(mac.bytes)
    }));
  }

  void close() {
    _channelSubscription.cancel();
    _channel.sink.close();
  }
}