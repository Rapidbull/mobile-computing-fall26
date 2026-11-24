import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_practice/main.dart';

// Give the test a pretend screen of this width,
// then build the app.
Future<void> buildAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: NotesHome()));
}

void main() {
  testWidgets('narrow screen shows only the list', (tester) async {
    await buildAt(tester, 400);
    expect(find.byType(NoteList), findsOneWidget);
    expect(find.byType(NoteDetails), findsNothing);
  });

  testWidgets('wide screen shows list and details', (tester) async {
    await buildAt(tester, 1000);
    expect(find.byType(NoteList), findsOneWidget);
    expect(find.byType(NoteDetails), findsOneWidget);
  });

  testWidgets('wide screen: a tap updates the details', (tester) async {
    await buildAt(tester, 1000);
    await tester.tap(find.text('Call the dentist'));
    await tester.pump();
    expect(find.text('Call the dentist'), findsNWidgets(2));
  });
}
