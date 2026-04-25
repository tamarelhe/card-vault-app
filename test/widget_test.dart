// Smoke test — verifies the app widget tree builds without throwing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:card_vault_app/app.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CardVaultApp()),
    );
    // Pump once — the router will redirect to login since no token is stored.
    await tester.pump();
  });
}
