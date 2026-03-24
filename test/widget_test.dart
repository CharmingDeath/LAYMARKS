import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appmine/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: '.env');
  });

  testWidgets('app boot smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AppMineApp());
    await tester.pumpAndSettle();

    expect(find.text('LAYMARKS'), findsOneWidget);
  });
}
