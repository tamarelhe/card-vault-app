import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/collection_card_model.dart';
import '../../../core/models/collection_model.dart';
import '../../../core/providers.dart';
import '../collections_repository.dart';
import '../widgets/card_filter_bar.dart';
import '../widgets/collection_card_tile.dart';

// ---------------------------------------------------------------------------
// State + Notifier
// ---------------------------------------------------------------------------

/// Immutable state for the collection cards list.
class CollectionDetailState {
  final List<CollectionCardModel> cards;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final CardFilterState filters;
  final String? errorMessage;

  const CollectionDetailState({
    this.cards = const [],
    this.isLoading = true,
    this.hasMore = true,
    this.currentPage = 1,
    this.filters = const CardFilterState(),
    this.errorMessage,
  });

  /// Returns true when cards are empty and the first load is still in flight.
  bool get isInitialLoad => cards.isEmpty && isLoading;

  CollectionDetailState copyWith({
    List<CollectionCardModel>? cards,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    CardFilterState? filters,
    String? errorMessage,
    bool clearError = false,
  }) =>
      CollectionDetailState(
        cards: cards ?? this.cards,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        currentPage: currentPage ?? this.currentPage,
        filters: filters ?? this.filters,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Manages paginated + filtered card list for a single collection.
class CollectionDetailNotifier
    extends StateNotifier<CollectionDetailState> {
  final String _collectionId;
  final CollectionsRepository _repo;

  static const _pageSize = 20;

  CollectionDetailNotifier(this._collectionId, this._repo)
      : super(const CollectionDetailState()) {
    _fetch(1, replaceAll: true);
  }

  /// Appends the next page to the existing list.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    await _fetch(state.currentPage + 1);
  }

  /// Resets to page 1 with new filters and re-fetches.
  Future<void> applyFilters(CardFilterState filters) async {
    state = state.copyWith(
      filters: filters,
      cards: [],
      currentPage: 1,
      hasMore: true,
      clearError: true,
    );
    await _fetch(1, replaceAll: true);
  }

  /// Resets to page 1 with the current filters and re-fetches.
  Future<void> refresh() async {
    state = state.copyWith(
      cards: [],
      currentPage: 1,
      hasMore: true,
      clearError: true,
    );
    await _fetch(1, replaceAll: true);
  }

  Future<void> _fetch(int page, {bool replaceAll = false}) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final f = state.filters;
      final result = await _repo.listCollectionCards(
        _collectionId,
        query: f.query,
        setCode: f.setCode,
        cardType: f.cardType,
        sortBy: f.sortBy,
        sortOrder: f.sortOrder,
        page: page,
        pageSize: _pageSize,
      );

      if (!mounted) return;

      final updated =
          replaceAll ? result.items : [...state.cards, ...result.items];

      state = state.copyWith(
        cards: updated,
        isLoading: false,
        hasMore: updated.length < result.total,
        currentPage: page,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

/// Provider family keyed by collection ID — auto-disposed when the screen leaves.
final collectionDetailProvider = StateNotifierProvider.autoDispose
    .family<CollectionDetailNotifier, CollectionDetailState, String>(
  (ref, collectionId) => CollectionDetailNotifier(
    collectionId,
    CollectionsRepository(ref.watch(dioProvider)),
  ),
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Displays the cards in a collection with filtering and infinite scroll.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  final CollectionModel collection;

  const CollectionDetailScreen({super.key, required this.collection});

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  final _scrollController = ScrollController();

  String get _id => widget.collection.id;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(collectionDetailProvider(_id).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionDetailProvider(_id));
    final notifier = ref.read(collectionDetailProvider(_id).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: CardFilterBar(
            filters: state.filters,
            onChanged: notifier.applyFilters,
          ),
        ),
      ),
      body: _buildBody(context, state, notifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    CollectionDetailState state,
    CollectionDetailNotifier notifier,
  ) {
    // Initial load spinner
    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error with no cards loaded
    if (state.errorMessage != null && state.cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.white24),
              const SizedBox(height: 16),
              Text(
                'Failed to load cards',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white54),
              ),
              const SizedBox(height: 8),
              Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: notifier.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (state.cards.isEmpty && !state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_clear, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              state.filters.hasActiveFilters
                  ? 'No cards match the current filters'
                  : 'No cards yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white54),
            ),
            if (state.filters.hasActiveFilters) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    notifier.applyFilters(const CardFilterState()),
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        controller: _scrollController,
        // Extra slot at the bottom for the loading indicator
        itemCount: state.cards.length + (state.isLoading || state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.cards.length) {
            return state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return Column(
            children: [
              CollectionCardTile(card: state.cards[index]),
              const Divider(height: 1, indent: 68),
            ],
          );
        },
      ),
    );
  }
}
