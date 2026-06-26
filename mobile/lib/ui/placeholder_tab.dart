/// Zakladka-zaslepka dla funkcji, ktore dochodza w kolejnych etapach portu
/// (Nagrania, Test glosow). Uczciwie pokazuje, ze funkcja jest w drodze, zamiast
/// udawac dzialanie.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.icon,
    required this.title,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final cc = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cc.muted),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: cc.text)),
            const SizedBox(height: 8),
            Text(note,
                textAlign: TextAlign.center,
                style: TextStyle(color: cc.muted)),
          ],
        ),
      ),
    );
  }
}
