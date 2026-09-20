import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/features/hello/presentation/hello_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la route / affiche HelloScreen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AstreinteApp()));
    await tester.pumpAndSettle();

    expect(find.byType(HelloScreen), findsOneWidget);
  });
}
