import 'package:flutter_test/flutter_test.dart';

import 'package:dailybrief/main.dart';

void main() {
  testWidgets('DailyBrief menampilkan layar pembuka', (tester) async {
    await tester.pumpWidget(const DailyBriefApp());
    expect(find.text('DailyBrief'), findsOneWidget);
    expect(find.text('Temukan Informasi dalam Satu Sentuhan'), findsOneWidget);
    // Hentikan timer splash agar test selesai bersih.
    await tester.pump(const Duration(seconds: 3));
  });
}
