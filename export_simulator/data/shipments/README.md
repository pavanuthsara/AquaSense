# Shipment records for the AI correction layer

One row per completed shipment (all bags packed the same way). Simulated and real records use
the same columns, so real data simply replaces the simulated file.

| Column | Meaning |
|---|---|
| id | any unique id |
| source | `real` (or `simulated` for the pretend-reality records) |
| species | `guppy` or `tiger_barb` |
| fish_mass_g | average weight per fish (g) |
| fish_per_bag | fish packed per bag |
| water_l, gas_l | water and oxygen per bag (L) |
| duration_h | hours from packing until the fish are out of the bag |
| temp_low_c, temp_high_c | coolest / warmest temperature during the trip (logger or estimate) |
| fasting_h | hours without food before packing |
| zeolite_g_per_l | 0 if none |
| anaesthetic | `none`, `ms222_40mgL` or `benzocaine_20mgL` |
| bags | number of bags in the shipment |
| fish_counted | fish counted on arrival + after unpacking (alive + dead) |
| fish_alive | fish alive after unpacking |
| observed_survival | fish_alive / fish_counted |

Files:
- `simulated_shipments.csv`, `simulated_test_shipments.csv` — SIMULATED (pretend reality), for building and testing the pipeline.
- `real_shipments_TEMPLATE.csv` — copy to `real_shipments.csv` and fill in real records, then run
  `python -m transit_sim ml train --data data/shipments/real_shipments.csv`.
