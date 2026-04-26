import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            onPressed: () => _openCreateScreen(context, ref),
          ),
        ],
      ),
      body: collectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                onCreateTap: () => _openCreateScreen(context, ref),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(collectionsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: collections.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CollectionCard(
                    collection: collections[i],
                    onTap: () => context.push(
                      '/collections/${collections[i].id}',
                      extra: collections[i],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// Navigates to the create screen; invalidates the list when a collection
  /// is successfully created.
  Future<void> _openCreateScreen(BuildContext context, WidgetRef ref) async {
    final created =
        await context.push<CollectionModel>('/collections/new');
    if (created != null) ref.invalidate(collectionsProvider);
  }
}

class _CollectionCard extends StatelessWidget {
  final CollectionModel collection;
  final VoidCallback onTap;

  const _CollectionCard({
    required this.collection,
    required this.onTap,
  });

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
        onTap: onTap,
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
