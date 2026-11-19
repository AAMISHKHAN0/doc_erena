import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/services/share/share_service.dart';

void main() {
  late Directory tempDir;
  late String validPdfPath;
  late String mockDatabasePath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docerena_share_unit_');

    // Create a dummy valid PDF file
    final pdfFile = File('${tempDir.path}/sample_export.pdf');
    await pdfFile.writeAsString('%PDF-1.4\nSample Content\n%%EOF');
    validPdfPath = pdfFile.path;

    // Create a mock database file
    final dbFile = File('${tempDir.path}/docerena.db');
    await dbFile.writeAsString('SQLite format 3');
    mockDatabasePath = dbFile.path;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ShareService - Security Checks & Permissions', () {
    test('security violation: sharing docerena.db or raw database is strictly rejected', () async {
      bool shareInvoked = false;
      final service = ShareService(
        shareInvoker: (files, {subject, text}) async {
          shareInvoked = true;
        },
      );

      final result = await service.sharePdf(
        pdfCachePath: mockDatabasePath,
        mimeType: 'application/pdf',
        subject: 'DatabaseLeakAttempt',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(ShareErrorCode.shareFailed));
      expect(result.errorOrNull?.message, contains('Security violation'));
      expect(shareInvoked, isFalse, reason: 'System share sheet must never be invoked for DB files');
    });

    test('security violation: path containing /database/ is rejected', () async {
      final service = ShareService();
      final result = await service.sharePdf(
        pdfCachePath: '/data/user/0/com.digitalerena.docerena/database/tables.pdf',
        mimeType: 'application/pdf',
        subject: 'DatabaseFolderLeak',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(ShareErrorCode.shareFailed));
    });

    test('returns fileNotFound when PDF cache path does not exist', () async {
      final service = ShareService();
      final result = await service.sharePdf(
        pdfCachePath: '${tempDir.path}/non_existent_doc_12345.pdf',
        mimeType: 'application/pdf',
        subject: 'MissingDoc',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(ShareErrorCode.fileNotFound));
    });
  });

  group('ShareService - System Share Sheet Execution', () {
    test('valid PDF passes to share_plus with correct MIME type and subject', () async {
      List<XFile>? sharedFiles;
      String? capturedSubject;

      final service = ShareService(
        shareInvoker: (files, {subject, text}) async {
          sharedFiles = files;
          capturedSubject = subject;
        },
      );

      final result = await service.sharePdf(
        pdfCachePath: validPdfPath,
        mimeType: 'application/pdf',
        subject: 'Monthly Invoice March 2026',
      );

      expect(result.isSuccess, isTrue);
      expect(sharedFiles, isNotNull);
      expect(sharedFiles!.length, equals(1));
      expect(sharedFiles!.first.path, equals(validPdfPath));
      expect(sharedFiles!.first.mimeType, equals('application/pdf'));
      expect(capturedSubject, equals('Monthly Invoice March 2026'));
    });
  });

  group('ShareService - Storage Access Framework Save Copy', () {
    test('saveCopyViaPicker succeeds when custom picker delegate provides path', () async {
      final targetDestination = '${tempDir.path}/saved_user_copy.pdf';

      final service = ShareService(
        savePickerInvoker: ({required sourcePath, required suggestedFileName}) async {
          return targetDestination;
        },
      );

      final result = await service.saveCopyViaPicker(
        sourceCachePath: validPdfPath,
        suggestedFileName: 'ExportedDoc.pdf',
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(targetDestination));
    });

    test('saveCopyViaPicker returns pickerCancelled when user cancels picker', () async {
      final service = ShareService(
        savePickerInvoker: ({required sourcePath, required suggestedFileName}) async {
          return null; // User cancelled
        },
      );

      final result = await service.saveCopyViaPicker(
        sourceCachePath: validPdfPath,
        suggestedFileName: 'ExportedDoc.pdf',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(ShareErrorCode.pickerCancelled));
    });

    test('saveCopyViaPicker default copy mechanism writes to destination folder', () async {
      final defaultSaveDir = '${tempDir.path}/user_exports';
      final service = ShareService(defaultSaveDirectory: defaultSaveDir);

      final result = await service.saveCopyViaPicker(
        sourceCachePath: validPdfPath,
        suggestedFileName: 'DefaultCopy.pdf',
      );

      expect(result.isSuccess, isTrue);
      final destPath = result.dataOrNull!;
      expect(destPath, contains('DefaultCopy.pdf'));
      expect(await File(destPath).exists(), isTrue);
    });
  });
}
