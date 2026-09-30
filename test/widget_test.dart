import 'package:flutter_test/flutter_test.dart';
import 'package:mozaque/app.dart';

void main() {
  testWidgets('shows setup guidance when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const MozaqueApp(configured: false));

    expect(find.text('Your people.\nYour memories.'), findsOneWidget);
    expect(find.text('Quick setup'), findsOneWidget);
  });
}
