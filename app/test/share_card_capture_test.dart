import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/features/share/presentation/period_card_data.dart';
import 'package:kitabi/features/share/presentation/period_share_card.dart';
import 'package:kitabi/features/share/presentation/share_capture.dart';
import 'package:kitabi/features/share/presentation/share_sheet_scaffold.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// A share card must leave the app as an *image*.
///
/// Twice the owner reported "only the text is getting shared" (26 Aug and
/// 6 Sep 2026). The second time the cause was the readiness check itself:
/// `RenderObject.debugNeedsPaint` assigns its value only inside an `assert`,
/// so in a release build the getter throws — and the capture's silent
/// text-only fallback swallowed that on every phone while every debug run
/// and every test rasterised fine. These tests mock the share channel so the
/// *kind* of share is asserted (a file, never bare text), and the fallback
/// now reports through `FlutterError`, which the harness turns into a
/// failure rather than a snackbar nobody reads.
PeriodCardData _data() => const PeriodCardData(
      heroValue: '12h 40m',
      heroLabel: 'read this month',
      subLine: 'Across 9 sittings and 3 books',
      closingLine: 'kitabi.in',
    );

class _ShareChannel {
  final calls = <MethodCall>[];
  late final Directory temp;

  void install() {
    temp = Directory.systemTemp.createTempSync('kitabi-share-test');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        calls.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
  }

  void remove() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  late final void Function(FlutterErrorDetails details, String testDescription) reportOriginal;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The cards set Fraunces through google_fonts; on the host the font isn't
    // bundled and the miss is reported as a test exception. Same filter every
    // card test in this suite uses.
    reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
  });

  tearDownAll(() {
    reportTestException = reportOriginal;
  });

  testWidgets('captureCardPng rasterises the period card at share width', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox(
          width: 168,
          child: RepaintBoundary(key: key, child: PeriodShareCard(data: _data())),
        ),
      ),
    ));
    await _settle(tester, 4);

    // Started outside runAsync — the capture awaits the end of a frame, and
    // only pumps produce frames here — then awaited on the real event loop,
    // which `toImage` needs.
    final pending = captureCardPng(key);
    await _settle(tester, 6);
    final png = await tester.runAsync(() => pending.timeout(const Duration(seconds: 20)));
    expect(png, isNotNull);
    // PNG signature.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      return frame.image;
    });
    expect(image!.width, greaterThanOrEqualTo(1080), reason: 'a story is 1080 wide');
  });

  test('the capture path reads no debug-only render getter', () {
    // A widget test runs in debug mode, where `debugNeedsPaint` answers — so
    // no test above can fail the way the phone did. This is the one check
    // that can: the file that rasterises the card must not touch a `debug*`
    // member of a render object, because every one of them is a debug-mode
    // contract that a release build is free to throw on.
    // Code only — the comments in that file name the getter on purpose.
    final source = File('lib/features/share/presentation/share_capture.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(RegExp(r'\.debug[A-Z]\w*').hasMatch(source), isFalse,
        reason: 'debugNeedsPaint threw LateInitializationError in release (6 Sep 2026)');
  });

  testWidgets('Share on the sheet hands the OS a PNG file, never bare text', (tester) async {
    final channel = _ShareChannel()..install();
    addTearDown(channel.remove);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ShareSheetScaffold(
          title: 'Share',
          card: PeriodShareCard(data: _data()),
          previewWidth: 168,
          shareText: () => 'My month in books',
          copyLabel: 'Copy',
          copyIcon: Icons.copy,
          onCopy: () {},
          shareLabel: 'Share image',
        ),
      ),
    ));
    await _settle(tester, 4);

    await tester.tap(find.text('Share image'));
    await _settle(tester, 20);

    final methods = channel.calls.map((c) => c.method).toList();
    expect(methods, contains('shareFiles'));
    expect(methods, isNot(contains('share')), reason: 'text-only is the failure mode');

    final files = channel.calls.firstWhere((c) => c.method == 'shareFiles');
    final paths = (files.arguments as Map)['paths'] as List;
    expect(paths, hasLength(1));
    final shared = File(paths.single as String);
    expect(shared.existsSync(), isTrue);
    expect(shared.readAsBytesSync().sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

    // The words ride the clipboard, as the sheet promises.
    expect(find.text('Caption copied — paste it alongside the card.'), findsOneWidget);
    expect(
      find.text("Couldn't render the card, so the text was shared instead."),
      findsNothing,
    );
  });
}
