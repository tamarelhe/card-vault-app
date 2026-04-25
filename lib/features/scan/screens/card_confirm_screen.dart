import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/card_model.dart';
import '../../../core/models/collection_model.dart';
import '../../../core/models/scan_hints.dart';
import '../../../core/providers.dart';
import '../../collections/collections_repository.dart';
import '../scan_repository.dart';

/// Displays the resolved card and lets the user add it to one of their collections.
///
/// Returns `true` via [Navigator.pop] when the card was successfully added.
class CardConfirmScreen extends ConsumerStatefulWidget {
  final CardModel card;

  const CardConfirmScreen({super.key, required this.card});

  @override
  ConsumerState<CardConfirmScreen> createState() => _CardConfirmScreenState();
}

class _CardConfirmScreenState extends ConsumerState<CardConfirmScreen> {
  String? _selectedCollectionId;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Add to Collection'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card image
            Center(child: _CardImage(card: widget.card)),
            const SizedBox(height: 20),

            // Card details
            _CardDetails(card: widget.card),
            const SizedBox(height: 24),

            // Collection picker
            _CollectionPicker(
              selectedId: _selectedCollectionId,
              onSelected: (id) => setState(() => _selectedCollectionId = id),
            ),
            const SizedBox(height: 32),

            // Add button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_selectedCollectionId != null && !_isSaving)
                        ? _addCard
                        : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add to Collection'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCard() async {
    if (_selectedCollectionId == null) return;
    setState(() => _isSaving = true);

    try {
      final scanRepo = ScanRepository(ref.read(dioProvider));

      // Create a one-off scan session for this single card.
      final sessionId = await scanRepo.createScanSession();
      await scanRepo.addItemToSession(
        sessionId,
        ScanHints(
          name: widget.card.name,
          setCode: widget.card.setCode,
          collectorNumber: widget.card.collectorNumber,
        ),
      );
      await scanRepo.importSession(sessionId, _selectedCollectionId!);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add card: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _CardImage extends StatelessWidget {
  final CardModel card;

  const _CardImage({required this.card});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: card.imageUri != null
          ? Image.network(
              card.imageUri!,
              width: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _Placeholder(),
            )
          : const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 308,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.image_not_supported,
          size: 48, color: Colors.white24),
    );
  }
}

class _CardDetails extends StatelessWidget {
  final CardModel card;

  const _CardDetails({required this.card});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(card.name,
            style: textTheme.headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (card.typeLine != null)
          Text(card.typeLine!,
              style: textTheme.bodyMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _Chip('${card.setName} #${card.collectorNumber}'),
            _Chip(card.rarityLabel),
            if (card.pricesEur != null)
              _Chip('€${card.pricesEur!.toStringAsFixed(2)}'),
          ],
        ),
        if (card.oracleText != null) ...[
          const SizedBox(height: 12),
          Text(card.oracleText!,
              style: textTheme.bodySmall?.copyWith(color: Colors.white60)),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.white70)),
      backgroundColor: Colors.white12,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Loads and displays the user's collections as a radio-style picker.
class _CollectionPicker extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _CollectionPicker({
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(_collectionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select collection',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        collectionsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white54)),
          error: (e, _) =>
              Text('Could not load collections', style: TextStyle(color: Colors.red.shade300)),
          data: (collections) => collections.isEmpty
              ? const Text('No collections yet — create one first.',
                  style: TextStyle(color: Colors.white54))
              : RadioGroup<String>(
                  groupValue: selectedId,
                  onChanged: (v) {
                    if (v != null) onSelected(v);
                  },
                  child: Column(
                    children: collections
                        .map(
                          (c) => InkWell(
                            onTap: () => onSelected(c.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: c.id,
                                    fillColor: WidgetStateProperty.resolveWith(
                                      (states) => states.contains(
                                              WidgetState.selected)
                                          ? Colors.deepPurpleAccent
                                          : Colors.white38,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(c.name,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        if (c.description.isNotEmpty)
                                          Text(c.description,
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Local provider scoped to this screen.
final _collectionsProvider = FutureProvider<List<CollectionModel>>((ref) async {
  final repo = CollectionsRepository(ref.watch(dioProvider));
  final result = await repo.listCollections();
  return result.items;
});
