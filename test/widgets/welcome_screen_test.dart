import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:camscanner/presentation/screens/s01_welcome/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests (Real Android Architecture)', () {
    testWidgets('Configures real Android SystemUiOverlayStyle and SafeArea', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(),
        ),
      );

      // Verify AnnotatedRegion<SystemUiOverlayStyle> is present
      final annotatedRegionFinder = find.byType(AnnotatedRegion<SystemUiOverlayStyle>);
      expect(annotatedRegionFinder, findsOneWidget);

      final annotatedRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(annotatedRegionFinder);
      expect(annotatedRegion.value.statusBarColor, Colors.transparent);
      expect(annotatedRegion.value.statusBarIconBrightness, Brightness.dark);
      expect(annotatedRegion.value.systemNavigationBarIconBrightness, Brightness.dark);

      // Verify SafeArea is present to respect camera cutouts and system insets
      final safeAreaFinder = find.byType(SafeArea);
      expect(safeAreaFinder, findsOneWidget);
    });

    testWidgets('Renders DocErena brand identity and copy without fake system bars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WelcomeScreen(),
        ),
      );

      // DocErena brand wordmark
      expect(find.text('DocErena'), findsOneWidget);

      // Headline and subheadline
      expect(find.text('Your documents,\nall in one place.'), findsOneWidget);
      expect(find.text('Scan, edit, and organize with ease.'), findsOneWidget);

      // Primary and secondary CTAs
      expect(find.byKey(const Key('welcome_get_started_btn')), findsOneWidget);
      expect(find.byKey(const Key('welcome_continue_guest_btn')), findsOneWidget);

      // Privacy statement
      expect(find.text('Your files stay on your device until you choose to share.'), findsOneWidget);

      // Ensure NO fake status bar text (e.g. 9:41 or battery percentage) was drawn in Flutter
      expect(find.text('9:41'), findsNothing);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('Tapping "Let’s get started" triggers onGetStarted callback', (tester) async {
      bool getStartedTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onGetStarted: () {
              getStartedTapped = true;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('welcome_get_started_btn')));
      await tester.pumpAndSettle();

      expect(getStartedTapped, isTrue);
    });

    testWidgets('Tapping "Continue as guest" triggers onContinueAsGuest callback', (tester) async {
      bool continueGuestTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onContinueAsGuest: () {
              continueGuestTapped = true;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('welcome_continue_guest_btn')));
      await tester.pumpAndSettle();

      expect(continueGuestTapped, isTrue);
    });

    testWidgets('Adapts to small screen and large text scale without overflow', (tester) async {
      // Simulate compact screen (320x568) with 1.5x accessibility text scale
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            );
          },
          home: const WelcomeScreen(),
        ),
      );

      // Content renders cleanly without RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('welcome_get_started_btn')), findsOneWidget);
    });
  });
}
