import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point.
///
/// Wraps the entire widget tree in [ProviderScope] so Riverpod providers
/// are available everywhere in the app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: CardVaultApp(),
    ),
  );
}
