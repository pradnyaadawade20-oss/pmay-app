import 'package:flutter_test/flutter_test.dart';
import 'package:pmay_admin/api.dart';
import 'package:pmay_admin/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.i.token = null;
  });

  testWidgets('shows the real login (no demo mode)', (tester) async {
    await Api.i.load();
    await tester.pumpWidget(const AdminApp());
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('Demo'), findsNothing);
  });

  test('role permissions', () {
    Api.i.roles = ['finance'];
    expect(Api.i.canPayments, isTrue);
    expect(Api.i.canReview, isFalse);
    expect(Api.i.isSuper, isFalse);
    Api.i.roles = ['super_admin'];
    expect(Api.i.isSuper && Api.i.canReview && Api.i.canAllot, isTrue);
  });
}
