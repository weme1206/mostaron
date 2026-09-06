import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'mostaron.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: (db, v) async {
        await _createTables(db);
      },
      onUpgrade: _upgrade,
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY, name TEXT, base_url TEXT, api_key TEXT,
        model TEXT, models TEXT, is_default INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE characters (
        id TEXT PRIMARY KEY, name TEXT, avatar TEXT, persona TEXT,
        personality TEXT, tone TEXT, background TEXT, greeting TEXT,
        chat_background TEXT, provider_id TEXT, model TEXT,
        reply_style TEXT, worldbook_ids TEXT, settings_json TEXT,
        user_name TEXT, user_gender TEXT, user_relation TEXT, user_background TEXT,
        pinned INTEGER, last_activity INTEGER, created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY, character_id TEXT, title TEXT,
        created_at INTEGER, updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY, session_id TEXT, group_id TEXT, role TEXT,
        content TEXT, reasoning TEXT, sender_id TEXT, created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY, name TEXT, avatar TEXT, background TEXT,
        member_ids TEXT, reply_mode TEXT, max_replies INTEGER,
        user_name TEXT, user_gender TEXT, user_relation TEXT, user_background TEXT,
        pinned INTEGER, provider_id TEXT, model TEXT, reply_style TEXT,
        auto_memory_every INTEGER, last_activity INTEGER, worldbook_ids TEXT,
        created_at INTEGER, updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY, character_id TEXT, content TEXT,
        pinned INTEGER, created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE worldbook (
        id TEXT PRIMARY KEY, character_id TEXT, name TEXT,
        keywords TEXT, content TEXT, enabled INTEGER, created_at INTEGER
      )
    ''');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  Future<void> _upgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN reply_style TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN group_id TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN sender_id TEXT');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE groups (
            id TEXT PRIMARY KEY, name TEXT, avatar TEXT, background TEXT,
            member_ids TEXT, reply_mode TEXT, max_replies INTEGER, created_at INTEGER
          )
        ''');
      } catch (_) {}
    }
    if (oldV < 3) {
      try {
        await db.execute('ALTER TABLE providers ADD COLUMN models TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN settings_json TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN user_name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN user_gender TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN user_relation TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN user_background TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN user_name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN user_gender TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN user_relation TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN user_background TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN updated_at INTEGER');
      } catch (_) {}
    }
    if (oldV < 4) {
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN pinned INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN pinned INTEGER');
      } catch (_) {}
    }
    if (oldV < 5) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN reasoning TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE characters ADD COLUMN last_activity INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN provider_id TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN model TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN reply_style TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN last_activity INTEGER');
      } catch (_) {}
    }
    if (oldV < 6) {
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN auto_memory_every INTEGER');
      } catch (_) {}
    }
    if (oldV < 7) {
      try {
        await db.execute('ALTER TABLE groups ADD COLUMN worldbook_ids TEXT');
      } catch (_) {}
      try {
        // 世界书改为全局管理：丢弃旧的“按角色/群单独存”的条目，全局池从空白开始
        await db.delete('worldbook', where: 'character_id IS NOT NULL');
      } catch (_) {}
    }
  }

  Future<void> saveSettings(AppSettings s) async {
    final d = await db;
    await d.insert('settings', {'key': 'app', 'value': jsonEncode(s.toMap())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AppSettings> loadSettings() async {
    final d = await db;
    final r = await d.query('settings', where: 'key = ?', whereArgs: ['app']);
    if (r.isEmpty) return AppSettings();
    return AppSettings.fromMap(jsonDecode(r.first['value'] as String) as Map<String, dynamic>);
  }

  // ---------------- Providers ----------------
  Future<List<ProviderConfig>> getProviders() async {
    final d = await db;
    final rows = await d.query('providers', orderBy: 'is_default DESC, name ASC');
    return rows.map(ProviderConfig.fromMap).toList();
  }

  Future<void> upsertProvider(ProviderConfig c) async {
    final d = await db;
    await d.insert('providers', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteProvider(String id) async {
    final d = await db;
    await d.delete('providers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setDefaultProvider(String id) async {
    final d = await db;
    await d.rawUpdate('UPDATE providers SET is_default = 0');
    await d.rawUpdate('UPDATE providers SET is_default = 1 WHERE id = ?', [id]);
  }

  Future<ProviderConfig?> getProvider(String id) async {
    final d = await db;
    final rows = await d.query('providers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ProviderConfig.fromMap(rows.first);
  }

  Future<ProviderConfig?> getDefaultProvider() async {
    final d = await db;
    final rows = await d.query('providers', where: 'is_default = 1', limit: 1);
    if (rows.isEmpty) return null;
    return ProviderConfig.fromMap(rows.first);
  }

  // ---------------- Characters ----------------
  Future<List<Character>> getCharacters() async {
    final d = await db;
    final rows = await d.query('characters', orderBy: 'created_at ASC');
    return rows.map(Character.fromMap).toList();
  }

  Future<Character?> getCharacter(String id) async {
    final d = await db;
    final rows = await d.query('characters', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Character.fromMap(rows.first);
  }

  Future<void> upsertCharacter(Character c) async {
    final d = await db;
    await d.insert('characters', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCharacter(String id) async {
    final d = await db;
    final sessions = await d.query('sessions', where: 'character_id = ?', whereArgs: [id]);
    for (final s in sessions) {
      await d.delete('messages', where: 'session_id = ?', whereArgs: [s['id']]);
    }
    await d.delete('sessions', where: 'character_id = ?', whereArgs: [id]);
    await d.delete('messages', where: 'sender_id = ?', whereArgs: [id]);
    await d.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Sessions ----------------
  Future<List<ChatSession>> getSessionsForCharacter(String characterId) async {
    final d = await db;
    final rows = await d.query('sessions',
        where: 'character_id = ?', whereArgs: [characterId], orderBy: 'updated_at DESC');
    return rows.map(ChatSession.fromMap).toList();
  }

  Future<ChatSession?> getSession(String id) async {
    final d = await db;
    final rows = await d.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ChatSession.fromMap(rows.first);
  }

  Future<void> upsertSession(ChatSession s) async {
    final d = await db;
    await d.insert('sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSession(String id) async {
    final d = await db;
    await d.delete('messages', where: 'session_id = ?', whereArgs: [id]);
    await d.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Messages ----------------
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final d = await db;
    final rows = await d.query('messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<List<ChatMessage>> getGroupMessages(String groupId) async {
    final d = await db;
    final rows = await d.query('messages',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<ChatMessage?> getMessage(String id) async {
    final d = await db;
    final rows = await d.query('messages', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  Future<void> insertMessage(ChatMessage m) async {
    final d = await db;
    await d.insert('messages', m.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    final t = DateTime.now().millisecondsSinceEpoch;
    if (m.sessionId != null) {
      await d.update('sessions', {'updated_at': t}, where: 'id = ?', whereArgs: [m.sessionId]);
      final sess = await d.query('sessions', where: 'id = ?', whereArgs: [m.sessionId], limit: 1);
      if (sess.isNotEmpty) {
        await d.update('characters', {'last_activity': t},
            where: 'id = ?', whereArgs: [sess.first['character_id']]);
      }
    }
    if (m.groupId != null) {
      await d.update('groups', {'updated_at': t, 'last_activity': t},
          where: 'id = ?', whereArgs: [m.groupId]);
    }
  }

  Future<void> updateMessageContent(String id, String content) async {
    final d = await db;
    await d.update('messages', {'content': content}, where: 'id = ?', whereArgs: [id]);
  }

  /// 某角色最近一条消息内容
  Future<String> lastMessageForCharacter(String characterId) async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT content FROM messages
      WHERE session_id IN (SELECT id FROM sessions WHERE character_id = ?)
      ORDER BY created_at DESC LIMIT 1
    ''', [characterId]);
    return rows.isEmpty ? '' : (rows.first['content'] as String? ?? '');
  }

  /// 某群聊最近一条消息内容
  Future<String> lastMessageForGroup(String groupId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT content FROM messages WHERE group_id = ? ORDER BY created_at DESC LIMIT 1', [groupId]);
    return rows.isEmpty ? '' : (rows.first['content'] as String? ?? '');
  }

  Future<void> deleteMessage(String id) async {
    final d = await db;
    await d.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _touch(Database d, String table, String id) async {
    final t = DateTime.now().millisecondsSinceEpoch;
    await d.update(table, {'updated_at': t}, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Groups ----------------
  Future<List<ChatGroup>> getGroups() async {
    final d = await db;
    final rows = await d.query('groups', orderBy: 'created_at ASC');
    return rows.map(ChatGroup.fromMap).toList();
  }

  Future<ChatGroup?> getGroup(String id) async {
    final d = await db;
    final rows = await d.query('groups', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ChatGroup.fromMap(rows.first);
  }

  Future<void> upsertGroup(ChatGroup g) async {
    final d = await db;
    await d.insert('groups', g.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteGroup(String id) async {
    final d = await db;
    await d.delete('messages', where: 'group_id = ?', whereArgs: [id]);
    await d.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Memories ----------------
  Future<List<MemoryItem>> getMemories(String? characterId) async {
    final d = await db;
    final rows = characterId == null
        ? await d.query('memories', where: 'character_id IS NULL', orderBy: 'created_at ASC')
        : await d.query('memories',
            where: 'character_id = ?', whereArgs: [characterId], orderBy: 'created_at ASC');
    return rows.map(MemoryItem.fromMap).toList();
  }

  Future<int> countMemories(String? characterId) async {
    final d = await db;
    final cnt = characterId == null
        ? await d.rawQuery('SELECT COUNT(*) c FROM memories WHERE character_id IS NULL')
        : await d.rawQuery('SELECT COUNT(*) c FROM memories WHERE character_id = ?', [characterId]);
    return Sqflite.firstIntValue(cnt) ?? 0;
  }

  Future<void> pruneMemories(String? characterId, int keep) async {
    final d = await db;
    final rows = characterId == null
        ? await d.query('memories', where: 'character_id IS NULL AND pinned = 0', orderBy: 'created_at ASC')
        : await d.query('memories',
            where: 'character_id = ? AND pinned = 0', whereArgs: [characterId], orderBy: 'created_at ASC');
    if (rows.length > keep) {
      for (int i = 0; i < rows.length - keep; i++) {
        await d.delete('memories', where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
  }

  Future<void> upsertMemory(MemoryItem m) async {
    final d = await db;
    await d.insert('memories', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMemory(String id) async {
    final d = await db;
    await d.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Worldbook ----------------
  Future<List<WorldbookEntry>> getWorldbook(String? characterId) async {
    final d = await db;
    final rows = characterId == null
        ? await d.query('worldbook', where: 'character_id IS NULL', orderBy: 'created_at ASC')
        : await d.query('worldbook',
            where: 'character_id = ?', whereArgs: [characterId], orderBy: 'created_at ASC');
    return rows.map(WorldbookEntry.fromMap).toList();
  }

  Future<void> upsertWorldbook(WorldbookEntry w) async {
    final d = await db;
    await d.insert('worldbook', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWorldbook(String id) async {
    final d = await db;
    await d.delete('worldbook', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Full export / import ----------------
  Future<Map<String, dynamic>> exportAll() async {
    final d = await db;
    return {
      'app': 'mostaron',
      'version': 2,
      'settings': await d.query('settings'),
      'providers': await d.query('providers'),
      'characters': await d.query('characters'),
      'sessions': await d.query('sessions'),
      'messages': await d.query('messages'),
      'groups': await d.query('groups'),
      'memories': await d.query('memories'),
      'worldbook': await d.query('worldbook'),
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final d = await db;
    final tables = ['settings', 'providers', 'characters', 'sessions', 'messages', 'groups', 'memories', 'worldbook'];
    for (final t in tables) {
      final rows = data[t];
      if (rows is List) {
        for (final r in rows) {
          try {
            // 不覆盖已存在数据：仅插入新记录（同 id 跳过）
            await d.insert(t, r as Map<String, dynamic>, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> clearAll() async {
    final d = await db;
    for (final t in ['settings', 'providers', 'characters', 'sessions', 'messages', 'groups', 'memories', 'worldbook']) {
      await d.delete(t);
    }
  }
}
