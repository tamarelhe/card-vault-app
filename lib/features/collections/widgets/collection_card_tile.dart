import 'package:flutter/material.dart';

import '../../../core/models/collection_card_model.dart';

/// A single row in the collection cards list.
///
/// Shows the card art thumbnail, name, set, type line, quantity, condition,
/// foil status, and price.
class CollectionCardTile extends StatelessWidget {
  final CollectionCardModel card;

  const CollectionCardTile({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 44,
              height: 61,
              child: card.imageUri != null
                  ? Image.network(
                      card.imageUri!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _Placeholder(),
                    )
                  : const _Placeholder(),
            ),
          ),
          const SizedBox(width: 12),
          // Card details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.cardName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${card.setName} · #${card.collectorNumber}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white54),
                ),
                if (card.typeLine != null)
                  Text(
                    card.typeLine!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white38),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _Badge('×${card.quantity}'),
                    _Badge(card.conditionLabel),
                    _Badge(card.rarityLabel),
                    if (card.foil)
                      _Badge('Foil', color: Colors.amber.shade700),
                    if (card.priceLabel != null)
                      _Badge(card.priceLabel!, color: Colors.green.shade400),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white12,
        child: const Icon(Icons.image_not_supported,
            size: 20, color: Colors.white24),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color? color;

  const _Badge(this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w500),
      ),
    );
  }
}
