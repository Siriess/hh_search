import 'package:flutter_test/flutter_test.dart';
import 'package:hh_search/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HhSearchApp());
    expect(find.text('HH.ru — Выгрузка вакансий'), findsOneWidget);
  });
}
