// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// **************************************************************************
// FloorGenerator
// **************************************************************************

abstract class $AppDatabaseBuilderContract {
  /// Adds migrations to the builder.
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations);

  /// Adds a database [Callback] to the builder.
  $AppDatabaseBuilderContract addCallback(Callback callback);

  /// Creates the database and initializes it.
  Future<AppDatabase> build();
}

// ignore: avoid_classes_with_only_static_members
class $FloorAppDatabase {
  /// Creates a database builder for a persistent database.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract databaseBuilder(String name) =>
      _$AppDatabaseBuilder(name);

  /// Creates a database builder for an in memory database.
  /// Information stored in an in memory database disappears when the process is killed.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract inMemoryDatabaseBuilder() =>
      _$AppDatabaseBuilder(null);
}

class _$AppDatabaseBuilder implements $AppDatabaseBuilderContract {
  _$AppDatabaseBuilder(this.name);

  final String? name;

  final List<Migration> _migrations = [];

  Callback? _callback;

  @override
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations) {
    _migrations.addAll(migrations);
    return this;
  }

  @override
  $AppDatabaseBuilderContract addCallback(Callback callback) {
    _callback = callback;
    return this;
  }

  @override
  Future<AppDatabase> build() async {
    final path = name != null
        ? await sqfliteDatabaseFactory.getDatabasePath(name!)
        : ':memory:';
    final database = _$AppDatabase();
    database.database = await database.open(path, _migrations, _callback);
    return database;
  }
}

class _$AppDatabase extends AppDatabase {
  _$AppDatabase([StreamController<String>? listener]) {
    changeListener = listener ?? StreamController<String>.broadcast();
  }

  SettingDao? _settingDaoInstance;

  TranscriptionDao? _transcriptionDaoInstance;

  Future<sqflite.Database> open(
    String path,
    List<Migration> migrations, [
    Callback? callback,
  ]) async {
    final databaseOptions = sqflite.OpenDatabaseOptions(
      version: 6,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await callback?.onConfigure?.call(database);
      },
      onOpen: (database) async {
        await callback?.onOpen?.call(database);
      },
      onUpgrade: (database, startVersion, endVersion) async {
        await MigrationAdapter.runMigrations(
          database,
          startVersion,
          endVersion,
          migrations,
        );

        await callback?.onUpgrade?.call(database, startVersion, endVersion);
      },
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE IF NOT EXISTS `settings` (`key` TEXT NOT NULL, `value` TEXT NOT NULL, PRIMARY KEY (`key`))',
        );
        await database.execute(
          'CREATE TABLE IF NOT EXISTS `transcriptions` (`id` TEXT NOT NULL, `text` TEXT NOT NULL, `raw_text` TEXT, `created_at` TEXT NOT NULL, `duration_ms` INTEGER NOT NULL, `provider` TEXT NOT NULL, `model` TEXT NOT NULL, `provider_config` TEXT NOT NULL, PRIMARY KEY (`id`))',
        );

        await callback?.onCreate?.call(database, version);
      },
    );
    return sqfliteDatabaseFactory.openDatabase(path, options: databaseOptions);
  }

  @override
  SettingDao get settingDao {
    return _settingDaoInstance ??= _$SettingDao(database, changeListener);
  }

  @override
  TranscriptionDao get transcriptionDao {
    return _transcriptionDaoInstance ??= _$TranscriptionDao(
      database,
      changeListener,
    );
  }
}

class _$SettingDao extends SettingDao {
  _$SettingDao(this.database, this.changeListener)
    : _queryAdapter = QueryAdapter(database),
      _settingEntityInsertionAdapter = InsertionAdapter(
        database,
        'settings',
        (SettingEntity item) => <String, Object?>{
          'key': item.key,
          'value': item.value,
        },
      );

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<SettingEntity> _settingEntityInsertionAdapter;

  @override
  Future<SettingEntity?> findByKey(String key) async {
    return _queryAdapter.query(
      'SELECT * FROM settings WHERE `key` = ?1',
      mapper: (Map<String, Object?> row) =>
          SettingEntity(row['key'] as String, row['value'] as String),
      arguments: [key],
    );
  }

  @override
  Future<List<SettingEntity>> getAll() async {
    return _queryAdapter.queryList(
      'SELECT * FROM settings',
      mapper: (Map<String, Object?> row) =>
          SettingEntity(row['key'] as String, row['value'] as String),
    );
  }

  @override
  Future<void> deleteByKey(String key) async {
    await _queryAdapter.queryNoReturn(
      'DELETE FROM settings WHERE `key` = ?1',
      arguments: [key],
    );
  }

  @override
  Future<void> insertSetting(SettingEntity setting) async {
    await _settingEntityInsertionAdapter.insert(
      setting,
      OnConflictStrategy.replace,
    );
  }
}

class _$TranscriptionDao extends TranscriptionDao {
  _$TranscriptionDao(this.database, this.changeListener)
    : _queryAdapter = QueryAdapter(database),
      _transcriptionEntityInsertionAdapter = InsertionAdapter(
        database,
        'transcriptions',
        (TranscriptionEntity item) => <String, Object?>{
          'id': item.id,
          'text': item.text,
          'raw_text': item.rawText,
          'created_at': item.createdAt,
          'duration_ms': item.durationMs,
          'provider': item.provider,
          'model': item.model,
          'provider_config': item.providerConfig,
        },
      );

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<TranscriptionEntity>
  _transcriptionEntityInsertionAdapter;

  @override
  Future<List<TranscriptionEntity>> getAll() async {
    return _queryAdapter.queryList(
      'SELECT * FROM transcriptions ORDER BY created_at DESC',
      mapper: (Map<String, Object?> row) => TranscriptionEntity(
        id: row['id'] as String,
        text: row['text'] as String,
        rawText: row['raw_text'] as String?,
        createdAt: row['created_at'] as String,
        durationMs: row['duration_ms'] as int,
        provider: row['provider'] as String,
        model: row['model'] as String,
        providerConfig: row['provider_config'] as String,
      ),
    );
  }

  @override
  Future<void> deleteById(String id) async {
    await _queryAdapter.queryNoReturn(
      'DELETE FROM transcriptions WHERE id = ?1',
      arguments: [id],
    );
  }

  @override
  Future<void> deleteAll() async {
    await _queryAdapter.queryNoReturn('DELETE FROM transcriptions');
  }

  @override
  Future<void> insertItem(TranscriptionEntity item) async {
    await _transcriptionEntityInsertionAdapter.insert(
      item,
      OnConflictStrategy.replace,
    );
  }
}
