import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alkawn_alshamil/main.dart';

void main() {
  testWidgets('يعرض التطبيق واجهة الدخول الجديدة', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('اسم المستخدم'), findsOneWidget);
    expect(find.text('تسجيل دخول'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsOneWidget);
  });
}
