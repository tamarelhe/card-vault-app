# Plan: Create Collection Screen + Collection Detail Screen

## Context

### What already exists
| File | Status |
|------|--------|
| `CollectionsScreen` | Lists collections; has an inline `_CreateCollectionDialog` (name only) |
| `CollectionsRepository` | `listCollections`, `createCollection`, `deleteCollection` — no card-listing |
| `CollectionModel` | Name, description, timestamps |
| `CardModel` | Full card data |
| `app.dart` | Routes: `/`, `/login`, `/register` only |
| `_CollectionCard.onTap` | `// TODO: navigate to collection detail screen` |

### What is missing
- `CollectionCardModel` — the API's `CollectionCard` schema (quantity, condition, language, foil, price…) has no Dart class
- `CollectionsRepository.listCollectionCards` — calls `GET /api/v1/collections/{id}/cards`
- Dedicated Create Collection screen (description field, validation)
- Collection Detail screen (cards list + filters)
- Route `/collections/:id` in `app.dart`

---

## API Reference

### `GET /api/v1/collections/{id}/cards`
Query params used by the filter widget:

| Param | Type | Notes |
|-------|------|-------|
| `q` | string | Card name substring search |
| `set_code` | string | Exact set code |
| `card_type` | string | Type-line substring (e.g. `Creature`) |
| `sort_by` | enum | `name` `rarity` `quantity` `added_at` `price` — default `name` |
| `sort_order` | enum | `asc` / `desc` — default `asc` |
| `page` / `page_size` | int | Pagination |

Response: `CollectionCardListResponse` → `{items: CollectionCard[], meta: PaginationMeta}`

### `CollectionCard` schema (new model needed)
```
id, card_id, card_name, set_code, set_name, collector_number, rarity,
image_uri?, mana_cost?, type_line?,
quantity (int), condition, language, foil (bool),
notes?, price_eur?, price_usd?,
added_at, updated_at
```

---

## Files to create

| File | Purpose |
|------|---------|
| `lib/core/models/collection_card_model.dart` | `CollectionCardModel` + `CollectionCardListResponse` |
| `lib/features/collections/screens/create_collection_screen.dart` | Dedicated create screen (name + description) |
| `lib/features/collections/screens/collection_detail_screen.dart` | Cards list with filter widget |
| `lib/features/collections/widgets/collection_card_tile.dart` | Single card row widget |
| `lib/features/collections/widgets/card_filter_bar.dart` | Sticky filter strip (search + set + type + sort) |

## Files to modify

| File | Change |
|------|--------|
| `lib/features/collections/collections_repository.dart` | Add `listCollectionCards(id, filters…)` |
| `lib/core/api/api_constants.dart` | Add `collectionCards(id)` helper |
| `lib/features/collections/screens/collections_screen.dart` | Replace `_showCreateDialog` with nav to create screen; wire `_CollectionCard.onTap` |
| `lib/app.dart` | Add route `/collections/:id` |

---

## Screen 1 — Create Collection

### Route
`/collections/new` — pushed from the `+` button in `CollectionsScreen`.

### Layout
```
AppBar: "New Collection"  [Cancel ×]

[Card / Form container]
  TextField  — Name *        (autofocus, max 80 chars, required)
  TextField  — Description   (multiline, max 300 chars, optional)

[Bottom]
  FilledButton  "Create Collection"  (disabled while name is empty or saving)
```

### Behaviour
- Validation: name must not be blank after trim.
- On submit: `CollectionsRepository.createCollection` → pop with the new `CollectionModel`.
- `CollectionsScreen` receives the result and calls `ref.invalidate(collectionsProvider)`.
- On error: `ScaffoldMessenger` SnackBar (matches existing error pattern).

### State
`ConsumerStatefulWidget` with a `TextEditingController` each for name and description, plus a `bool _saving`.

---

## Screen 2 — Collection Detail

### Route
`/collections/:id` — pushed when tapping a row in `CollectionsScreen`.
Receives `CollectionModel` as extra parameter (already loaded, no extra fetch needed).

### Layout
```
AppBar: collection.name  [search icon ▸ toggles search bar]

── CardFilterBar (sticky below AppBar) ──────────────────────
  [Search field]  [Set chip ▾]  [Type chip ▾]  [Sort chip ▾]

── Card list (ListView.builder, infinite scroll) ─────────────
  CollectionCardTile × N
    [Card image 56×78]  Name · Set · #num
                        type_line  •  qty×N  •  condition
                        €price (if available)
  ── loading indicator at bottom when fetching next page ──
```

### `CardFilterBar` widget
Stateless UI; emits `CardFilterState` via callback when any field changes.

```dart
class CardFilterState {
  final String query;         // q
  final String? setCode;      // set_code
  final String? cardType;     // card_type
  final String sortBy;        // default 'name'
  final String sortOrder;     // 'asc' | 'desc'
}
```

Filter chips open inline dropdowns or a small `ModalBottomSheet` with radio options.

### State management
`StateNotifierProvider` that holds `CollectionDetailState`:
```dart
class CollectionDetailState {
  final List<CollectionCardModel> cards;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final CardFilterState filters;
  final String? errorMessage;
}
```

Key interactions:
- Filter change → reset `cards`, `page=1`, re-fetch.
- Scroll near bottom → fetch next page and append.
- Pull-to-refresh → reset to page 1.
- On error: inline error banner with "Retry" (not a snackbar, because the list is empty).

### `CollectionCardTile`
```
Row {
  Image.network(imageUri, 56×78, rounded corners, placeholder on error)
  Column {
    Text(card_name, style: titleSmall)
    Text(setName + " · #" + collectorNumber, style: bodySmall, muted)
    Text(typeLine, style: bodySmall, muted)
    Row { qty chip, condition chip, foil badge (if foil), price chip }
  }
}
```

---

## Provider structure

```
// In collections_screen.dart (already exists)
collectionsProvider → FutureProvider<List<CollectionModel>>

// New, in collection_detail_screen.dart
collectionDetailProvider(collectionId) →
    StateNotifierProvider<CollectionDetailNotifier, CollectionDetailState>
```

`CollectionDetailNotifier` is parameterised by `collectionId` (use `family`).

---

## Repository addition

```dart
Future<CollectionCardListResponse> listCollectionCards(
  String collectionId, {
  String? query,
  String? setCode,
  String? cardType,
  String sortBy = 'name',
  String sortOrder = 'asc',
  int page = 1,
  int pageSize = 20,
}) async {
  final response = await _dio.get<Map<String, dynamic>>(
    '${ApiConstants.collections}/$collectionId/cards',
    queryParameters: {
      if (query != null && query.isNotEmpty) 'q': query,
      if (setCode != null) 'set_code': setCode,
      if (cardType != null) 'card_type': cardType,
      'sort_by': sortBy,
      'sort_order': sortOrder,
      'page': page,
      'page_size': pageSize,
    },
  );
  return CollectionCardListResponse.fromJson(response.data!);
}
```

---

## Routing

```dart
// app.dart  — add inside GoRouter.routes
GoRoute(
  path: '/collections/new',
  builder: (ctx, state) => const CreateCollectionScreen(),
),
GoRoute(
  path: '/collections/:id',
  builder: (ctx, state) {
    final collection = state.extra as CollectionModel;
    return CollectionDetailScreen(collection: collection);
  },
),
```

`CollectionsScreen` buttons:
```dart
// Add button
onPressed: () async {
  final created = await context.push<CollectionModel>('/collections/new');
  if (created != null) ref.invalidate(collectionsProvider);
}

// Row tap
onTap: () => context.push('/collections/${collection.id}', extra: collection),
```

---

## Implementation order

1. `CollectionCardModel` + `CollectionCardListResponse` (model, no deps)
2. `ApiConstants` update
3. `CollectionsRepository.listCollectionCards`
4. `CreateCollectionScreen` + update `CollectionsScreen` + route in `app.dart`
5. `CardFilterBar` widget + `CardFilterState`
6. `CollectionCardTile` widget
7. `CollectionDetailNotifier` + `CollectionDetailState`
8. `CollectionDetailScreen` (wires all of the above)

---

## Success criteria

1. Tapping `+` in `CollectionsScreen` opens the create screen; submitting creates the collection and invalidates the list.
2. Tapping a collection row navigates to the detail screen showing its cards.
3. Typing in the search field filters results within ~400 ms (debounced).
4. Changing Set / Type / Sort chips re-fetches from page 1.
5. Scrolling to the bottom loads the next page seamlessly.
6. Pull-to-refresh resets to page 1 with current filters.
