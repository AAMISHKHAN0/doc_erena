import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/storage/file_storage_service.dart';

void main() {
  late Directory tempDir;
  late FileStorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docerena_storage_test_');
    storageService = FileStorageService(basePath: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileStorageService Tests', () {
    test('writeAtomic stages to temporary file and atomically commits content', () async {
      final key = storageService.createOriginalKey('doc_1', 'page_1');
      final testData = Uint8List.fromList([1, 2, 3, 4, 5, 42, 99]);

      final writeResult = await storageService.writeAtomic(key, testData);

      expect(writeResult.isSuccess, isTrue);
      final writtenPath = writeResult.dataOrNull!;
      expect(await File(writtenPath).exists(), isTrue);

      // Verify content
      final readResult = await storageService.readFile(key);
      expect(readResult.isSuccess, isTrue);
      expect(readResult.dataOrNull, equals(testData));

      // Verify no leftover .tmp files
      final parentDir = File(writtenPath).parent;
      final tmpFiles = parentDir.listSync().where((f) => f.path.contains('.tmp'));
      expect(tmpFiles, isEmpty);
    });

    test('writeAtomic rejects empty 0-byte input to prevent data corruption', () async {
      final key = storageService.createOriginalKey('doc_1', 'page_empty');
      final emptyBytes = Uint8List(0);

      final result = await storageService.writeAtomic(key, emptyBytes);

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(StorageErrorCode.corruptedData));
    });

    test('resolveKey blocks directory traversal attempts', () {
      expect(
        () => storageService.resolveKey('../outside.txt'),
        throwsArgumentError,
      );
      expect(
        () => storageService.resolveKey('documents/../../secret.txt'),
        throwsArgumentError,
      );
    });

    test('deleteFile removes existing file safely', () async {
      final key = storageService.createOriginalKey('doc_1', 'page_to_delete');
      final testData = Uint8List.fromList([10, 20, 30]);

      await storageService.writeAtomic(key, testData);
      expect(await storageService.fileExists(key), isTrue);

      final deleteResult = await storageService.deleteFile(key);
      expect(deleteResult.isSuccess, isTrue);
      expect(await storageService.fileExists(key), isFalse);
    });
  });
}
