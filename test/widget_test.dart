import 'package:flutter_test/flutter_test.dart';
import 'package:pettime_app/main.dart';

void main() {
  testWidgets('shows the app name', (tester) async {
    await tester.pumpWidget(const PetTimeApp());
    expect(find.text('PetTime'), findsOneWidget);
  });
}
