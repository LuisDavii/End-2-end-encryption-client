import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:client_chat/models/chat_models.dart';

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

  Future<void> initForUser(String username) async {
    if (_currentUser == username && _database != null) {
      return;
    }
    _currentUser = username;
    
    final dbName = 'Chat_$username.db';
    String path = join(await getDatabasesPath(), dbName);
    _database = await openDatabase(path, version: 1, onCreate: _onCreate);
    print("Banco de dados inicializado para o usuário: $username em $path");
  }

   Future<Database> get database async {
    if (_database == null || _currentUser == null) {
      throw Exception("DatabaseHelper não foi inicializado. Chame initForUser() após o login.");
    }
    return _database!;
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $_tableConversas (
            _id INTEGER PRIMARY KEY AUTOINCREMENT,
            remetente TEXT NOT NULL,
            destinatario TEXT NOT NULL,
            conteudo TEXT NOT NULL,
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

  Future<void> saveKeyPair(String privateKey, String publicKey) async {
    Database db = await instance.database;
    await db.delete(_tableKeyStore); 
    await db.insert(_tableKeyStore, {
      '_id': 1,
      'private_key': privateKey,
      'public_key': publicKey,
    });
    print("Par de chaves guardado localmente.");
  }

  Future<String?> getPrivateKey() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(_tableKeyStore, limit: 1);
    if (maps.isNotEmpty) {
      return maps.first['private_key'] as String;
    }
    return null;
  }

  Future<int> insertMessage(ChatMessage message, String destinatario) async {
    Database db = await instance.database;
    return await db.insert(_tableConversas, {
      columnRemetente: message.from,
      columnDestinatario: destinatario,
      columnConteudo: message.content,
      columnTimestamp: DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> saveSessionKeys(String peerUsername, String aesKeyB64, String hmacKeyB64) async {
    Database db = await instance.database;
    await db.insert(_tableSessionKeys, {
      'peer_username': peerUsername,
      'aes_key': aesKeyB64,
      'hmac_key': hmacKeyB64,
    }, conflictAlgorithm: ConflictAlgorithm.replace); 
    print("[DB] Chaves de sessão salvas para $peerUsername");
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

  Future<List<ChatMessage>> getConversationHistory(String user1, String user2) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(_tableConversas,
        where: '($columnRemetente = ? AND $columnDestinatario = ?) OR ($columnRemetente = ? AND $columnDestinatario = ?)',
        whereArgs: [user1, user2, user2, user1],
        orderBy: '$columnTimestamp ASC');

    return List.generate(maps.length, (i) {
      return ChatMessage(
        from: maps[i][columnRemetente],
        content: maps[i][columnConteudo],
      );
    });
  }
}