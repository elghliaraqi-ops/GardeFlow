import 'package:flutter/material.dart';

/// Réserve une ligne au mois complet ; les actions restent sur une autre ligne.
class MonthNavigation extends StatelessWidget {
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onLabelTap;
  const MonthNavigation({super.key, required this.label, required this.onPrevious,
    required this.onNext, this.onLabelTap});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(tooltip: 'Mois précédent', onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded)),
      Expanded(child: InkWell(
        onTap: onLabelTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(label, textAlign: TextAlign.center, softWrap: true,
            style: Theme.of(context).textTheme.titleLarge),
        ),
      )),
      IconButton(tooltip: 'Mois suivant', onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded)),
    ],
  );
}
