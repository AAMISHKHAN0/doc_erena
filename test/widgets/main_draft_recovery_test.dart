import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/main.dart';

class MockDraftRepository implements IDocumentRepository {
  DocumentEntity? activeDraft;
  final List<PageEntity> draftPages = [];
  bool draftDiscarded = false;

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async {
    return Success(activeDraft);
  }

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    if (activeDraft?.id == draftId) {
      activeDraft = null;
      draftDiscarded = true;
    }
    return const Success(null);
  }

  @override
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId) async {
    return Success(draftPages);
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async {
    return const Success([]);
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id) async {
    return Success(activeDraft);
  }

  @override
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  }) async {
    return Success(document);
  }

  @override
  Future<Result<void, StorageError>> deleteDocument(String id) async {
    return const Success(null);
  }

  @override
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle) async {
    return const Success(null);
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async {
    return const Success([]);
  }
}

void main() {
  late MockDraftRepository mockRepo;

  setUp(() {
    mockRepo = MockDraftRepository();
  });

  group('Main App - Startup Draft Recovery Banner', () {
    testWidgets('when no active draft exists, recovery banner is not displayed', (tester) async {
      mockRepo.activeDraft = null;

      await tester.pumpWidget(
        DocErenaApp(repository: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active_draft_banner')), findsNothing);
      expect(find.text('You have an unfinished document. Resume or Discard?'), findsNothing);
    });

    testWidgets('when active draft exists, displays prompt banner with Resume and Discard actions', (tester) async {
      mockRepo.activeDraft = DocumentEntity(
        id: 'draft_123',
        title: 'DocErena_20261107_120000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      await tester.pumpWidget(
        DocErenaApp(repository: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active_draft_banner')), findsOneWidget);
      expect(find.text('You have an unfinished document. Resume or Discard?'), findsOneWidget);
      expect(find.byKey(const Key('draft_resume_btn')), findsOneWidget);
      expect(find.byKey(const Key('draft_discard_btn')), findsOneWidget);
    });

    testWidgets('tapping Discard calls repository.discardDraft and removes banner', (tester) async {
      mockRepo.activeDraft = DocumentEntity(
        id: 'draft_123',
        title: 'DocErena_20261107_120000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      await tester.pumpWidget(
        DocErenaApp(repository: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active_draft_banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('draft_discard_btn')));
      await tester.pumpAndSettle();

      expect(mockRepo.draftDiscarded, isTrue);
      expect(find.byKey(const Key('active_draft_banner')), findsNothing);
      expect(find.text('Unfinished draft discarded.'), findsOneWidget);
    });

    testWidgets('tapping Resume dismisses banner and navigates to organizer screen', (tester) async {
      mockRepo.activeDraft = DocumentEntity(
        id: 'draft_123',
        title: 'DocErena_20261107_120000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      await tester.pumpWidget(
        DocErenaApp(repository: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('draft_resume_btn')));
      await tester.pumpAndSettle();

      // Banner should be dismissed
      expect(find.byKey(const Key('active_draft_banner')), findsNothing);
      // Organizer screen should now be navigated to
      expect(find.byKey(const Key('page_organizer_screen')), findsOneWidget);
    });
  });
}
