from app import parse_import


def test_parse_german_run_sentence():
    draft = parse_import("5 km, 32 Minuten, Pace 6:24")
    assert draft.distanceMeters == 5000
    assert draft.duration == 1920
    assert draft.averagePaceSecondsPerKm == 384
    assert draft.confidence > 0.6
