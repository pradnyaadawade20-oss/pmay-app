import 'package:flutter_test/flutter_test.dart';
import 'package:pmay_app/main.dart';

void main() {
  testWidgets('PMAY app launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const PmayApp());

    // Allow the first frame to render.
    await tester.pump();

    expect(find.byType(PmayApp), findsOneWidget);
  });
}