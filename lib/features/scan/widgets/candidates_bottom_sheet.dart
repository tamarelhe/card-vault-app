import 'package:flutter/material.dart';
import '../../../core/models/card_model.dart';

/// Bottom sheet displayed when the backend returns multiple candidate cards.
///
/// The user picks the correct printing; the selected [CardModel] is returned
/// via `Navigator.pop`.
class CandidatesBottomSheet extends StatelessWidget {
  final List<CardModel> candidates;

  const CandidatesBottomSheet({super.key, required this.candidates});

  /// Convenience method to show the sheet and await the user's selection.
  static Future<CardModel?> show(
    BuildContext context,
    List<CardModel> candidates,
  ) {
    return showModalBottomSheet<CardModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CandidatesBottomSheet(candidates: candidates),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Multiple printings found',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Which one do you want to add?',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
            ),
            const Divider(color: Colors.white12, height: 24),

            // Candidate list
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: candidates.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (ctx, i) => _CandidateTile(
                  card: candidates[i],
                  onTap: () => Navigator.of(ctx).pop(candidates[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final CardModel card;
  final VoidCallback onTap;

  const _CandidateTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // Card art thumbnail
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: card.imageUri != null
            ? Image.network(
                card.imageUri!,
                width: 44,
                height: 62,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const _CardPlaceholder(width: 44, height: 62),
              )
            : const _CardPlaceholder(width: 44, height: 62),
      ),
      title: Text(
        card.name,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${card.setName} · #${card.collectorNumber} · ${card.rarityLabel}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }
}

/// Fallback widget shown when a card has no image or the network request fails.
class _CardPlaceholder extends StatelessWidget {
  final double width;
  final double height;

  const _CardPlaceholder({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.image_not_supported,
          size: 20, color: Colors.white24),
    );
  }
}
