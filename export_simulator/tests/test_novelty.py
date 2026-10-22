from dataclasses import replace
from pathlib import Path

import pytest

from transit_sim import advisor
from transit_sim.advisor import AdvisoryRequest, advise, advise_text
from transit_sim.config import load_species
from transit_sim.novelty import MIN_SIMILAR, MIN_SPECIES_RECORDS, ShipmentFeatures, ShipmentHistory

X = ShipmentFeatures(species="guppy", fish_mass_g=0.3, fish_per_bag=40, water_l=0.4, gas_l=1.2, duration_h=24,
                     temp_max_c=28, fasting_h=24, anaesthetic="ms222_40mgL")


def _history(n_similar: int, n_other: int = 0) -> ShipmentHistory:
    similar = [replace(X, fish_per_bag=38 + i % 5) for i in range(n_similar)]
    other = [replace(X, fish_per_bag=150, duration_h=12, temp_max_c=22) for _ in range(n_other)]
    return ShipmentHistory(similar + other)


def test_many_similar_shipments_show_the_ai():
    r = _history(MIN_SIMILAR).check(X)
    assert (r.level, r.ai_display, r.similar_shipments) == ("many", "full", MIN_SIMILAR)


def test_few_similar_shipments_are_limited_experience():
    r = _history(2, n_other=20).check(X)
    assert (r.level, r.ai_display, r.similar_shipments) == ("few", "limited", 2)
    assert "Limited experience" in r.message


def test_in_range_but_nothing_close_is_new():
    r = _history(1, n_other=1).check(replace(X, fish_per_bag=90, duration_h=18, temp_max_c=25))
    assert r.level == "new" and r.similar_shipments == 0 and not r.out_of_range


@pytest.mark.parametrize("change, phrase", [
    (dict(species="neon_tetra"), "has not been shipped before"),
    (dict(duration_h=48), "trip length 48 h is higher than any recorded"),
    (dict(temp_max_c=33), "hottest temperature"),
    (dict(anaesthetic="benzocaine_20mgL"), "sedative"),
    (dict(zeolite_g_per_l=20), "zeolite"),
])
def test_range_check_flags_anything_never_seen(change, phrase):
    r = _history(10).check(replace(X, **change))
    assert (r.level, r.ai_display) == ("new", "hidden")
    assert any(phrase in reason for reason in r.out_of_range), r.out_of_range
    assert "first data point" in r.message


def test_no_records_means_physics_only():
    r = ShipmentHistory().check(X)
    assert r.ai_display == "hidden" and r.records == 0


def test_history_reads_csv(tmp_path):
    p = tmp_path / "real.csv"
    p.write_text("species,fish_mass_g,fish_per_bag,water_l,gas_l,duration_h,temp_max_c,anaesthetic\n"
                 "guppy,0.3,40,0.4,1.2,24,28,ms222_40mgL\n"
                 "guppy,0.3,40,0.4,1.2,24,28,none\n", encoding="utf-8")
    h = ShipmentHistory.from_csv(p)
    assert len(h) == 2 and h.count_species("guppy") == 2
    assert h.records[1].anaesthetic == "" and h.records[0].fasting_h == 24.0
    bad = tmp_path / "bad.csv"
    bad.write_text("species,fish_mass_g\nguppy,0.3\n", encoding="utf-8")
    with pytest.raises(ValueError):
        ShipmentHistory.from_csv(bad)


def test_borrowed_species_are_marked():
    assert load_species("guppy").borrowed_from == "tiger_barb"
    assert load_species("guppy").rate_uncertainty > 0
    assert load_species("tiger_barb").borrowed_from is None
    assert load_species("tiger_barb").rate_uncertainty == 0


REQ = dict(species="guppy", fish_mass_g=0.3, total_fish=1000, water_l=0.4, gas_l=1.2, duration_h=24,
           temp_low_c=24, temp_high_c=26, samples=0, allow_anaesthetic=False, allow_zeolite=False, max_fasting_h=24)


@pytest.fixture(scope="module")
def cautious():
    return advise(AdvisoryRequest(**REQ), history=ShipmentHistory())


def test_borrowed_species_is_packed_more_conservatively(cautious):
    su = cautious["species_uncertainty"]
    assert su["safe_fish_per_bag_with_margin"] < su["fish_per_bag_at_published_values"]
    assert cautious["recommendation"]["fish_per_bag"] == su["safe_fish_per_bag_with_margin"]
    assert any("packs more carefully" in w for w in cautious["warnings"])
    assert cautious["experience"]["ai_display"] == "hidden"
    assert cautious["verdict"]["ai_display"] == "hidden"
    assert "AI SECOND OPINION" in advise_text(cautious)


def test_margin_is_dropped_once_real_shipments_exist(cautious):
    su = cautious["species_uncertainty"]
    n = su["fish_per_bag_at_published_values"]
    records = [ShipmentFeatures(species="guppy", fish_mass_g=0.3, fish_per_bag=n + i % 3 - 1, water_l=0.4,
                                gas_l=1.2, duration_h=24, temp_max_c=26) for i in range(MIN_SPECIES_RECORDS)]
    adv = advise(AdvisoryRequest(**REQ), history=ShipmentHistory(records))
    assert adv["species_uncertainty"] is None
    assert adv["recommendation"]["fish_per_bag"] == n
    assert adv["experience"]["level"] == "many"


def test_measured_species_has_no_margin():
    adv = advise(AdvisoryRequest(**{**REQ, "species": "tiger_barb", "fish_mass_g": 12, "total_fish": 50,
                                    "water_l": 1.0, "gas_l": 3.0}), history=ShipmentHistory())
    assert adv["species_uncertainty"] is None


def test_history_reads_the_shipment_template_columns(tmp_path):
    p = tmp_path / "real.csv"
    p.write_text("id,source,species,fish_mass_g,fish_per_bag,water_l,gas_l,duration_h,temp_low_c,temp_high_c,"
                 "fasting_h,zeolite_g_per_l,anaesthetic,bags,fish_counted,fish_alive,observed_survival\n"
                 "r1,real,guppy,0.3,40,0.4,1.2,24,26,29.5,48,0,none,10,400,392,0.98\n", encoding="utf-8")
    h = ShipmentHistory.from_csv(p)
    assert h.records[0].temp_max_c == 29.5 and h.records[0].fasting_h == 48.0
    assert h.label == "past shipments"


def test_simulated_records_are_named_as_such():
    h = ShipmentHistory.from_csv(Path(__file__).resolve().parent.parent / "data/shipments/simulated_shipments.csv")
    assert h.label == "simulated shipments" and len(h) > 0


def test_ai_numbers_follow_the_novelty_check(monkeypatch):
    fake = {"physics_survival_pct": 97.0, "corrected_survival_pct": 96.0, "adjustment_pp": -1.0,
            "trained_on": "real", "n_shipments": 1, "note": ""}
    monkeypatch.setattr(advisor, "_ai_correction", lambda *a: dict(fake))
    req = AdvisoryRequest(**{**REQ, "species": "tiger_barb", "fish_mass_g": 12, "total_fish": 50,
                             "water_l": 1.0, "gas_l": 3.0})
    hidden = advise(req, history=ShipmentHistory())
    assert hidden["experience"]["ai_display"] == "hidden" and hidden["ai_correction"] is None
    n = hidden["recommendation"]["fish_per_bag"]
    seen = [ShipmentFeatures(species="tiger_barb", fish_mass_g=12, fish_per_bag=n, water_l=1.0, gas_l=3.0,
                             duration_h=24, temp_max_c=26)] * 2
    limited = advise(req, history=ShipmentHistory(), ai_history=ShipmentHistory(seen))
    assert limited["experience"]["ai_display"] == "limited" and limited["ai_correction"]["display"] == "limited"
    assert "AI estimate: 96.0%" in advise_text(limited)
