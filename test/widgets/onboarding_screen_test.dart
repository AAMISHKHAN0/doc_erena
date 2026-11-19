import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:camscanner/presentation/screens/s01_welcome/onboarding_screen.dart';

void main() {
  group('OnboardingScreen Widget Tests (Multi-Step Onboarding)', () {
    testWidgets('Renders real Android SystemUiOverlayStyle and SafeArea', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );

      // Verify AnnotatedRegion<SystemUiOverlayStyle> is present
      final annotatedRegionFinder = find.byType(AnnotatedRegion<SystemUiOverlayStyle>);
      expect(annotatedRegionFinder, findsOneWidget);

      final annotatedRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(annotatedRegionFinder);
      expect(annotatedRegion.value.statusBarColor, Colors.transparent);
      expect(annotatedRegion.value.statusBarIconBrightness, Brightness.dark);

      // Verify SafeArea is present
      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('Renders header with Back button, Logo, and Skip button', (tester) async {
      bool backTapped = false;
      bool skipTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onBack: () => backTapped = true,
            onSkip: () => skipTapped = true,
          ),
        ),
      );

      // Logo and Header buttons
      expect(find.text('DocErena'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_btn')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_back_btn')));
      await tester.pumpAndSettle();
      expect(backTapped, isTrue);

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();
      expect(skipTapped, isTrue);
    });

    testWidgets('Step 1: Renders "1 of 2" badge, headline, and subheadline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );

      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Scan in seconds'), findsOneWidget);
      expect(find.text('Turn paper documents into clear\ndigital files.'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_next_btn')), findsOneWidget);
    });

    testWidgets('Step transition: Tapping Next advances to Step 2 ("Edit and organize")', (tester) async {
      bool nextCallbackFired = false;
      bool homeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onNext: () => nextCallbackFired = true,
            onGoToHome: () => homeTapped = true,
          ),
        ),
      );

      // Initially on Step 1
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Scan in seconds'), findsOneWidget);

      // Tap Next
      await tester.tap(find.byKey(const Key('onboarding_next_btn')));
      await tester.pumpAndSettle();

      expect(nextCallbackFired, isTrue);

      // Now on Step 2
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('Edit and organize'), findsOneWidget);
      expect(find.text('Keep your documents ready\nwhenever you need them.'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_go_home_btn')), findsOneWidget);

      // Tap Go to home
      await tester.tap(find.byKey(const Key('onboarding_go_home_btn')));
      await tester.pumpAndSettle();

      expect(homeTapped, isTrue);
    });

    testWidgets('Step 2 Back navigation returns to Step 1', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(initialStep: 1),
        ),
      );

      // Initially on Step 2
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('Edit and organize'), findsOneWidget);

      // Tap Back
      await tester.tap(find.byKey(const Key('onboarding_back_btn')));
      await tester.pumpAndSettle();

      // Should be back on Step 1
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Scan in seconds'), findsOneWidget);
    });

    testWidgets('Continue as guest button triggers callback', (tester) async {
      bool guestTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onContinueAsGuest: () => guestTapped = true,
          ),
        ),
      );

      expect(find.byKey(const Key('onboarding_continue_guest_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_continue_guest_btn')));
      await tester.pumpAndSettle();

      expect(guestTapped, isTrue);
    });

    testWidgets('Adapts to larger text scale factors (1.4x accessibility font scale)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.4),
              size: Size(360, 640),
            ),
            child: const OnboardingScreen(),
          ),
        ),
      );

      // Should render without RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.text('Scan in seconds'), findsOneWidget);

      // Advance to Step 2 under 1.4x scale
      await tester.tap(find.byKey(const Key('onboarding_next_btn')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Edit and organize'), findsOneWidget);
    });
  });
}
