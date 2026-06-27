/// Mieszanki opon do kalkulatora stintu.
///
/// GT7 nie udostępnia mieszanki ani zużycia opon w pakiecie UDP, więc wybiera ją
/// użytkownik. Każda mieszanka ma domyślną, edytowalną szacowaną żywotność w
/// okrążeniach — realna żywotność mocno zależy od toru, auta i stylu jazdy, więc
/// to tylko punkt startowy.
library;

class TyreCompound {
  /// Stały identyfikator (do zapisu / ustawień).
  final String id;

  /// Klucz i18n nazwy mieszanki.
  final String nameKey;

  /// Domyślna szacowana żywotność [okrążenia].
  final int defaultLifeLaps;

  /// Domyślne tempo na świeżej oponie [s] — placeholder do edycji/pomiaru.
  final double defaultBasePaceS;

  /// Domyślna degradacja [s/okrążenie] — placeholder do edycji/pomiaru.
  final double defaultDegPerLapS;

  const TyreCompound(
    this.id,
    this.nameKey,
    this.defaultLifeLaps,
    this.defaultBasePaceS,
    this.defaultDegPerLapS,
  );
}

/// Mieszanki istotne dla zużycia w wyścigach GT7 (od najmiększej).
/// Wartości tempa/degradacji to tylko punkty startowe — realne dane lepiej
/// zmierzyć z jazdy albo wpisać ręcznie pod konkretny tor i auto.
const List<TyreCompound> kTyreCompounds = [
  TyreCompound('RS', 'tyre.RS', 8, 94.0, 0.25), // wyścigowe miękkie
  TyreCompound('RM', 'tyre.RM', 14, 95.0, 0.12), // wyścigowe średnie
  TyreCompound('RH', 'tyre.RH', 22, 96.2, 0.06), // wyścigowe twarde
  TyreCompound('RI', 'tyre.RI', 12, 100.0, 0.10), // pośrednie
  TyreCompound('RW', 'tyre.RW', 16, 103.0, 0.08), // deszczowe
];

/// Mieszanka po id (domyślnie RM, gdy nieznana).
TyreCompound tyreCompoundById(String id) => kTyreCompounds.firstWhere(
      (c) => c.id == id,
      orElse: () => kTyreCompounds[1],
    );
