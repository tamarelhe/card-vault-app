import 'package:flutter/material.dart';

import '../collections/screens/collections_screen.dart';
import '../scan/screens/scanner_screen.dart';

/// Tab shell — hosts the Scan and Collections tabs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _tabs = [
    _Tab(
      icon: Icon(Icons.document_scanner_outlined),
      activeIcon: Icon(Icons.document_scanner),
      label: 'Scan',
      body: _ScanTab(),
    ),
    _Tab(
      icon: Icon(Icons.folder_outlined),
      activeIcon: Icon(Icons.folder),
      label: 'Collections',
      body: CollectionsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs.map((t) => t.body).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _tabs
            .map(
              (t) => NavigationDestination(
                icon: t.icon,
                selectedIcon: t.activeIcon,
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Scan tab — a launch pad for the full-screen scanner.
class _ScanTab extends StatelessWidget {
  const _ScanTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Card Vault')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.document_scanner_outlined,
                size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            Text(
              'Scan a card',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Point your camera at any MTG card\nto identify and add it to a collection.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white38),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const ScannerScreen(),
                ),
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Open Scanner'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab {
  final Widget icon;
  final Widget activeIcon;
  final String label;
  final Widget body;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.body,
  });
}
