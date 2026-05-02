import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicetype/models/transcription.dart';
import 'package:voicetype/database/app_database.dart';
import 'package:voicetype/services/history_db.dart';

void main() {
  // Initialize sqflite FFI for desktop testing
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.resetForTest();
  });

  tearDownAll(() async {
    await AppDatabase.resetForTest();
  });

  group('HistoryDb', () {
    test('insert and getAll', () async {
      final db = HistoryDb.instance;

      final item = Transcription(
        id: 'test-001',
        text: 'Test transcription text',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 5),
        llmProcessingDuration: const Duration(milliseconds: 1200),
        llmInputTokens: 88,
        llmOutputTokens: 21,
        provider: 'TestProvider',
        model: 'test-model',
        providerConfigJson: '{}',
      );

      await db.insert(item);
      final items = await db.getAll();

      expect(items.any((t) => t.id == 'test-001'), isTrue);
      final found = items.firstWhere((t) => t.id == 'test-001');
      expect(found.text, 'Test transcription text');
      expect(found.llmProcessingDuration?.inMilliseconds, 1200);
      expect(found.llmInputTokens, 88);
      expect(found.llmOutputTokens, 21);
      expect(found.provider, 'TestProvider');
      expect(found.model, 'test-model');
    });

    test('insert replaces existing item with same id', () async {
      final db = HistoryDb.instance;

      final item1 = Transcription(
        id: 'test-replace-001',
        text: 'Original text',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 3),
        provider: 'Provider',
        model: 'model',
        providerConfigJson: '{}',
      );

      final item2 = Transcription(
        id: 'test-replace-001',
        text: 'Updated text',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 5),
        provider: 'Provider',
        model: 'model',
        providerConfigJson: '{}',
      );

      await db.insert(item1);
      await db.insert(item2);

      final items = await db.getAll();
      final matches = items.where((t) => t.id == 'test-replace-001').toList();
      expect(matches.length, 1);
      expect(matches.first.text, 'Updated text');
    });

    test('deleteById removes specific item', () async {
      final db = HistoryDb.instance;

      final item = Transcription(
        id: 'test-delete-001',
        text: 'To be deleted',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 2),
        provider: 'Provider',
        model: 'model',
        providerConfigJson: '{}',
      );

      await db.insert(item);
      await db.deleteById('test-delete-001');

      final items = await db.getAll();
      expect(items.any((t) => t.id == 'test-delete-001'), isFalse);
    });

    test('clear removes all items', () async {
      final db = HistoryDb.instance;

      for (var i = 0; i < 3; i++) {
        await db.insert(
          Transcription(
            id: 'test-clear-$i',
            text: 'Item $i',
            createdAt: DateTime.now(),
            duration: const Duration(seconds: 1),
            provider: 'Provider',
            model: 'model',
            providerConfigJson: '{}',
          ),
        );
      }

      await db.clear();
      final items = await db.getAll();
      expect(items, isEmpty);
    });

    test('getAll returns items ordered by created_at DESC', () async {
      final db = HistoryDb.instance;
      await db.clear();

      final now = DateTime.now();
      final items = [
        Transcription(
          id: 'order-1',
          text: 'First',
          createdAt: now.subtract(const Duration(hours: 2)),
          duration: const Duration(seconds: 1),
          provider: 'P',
          model: 'm',
          providerConfigJson: '{}',
        ),
        Transcription(
          id: 'order-3',
          text: 'Third (newest)',
          createdAt: now,
          duration: const Duration(seconds: 1),
          provider: 'P',
          model: 'm',
          providerConfigJson: '{}',
        ),
        Transcription(
          id: 'order-2',
          text: 'Second',
          createdAt: now.subtract(const Duration(hours: 1)),
          duration: const Duration(seconds: 1),
          provider: 'P',
          model: 'm',
          providerConfigJson: '{}',
        ),
      ];

      for (final item in items) {
        await db.insert(item);
      }

      final result = await db.getAll();
      expect(result.length, 3);
      expect(result[0].id, 'order-3'); // newest first
      expect(result[1].id, 'order-2');
      expect(result[2].id, 'order-1'); // oldest last
    });
  });
}
