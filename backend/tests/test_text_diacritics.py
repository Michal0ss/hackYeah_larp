from app.services.safety import check_generated_text


def test_long_text_without_polish_letters_is_rejected():
    text = "Dzis lzejszy trening. Krotki sen to sygnal, ze warto dzis zwolnic i zrobic o jedna serie mniej."
    assert "missing_diacritics" in check_generated_text(text)


def test_text_with_polish_letters_passes():
    text = "Dziś lżejszy trening. Krótki sen to sygnał, że warto dziś zwolnić i zrobić o jedną serię mniej."
    assert "missing_diacritics" not in check_generated_text(text)


def test_short_text_is_not_checked():
    assert "missing_diacritics" not in check_generated_text("Trenuj wg planu")
