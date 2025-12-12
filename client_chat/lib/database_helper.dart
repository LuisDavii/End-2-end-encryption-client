import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:client_chat/models/chat_models.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseHelper {
  static const columnId = '_id';
  static const columnRemetente = 'remetente';
  static const columnDestinatario = 'destinatario';
  static const columnConteudo = 'conteudo';
  static const columnTimestamp = 'timestamp';
  
  static const _tableConversas = 'conversas';
  static const _tableKeyStore = 'key_store';  
  static const _tableSessionKeys = 'session_keys';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Database? _database;
  String? _currentUser;

  final _storage = const FlutterSecureStorage();
  final _algo = AesGcm.with256bits();
  SecretKey? _localDbKey;

  Future<void> initForUser(String username) async {
    if (_currentUser == username && _database != null && _localDbKey != null) {
      return;
    }
    _currentUser = username;

    await _loadOrGenerateLocalKey(username);

    final dbName = 'Chat_$username.db';
    String path = join(await getDatabasesPath(), dbName);
    _database = await openDatabase(path, version: 1, onCreate: _onCreate);
    print("Banco de dados seguro inicializado para: $username");
  }

  Future<void> _loadOrGenerateLocalKey(String username) async {
    final keyStorageName = 'db_key_$username';

    String? base64Key = await _storage.read(key: keyStorageName);

    if (base64Key == null) {

      final newKey = await _algo.newSecretKey();
      final newKeyBytes = await newKey.extractBytes();
      base64Key = base64Url.encode(newKeyBytes);

      await _storage.write(key: keyStorageName, value: base64Key);
      print("[DB] Nova chave local gerada e salva no cofre seguro.");
    } else {
      print("[DB] Chave local recuperada do cofre seguro.");
    }

    _localDbKey = SecretKey(base64Url.decode(base64Key));
  }

  Future<Database> get database async {
    if (_database == null || _currentUser == null) {
      throw Exception("DatabaseHelper não inicializado!");
    }
    return _database!;
  }

  Future _onCreate(Database db, int version) async {

    await db.execute('''
          CREATE TABLE $_tableConversas (
            _id INTEGER PRIMARY KEY AUTOINCREMENT,
            remetente TEXT NOT NULL,
            destinatario TEXT NOT NULL,
            conteudo TEXT NOT NULL, -- Agora será cifrado
            timestamp INTEGER NOT NULL
          )
          ''');

    await db.execute('''
          CREATE TABLE $_tableKeyStore (
            _id INTEGER PRIMARY KEY,
            private_key TEXT NOT NULL,
            public_key TEXT NOT NULL
          )
          ''');

    await db.execute('''
          CREATE TABLE $_tableSessionKeys (
            peer_username TEXT PRIMARY KEY,
            aes_key TEXT NOT NULL,
            hmac_key TEXT NOT NULL
          )
          ''');
  }

  Future<String> _encryptContent(String plaintext) async {
    if (_localDbKey == null) throw Exception("Chave local não carregada");

    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(
      utf8.encode(plaintext),
      secretKey: _localDbKey!,
      nonce: nonce,
    );

    return jsonEncode({
      'n': base64Url.encode(nonce),
      'c': base64Url.encode(secretBox.cipherText),
      'm': base64Url.encode(secretBox.mac.bytes),
    });
  }

  Future<String> _decryptContent(String dbContent) async {
    if (_localDbKey == null) throw Exception("Chave local não carregada");

    try {
      final map = jsonDecode(dbContent);
      final nonce = base64Url.decode(map['n']);
      final cipherText = base64Url.decode(map['c']);
      final macBytes = base64Url.decode(map['m']);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      final clearBytes = await _algo.decrypt(
        secretBox,
        secretKey: _localDbKey!,
      );
      return utf8.decode(clearBytes);
    } catch (e) {
      return "[Erro ao decifrar: mensagem corrompida ou chave inválida]";
    }
  }

  Future<int> insertMessage(ChatMessage message, String destinatario) async {
    Database db = await instance.database;

    final encryptedContent = await _encryptContent(message.content);

    return await db.insert(_tableConversas, {
      columnRemetente: message.from,
      columnDestinatario: destinatario,
      columnConteudo: encryptedContent, 
      columnTimestamp: DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ChatMessage>> getConversationHistory(String user1, String user2) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(_tableConversas,
        where: '($columnRemetente = ? AND $columnDestinatario = ?) OR ($columnRemetente = ? AND $columnDestinatario = ?)',
        whereArgs: [user1, user2, user2, user1],
        orderBy: '$columnTimestamp ASC');

    final List<ChatMessage> history = [];
    for (var i = 0; i < maps.length; i++) {
      final encryptedContent = maps[i][columnConteudo] as String;
      final decryptedContent = await _decryptContent(encryptedContent);
      
      history.add(ChatMessage(
        from: maps[i][columnRemetente],
        content: decryptedContent,
      ));
    }
    return history;
  }

  Future<void> saveKeyPair(String privateKey, String publicKey) async {
    Database db = await instance.database;
    await db.delete(_tableKeyStore); 
    await db.insert(_tableKeyStore, {
      '_id': 1,
      'private_key': privateKey,
      'public_key': publicKey,
    });
  }

  Future<String?> getPrivateKey() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(_tableKeyStore, limit: 1);
    if (maps.isNotEmpty) {
      return maps.first['private_key'] as String;
    }
    return null;
  }

  Future<void> saveSessionKeys(String peerUsername, String aesKeyB64, String hmacKeyB64) async {
    Database db = await instance.database;
    await db.insert(_tableSessionKeys, {
      'peer_username': peerUsername,
      'aes_key': aesKeyB64,
      'hmac_key': hmacKeyB64,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>?> getSessionKeys(String peerUsername) async {
    Database db = await instance.database;
    final maps = await db.query(
      _tableSessionKeys,
      where: 'peer_username = ?',
      whereArgs: [peerUsername],
    );

    if (maps.isNotEmpty) {
      return {
        'aes_key': maps.first['aes_key'] as String,
        'hmac_key': maps.first['hmac_key'] as String,
      };
    }
    return null;
  }
}