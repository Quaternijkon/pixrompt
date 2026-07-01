import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/ui/stored_image.dart';

void main() {
  testWidgets('loading image uses a soft non-black placeholder', (tester) async {
    final bytes = Completer<Uint8List?>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox.square(
              dimension: 120,
              child: StoredImage(
                loader: bytes.future,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );

    final placeholder = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('storedImage.placeholder')),
    );
    final decoration = placeholder.decoration as BoxDecoration;
    expect(decoration.color, isNot(Colors.black));
    expect(find.byKey(const ValueKey('storedImage.missingIcon')), findsNothing);

    bytes.complete(_onePixelPng);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'missing image icon is reserved for completed failed loads',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SizedBox.square(
                dimension: 120,
                child: StoredImage(
                  loader: Future<Uint8List?>.value(),
                  backgroundColor: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('storedImage.placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storedImage.missingIcon')),
        findsOneWidget,
      );
    },
  );
}

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
  '/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);
