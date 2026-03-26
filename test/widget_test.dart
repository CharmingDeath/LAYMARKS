import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:laymarks/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Allow smoke tests to run when local env file is absent.
      dotenv.testLoad(fileInput: '');
    }
  });

  testWidgets('app boot smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AppMineApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('LAYMARKS'), findsOneWidget);
  });
}
