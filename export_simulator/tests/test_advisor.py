import pytest

from transit_sim.advisor import AdvisoryRequest, advise, advise_text


@pytest.fixture(scope="module")
def adv():
    return advise(AdvisoryRequest(species="guppy", fish_mass_g=0.3, total_fish=1000, water_l=0.4, gas_l=1.2,
                                  duration_h=36, temp_low_c=24, temp_high_c=28, samples=4))


def test_advisory_has_every_section(adv):
    assert adv["feasible"]
    for key in ("recommendation", "oxygen", "mortality", "chemistry", "unpacking", "temperature", "timeline",
                "options", "warnings", "survival_band_pct"):
        assert key in adv, key


def test_recommended_plan_meets_target_in_hot_case(adv):
    rec = adv["recommendation"]
    assert rec["fish_per_bag"] > 0
    chosen = next(o for o in adv["options"] if o["recommended"])
    assert chosen["survival_hot_case_pct"] >= 95.0
    assert rec["bags_needed"] == -(-1000 // rec["fish_per_bag"])


def test_doses_are_scaled_to_bag_volume(adv):
    for d in adv["recommendation"]["doses"]:
        if d["addon"] == "ms222_40mgL":
            assert d["per_bag"].startswith("16.0 mg")
        if d["addon"] == "zeolite":
            assert d["per_bag"].startswith("8.0 g")


def test_chemicals_only_recommended_when_they_pay(adv):
    rec_opt = next(o for o in adv["options"] if o["recommended"])
    best = max(o["max_fish_per_bag"] for o in adv["options"])
    assert rec_opt["max_fish_per_bag"] >= 0.95 * best


def test_more_fish_than_chemical_free(adv):
    rec = adv["recommendation"]
    assert rec["fish_per_bag"] >= rec["fish_per_bag_without_chemicals"]


def test_timeline_is_hourly_and_includes_unpacking(adv):
    tl = adv["timeline"]["median"]
    assert len(tl["t_h"]) == len(tl["do_mgL"]) == len(tl["alive_pct"])
    assert 1 in tl["opened"]


def test_no_chemicals_when_not_allowed():
    adv = advise(AdvisoryRequest(fish_mass_g=0.3, water_l=0.4, gas_l=1.2, duration_h=24, temp_low_c=24,
                                 temp_high_c=26, allow_anaesthetic=False, allow_zeolite=False, samples=0))
    assert all(not o["addons"] for o in adv["options"])


def test_infeasible_trip_is_reported():
    adv = advise(AdvisoryRequest(fish_mass_g=5.0, water_l=0.1, gas_l=0.05, duration_h=120, temp_low_c=34,
                                 temp_high_c=36, target_survival=0.99, samples=0))
    assert adv["feasible"] is False
    assert "No plan" in advise_text(adv)


def test_invalid_request():
    with pytest.raises(ValueError):
        advise(AdvisoryRequest(water_l=0))


BASE = dict(species="guppy", fish_mass_g=0.3, total_fish=1000, water_l=0.4, gas_l=1.2, duration_h=36,
            temp_low_c=24, temp_high_c=28, samples=2)


def test_fixed_bags_enough():
    adv = advise(AdvisoryRequest(**BASE, mode="fixed_bags", bags=30))
    v = adv["verdict"]
    assert v["meets_target"] is True
    assert adv["recommendation"]["fish_per_bag"] == 34          # ceil(1000 / 30)
    assert adv["recommendation"]["bags_needed"] == 30
    assert "enough" in v["message"]


def test_fixed_bags_too_few_says_how_many_are_needed():
    adv = advise(AdvisoryRequest(**BASE, mode="fixed_bags", bags=10))
    v = adv["verdict"]
    assert v["meets_target"] is False
    assert v["survival_worst_pct"] < 90
    assert f"at least {v['recommended_bags']} bags" in v["message"]


def test_check_overpacked_bag_shows_real_losses():
    adv = advise(AdvisoryRequest(**BASE, mode="check", fish_per_bag=150))
    v = adv["verdict"]
    assert v["meets_target"] is False
    assert v["survival_median_pct"] < 80                          # survival really drops
    assert v["expected_dead_total"] > 200
    assert adv["recommendation"]["doses"][0]["addon"] == "fasting"
    assert "NOT safe" in advise_text(adv)


def test_check_uses_the_exporters_addons():
    adv = advise(AdvisoryRequest(**BASE, mode="check", fish_per_bag=35, check_fasting_h=48,
                                 check_anaesthetic="ms222_40mgL", check_zeolite=True))
    addons = {d["addon"] for d in adv["recommendation"]["doses"]}
    assert addons == {"fasting", "zeolite", "ms222_40mgL"}
    assert adv["verdict"]["meets_target"] is True
    assert adv["verdict"]["safe_max_with_selected_addons"] >= 35


def test_check_and_fixed_bags_validation():
    with pytest.raises(ValueError):
        advise(AdvisoryRequest(**BASE, mode="check"))
    with pytest.raises(ValueError):
        advise(AdvisoryRequest(**{**BASE, "total_fish": None}, mode="fixed_bags", bags=5))
    with pytest.raises(ValueError):
        advise(AdvisoryRequest(**BASE, mode="check", fish_per_bag=10, check_anaesthetic="vodka"))


def test_advice_has_no_citations_outside_the_method_section(adv):
    import re
    citation = re.compile(r"et al|\(\d{4}\)|\b(19|20)\d{2}\b")
    texts = list(adv["warnings"])
    for d in adv["recommendation"]["doses"] + adv["recommendation"]["not_simulated_options"]:
        texts += [d["why"], d["caution"], d["evidence"]]
    for key in ("oxygen", "mortality", "chemistry", "unpacking"):
        texts.append(adv[key]["explanation"])
    texts += [adv["temperature"]["advice"], adv["recommendation"]["summary"]]
    for t in texts:
        assert not citation.search(t), t
    assert adv["method"]["steps"] and adv["method"]["sources"]
