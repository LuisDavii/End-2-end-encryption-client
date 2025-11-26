import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:math';
import 'dart:typed_data';

class SecureChannelWrapper {
  late final WebSocketChannel _channel;
  final _algorithm = X25519();
  late final SimpleKeyPair _clientKeyPair;

  late final SecretKey _key1Aes;
  late final StreamSubscription _channelSubscription;

  final _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;

  late final List<int> _salt;

  final _handshakeCompleter = Completer<String>();

  Future<void> connectAndHandshake(String url) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channelSubscription = _channel.stream.listen(
      (message) {
        // Verifica se o handshake já foi concluído
        if (!_handshakeCompleter.isCompleted) {
          // Se não, esta é (esperemos) a resposta do handshake
          _handshakeCompleter.complete(message);
        } else {
          // Se sim, é um pacote de dados normal para o nosso stream
          _handleEncryptedData(message);
        }
      },
      onDone: () {
        _controller.close();
        if (!_handshakeCompleter.isCompleted) {
          _handshakeCompleter.completeError(
            Exception("Canal fechou antes do handshake."),
          );
        }
      },
      onError: (e) {
        _controller.addError(e);
        if (!_handshakeCompleter.isCompleted) {
          _handshakeCompleter.completeError(e);
        }
      },
    );
    _clientKeyPair = await _algorithm.newKeyPair();
    final clientPublicKey = await _clientKeyPair.extractPublicKey();
    final clientPublicKeyBytes = clientPublicKey.bytes;

    final secureRandom = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = secureRandom.nextInt(256);
    }
    _salt = bytes;

    _channel.sink.add(
      jsonEncode({
        "type": "HANDSHAKE_START",
        "public_key": base64Url.encode(clientPublicKeyBytes),
        "salt": base64Url.encode(_salt),
      }),
    );

    final String response;
    try {
      // A execução fica "pausada" aqui até o listener (acima) chamar _handshakeCompleter.complete()
      response = await _handshakeCompleter.future;
    } catch (e) {
      throw Exception('Falha ao esperar pelo handshake: $e');
    }

    final data = jsonDecode(response);

    if (data['type'] == 'HANDSHAKE_RESPONSE') {
      final serverKeyB64 = data['public_key'];
      final serverKeyBytes = base64Url.decode(serverKeyB64);

      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: _clientKeyPair,
        remotePublicKey: SimplePublicKey(
          serverKeyBytes,
          type: KeyPairType.x25519,
        ),
      );
      final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);

      final sharedSecretBytes = await sharedSecret.extractBytes();

      final keyMaterial = await hkdf.deriveKey(
        secretKey: SecretKey(sharedSecretBytes),
        nonce: _salt,
        info: utf8.encode('handshake_info'),
      );

      final keyMaterialBytes = await keyMaterial.extractBytes();
      _key1Aes = SecretKey(keyMaterialBytes.sublist(0, 32));

      print("DEBUG CLIENT KEY (AES): ${keyMaterialBytes.sublist(0, 32)}");
      

      print("[Canal Seguro] Chaves de sessão derivadas no cliente!");

    } else {
      throw Exception('Falha no Handshake: Resposta inválida do servidor.');
    }
  }

  Future<void> _handleEncryptedData(dynamic data) async {
    try {
      final encryptedPackage = jsonDecode(data);
      final iv = base64Url.decode(encryptedPackage['iv']);
      final encryptedPayload = base64Url.decode(encryptedPackage['payload']);
      final receivedMacBytes = base64Url.decode(encryptedPackage['hmac']);

      final cipher = AesGcm.with256bits();

      final secretBox = SecretBox(
        encryptedPayload, // O payload (ciphertext)
        nonce: iv,
        mac: Mac(receivedMacBytes),
      );

      print("DEBUG CLIENT SEND:");
      print("IV: ${base64.encode(secretBox.nonce)}");
      print("Ciphertext: ${base64.encode(secretBox.cipherText)}");
      print("Tag (Mac): ${base64.encode(secretBox.mac.bytes)}");
    
      final decryptedBytes = await cipher.decrypt(
        secretBox,
        secretKey: _key1Aes,
      );

      final plaintextJsonString = utf8.decode(decryptedBytes);
      _controller.add(plaintextJsonString);
    } catch (e) {
      print("[ERRO AO DESENCRIPTAR] $e");
      _controller.addError(Exception("Falha ao processar mensagem segura: $e"));
    }
  }

  Future<void> send(String jsonString) async {
    final cipher = AesGcm.with256bits();

    final secretBox = await cipher.encrypt(
      utf8.encode(jsonString),
      secretKey: _key1Aes, // Usa a mesma chave AES
      // Não precisamos de passar o nonce, ele cria um
    );

    _channel.sink.add(
      jsonEncode({
        "iv": base64Url.encode(secretBox.nonce),
        "payload": base64Url.encode(secretBox.cipherText),
        "hmac": base64Url.encode(secretBox.mac.bytes),
      }),
    );
  }

  void close() {
    _channelSubscription.cancel();
    _channel.sink.close();
  }
}
