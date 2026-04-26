import 'dart:async';

import 'package:flutter/material.dart';

/// Immutable filter state for the collection cards list.
///
/// Nullable fields ([setCode], [cardType]) represent "no filter applied".
/// Use [copyWith] with the matching `clear*` flag to reset them to null.
class CardFilterState {
  final String query;
  final String? setCode;
  final String? cardType;
  final String sortBy;
  final String sortOrder;

  const CardFilterState({
    this.query = '',
    this.setCode,
    this.cardType,
    this.sortBy = 'name',
    this.sortOrder = 'asc',
  });

  /// Returns true when any filter differs from the defaults.
  bool get hasActiveFilters =>
      query.isNotEmpty ||
      setCode != null ||
      cardType != null ||
      sortBy != 'name' ||
      sortOrder != 'asc';

  /// Creates a copy with the given fields replaced.
  ///
  /// Pass [clearSetCode] or [clearCardType] as `true` to explicitly set those
  /// nullable fields to null, since null-as-argument is ambiguous.
  CardFilterState copyWith({
    String? query,
    String? setCode,
    bool clearSetCode = false,
    String? cardType,
    bool clearCardType = false,
    String? sortBy,
    String? sortOrder,
  }) =>
      CardFilterState(
        query: query ?? this.query,
        setCode: clearSetCode ? null : (setCode ?? this.setCode),
        cardType: clearCardType ? null : (cardType ?? this.cardType),
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  @override
  bool operator ==(Object other) =>
      other is CardFilterState &&
      other.query == query &&
      other.setCode == setCode &&
      other.cardType == cardType &&
      other.sortBy == sortBy &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hash(query, setCode, cardType, sortBy, sortOrder);
}

/// Sticky filter bar displayed below the AppBar on the collection detail screen.
///
/// Emits updated [CardFilterState] via [onChanged] whenever the user modifies
/// any filter.  Search input is debounced by 400 ms.
class CardFilterBar extends StatefulWidget {
  final CardFilterState filters;
  final ValueChanged<CardFilterState> onChanged;

  const CardFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
  });

  @override
  State<CardFilterBar> createState() => _CardFilterBarState();
}

class _CardFilterBarState extends State<CardFilterBar> {
  late final TextEditingController _searchCtrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.filters.query);
  }

  @override
  void didUpdateWidget(CardFilterBar old) {
    super.didUpdateWidget(old);
    // Sync controller if parent cleared the query (e.g. "clear all filters").
    if (widget.filters.query != old.filters.query &&
        widget.filters.query != _searchCtrl.text) {
      _searchCtrl.text = widget.filters.query;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      widget.onChanged(widget.filters.copyWith(query: value));
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    widget.onChanged(widget.filters.copyWith(query: ''));
  }

  Future<void> _showSetFilter() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TextInputSheet(
        title: 'Filter by set',
        hint: 'e.g. m10, one, dmu',
        initial: widget.filters.setCode ?? '',
      ),
    );
    if (!mounted || result == null) return;
    widget.onChanged(widget.filters.copyWith(
      setCode: result.toLowerCase().isEmpty ? null : result.toLowerCase(),
      clearSetCode: result.isEmpty,
    ));
  }

  Future<void> _showTypeFilter() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) =>
          _TypePickerSheet(selected: widget.filters.cardType),
    );
    if (!mounted || result == null) return;
    widget.onChanged(widget.filters.copyWith(
      cardType: result.isEmpty ? null : result,
      clearCardType: result.isEmpty,
    ));
  }

  Future<void> _showSortOptions() async {
    final result = await showModalBottomSheet<({String sortBy, String sortOrder})>(
      context: context,
      builder: (_) => _SortSheet(
        sortBy: widget.filters.sortBy,
        sortOrder: widget.filters.sortOrder,
      ),
    );
    if (!mounted || result == null) return;
    widget.onChanged(widget.filters.copyWith(
      sortBy: result.sortBy,
      sortOrder: result.sortOrder,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search cards…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _clearSearch,
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              // Set code
              if (f.setCode != null)
                InputChip(
                  label: Text('Set: ${f.setCode!.toUpperCase()}'),
                  onPressed: _showSetFilter,
                  onDeleted: () =>
                      widget.onChanged(f.copyWith(clearSetCode: true)),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.filter_list, size: 16),
                  label: const Text('Set'),
                  onPressed: _showSetFilter,
                ),
              const SizedBox(width: 8),
              // Card type
              if (f.cardType != null)
                InputChip(
                  label: Text('Type: ${f.cardType!}'),
                  onPressed: _showTypeFilter,
                  onDeleted: () =>
                      widget.onChanged(f.copyWith(clearCardType: true)),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: const Text('Type'),
                  onPressed: _showTypeFilter,
                ),
              const SizedBox(width: 8),
              // Sort
              ActionChip(
                avatar: Icon(
                  f.sortOrder == 'asc'
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 16,
                ),
                label: Text(_sortLabel(f.sortBy)),
                onPressed: _showSortOptions,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  static String _sortLabel(String sortBy) => switch (sortBy) {
        'name' => 'Name',
        'rarity' => 'Rarity',
        'quantity' => 'Qty',
        'added_at' => 'Added',
        'price' => 'Price',
        _ => sortBy,
      };
}

// ---------------------------------------------------------------------------
// Bottom sheet sub-widgets
// ---------------------------------------------------------------------------

/// Free-text input sheet used for set code filter.
class _TextInputSheet extends StatefulWidget {
  final String title;
  final String hint;
  final String initial;

  const _TextInputSheet({
    required this.title,
    required this.hint,
    this.initial = '',
  });

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Clear'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ctrl.text.trim()),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Radio-list picker for card type filter.
class _TypePickerSheet extends StatelessWidget {
  final String? selected;

  const _TypePickerSheet({this.selected});

  static const _types = [
    'Creature',
    'Instant',
    'Sorcery',
    'Enchantment',
    'Artifact',
    'Land',
    'Planeswalker',
    'Battle',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text('Filter by type',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        // RadioGroup manages groupValue for all Radio descendants.
        RadioGroup<String>(
          groupValue: selected ?? '',
          onChanged: (v) {
            if (v != null) Navigator.of(context).pop(v);
          },
          child: Column(
            children: [
              _RadioRow(value: '', label: 'Any type', context: context),
              ..._types.map(
                (t) => _RadioRow(value: t, label: t, context: context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String value;
  final String label;
  final BuildContext context;

  const _RadioRow({
    required this.value,
    required this.label,
    required this.context,
  });

  @override
  Widget build(BuildContext _) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          children: [
            Radio<String>(value: value),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Sort field + direction picker.
class _SortSheet extends StatefulWidget {
  final String sortBy;
  final String sortOrder;

  const _SortSheet({required this.sortBy, required this.sortOrder});

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late String _sortBy;
  late String _sortOrder;

  static const _options = [
    ('name', 'Name'),
    ('rarity', 'Rarity'),
    ('quantity', 'Quantity'),
    ('added_at', 'Date added'),
    ('price', 'Price'),
  ];

  @override
  void initState() {
    super.initState();
    _sortBy = widget.sortBy;
    _sortOrder = widget.sortOrder;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sort by', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _options
                .map((opt) => ChoiceChip(
                      label: Text(opt.$2),
                      selected: _sortBy == opt.$1,
                      onSelected: (_) => setState(() => _sortBy = opt.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('Direction',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DirectionButton(
                  label: 'A → Z',
                  icon: Icons.arrow_upward,
                  selected: _sortOrder == 'asc',
                  onTap: () => setState(() => _sortOrder = 'asc'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DirectionButton(
                  label: 'Z → A',
                  icon: Icons.arrow_downward,
                  selected: _sortOrder == 'desc',
                  onTap: () => setState(() => _sortOrder = 'desc'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop((sortBy: _sortBy, sortOrder: _sortOrder)),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: selected
          ? OutlinedButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              side: BorderSide(color: cs.primary),
            )
          : null,
      onPressed: onTap,
    );
  }
}
