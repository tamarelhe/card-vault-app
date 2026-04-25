import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/collection_model.dart';
import '../../../core/providers.dart';
import '../collections_repository.dart';

/// Provider for the paginated collections list.
final collectionsProvider =
    FutureProvider.autoDispose<List<CollectionModel>>((ref) async {
  final repo = CollectionsRepository(ref.watch(dioProvider));
  final response = await repo.listCollections();
  return response.items;
});

/// Displays the user's collections and allows creating new ones.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Collections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New collection',
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: collectionsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load collections: $e'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(collectionsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (collections) => collections.isEmpty
            ? _EmptyState(
                onCreateTap: () => _showCreateDialog(context, ref),
              )
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(collectionsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: collections.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _CollectionCard(collection: collections[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _showCreateDialog(
      BuildContext context, WidgetRef ref) async {
    final name = await _CreateCollectionDialog.show(context);
    if (name == null || name.trim().isEmpty) return;

    try {
      final repo = CollectionsRepository(ref.read(dioProvider));
      await repo.createCollection(name: name.trim());
      ref.invalidate(collectionsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create collection: $e')),
        );
      }
    }
  }
}

class _CollectionCard extends StatelessWidget {
  final CollectionModel collection;

  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
        title: Text(collection.name),
        subtitle: collection.description.isNotEmpty
            ? Text(
                collection.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
        // TODO: navigate to collection detail screen
        onTap: () {},
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;

  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'No collections yet',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: const Text('Create first collection'),
          ),
        ],
      ),
    );
  }
}

/// Simple dialog for entering the new collection name.
class _CreateCollectionDialog extends StatefulWidget {
  const _CreateCollectionDialog();

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const _CreateCollectionDialog(),
    );
  }

  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState
    extends State<_CreateCollectionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Collection'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Collection name',
          hintText: 'e.g. Standard Deck',
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
