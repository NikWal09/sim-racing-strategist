"""
Kalkulator oszczędności rekrutacyjnych — MONDI

Skrypt liczy szacunkową oszczędność dla klienta, który zamiast rekrutować
samodzielnie, decyduje się skorzystać z usług MONDI.

"""

# === Założenia biznesowe (potwierdzone przez dział sprzedaży) ===

# Średni miesięczny koszt rekrutacji jednego pracownika po stronie klienta:
# rekrutacja własna obejmuje ogłoszenia, czas HR, prowizje, onboarding
KOSZT_REKRUTACJI_WLASNEJ_PER_PRACOWNIK = 3500  # PLN/miesiąc

# Marża MONDI doliczana do kosztów pracownika u klienta
MARZA_MONDI_PROCENT = 18

# Czas trwania średniego kontraktu z klientem
DLUGOSC_KONTRAKTU_MIESIACE = 12

# Bonus oszczędności - typowy klient nie zatrudnia wszystkich od razu,
# tylko stopniowo, więc liczymy 0.7 miesiąca jako wskaźnik realnego obciążenia
WSKAZNIK_REALNEGO_OBCIAZENIA = 0.7


def oblicz_koszt_wlasnej_rekrutacji(liczba_pracownikow, miesiace):
    """Liczy koszt, gdyby klient rekrutował sam"""
    koszt_miesieczny = liczba_pracownikow * KOSZT_REKRUTACJI_WLASNEJ_PER_PRACOWNIK
    koszt_calkowity = koszt_miesieczny * miesiace * WSKAZNIK_REALNEGO_OBCIAZENIA
    print(koszt_miesieczny,koszt_calkowity)
    return koszt_calkowity


def oblicz_koszt_uslug_mondi(liczba_pracownikow, miesiace):
    """Liczy koszt usług MONDI dla klienta"""
    # Bazowy koszt jednego pracownika to koszt rekrutacji własnej
    # MONDI dolicza do tego swoją marżę
    koszt_bazowy_per_pracownik = KOSZT_REKRUTACJI_WLASNEJ_PER_PRACOWNIK
    marza = koszt_bazowy_per_pracownik * MARZA_MONDI_PROCENT / 100
    koszt_per_pracownik = koszt_bazowy_per_pracownik + marza

    koszt_miesieczny = liczba_pracownikow * koszt_per_pracownik
    koszt_calkowity = koszt_miesieczny * miesiace
    print(koszt_bazowy_per_pracownik,koszt_per_pracownik,marza,koszt_miesieczny,koszt_calkowity)
    return koszt_calkowity


def oblicz_oszczednosc(liczba_pracownikow):
    """Główna funkcja - liczy szacunkową oszczędność klienta"""
    koszt_wlasny = oblicz_koszt_wlasnej_rekrutacji(
        liczba_pracownikow, DLUGOSC_KONTRAKTU_MIESIACE
    )
    koszt_mondi = oblicz_koszt_uslug_mondi(
        liczba_pracownikow, DLUGOSC_KONTRAKTU_MIESIACE
    )
    print(koszt_mondi,koszt_wlasny)
    oszczednosc = koszt_wlasny - koszt_mondi
    return oszczednosc


def formatuj_kwote(kwota):
    """Formatuje kwotę do wyświetlenia"""
    return f"{kwota:.0f} zł"


# === Symulacja dla 5 pracowników ===

if __name__ == "__main__":
    liczba = 5
    wynik = oblicz_oszczednosc(liczba)
    print(f"Dla {liczba} pracowników szacunkowa oszczędność wynosi: {formatuj_kwote(wynik)}")