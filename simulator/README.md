# HeatGuard environmental simulator (SIMULATED data)

`heatguard_sim` produces **synthetic**, internally consistent WBGT inputs. It is used in-process by the backend
(through the `SensorSource` interface) and by the standalone client `simulator.py`.

## Generation assumptions

1. Each scenario defines *drivers* per simulated minute: air temperature, RH, solar irradiance, air speed and
   indoor radiant excess.
2. Psychrometric wet-bulb comes from Stull (2011), *J. Appl. Meteor. Climatol.* 50:2267–2269.
3. Globe temperature: `Tg = Tdb + (0.016·S + R) / (1 + 0.3·v)`. This is a heuristic: the excess grows with
   solar load S (W/m²) or radiant excess R and falls with air speed v.
4. Natural wet-bulb: `Tnwb = Twb + 0.1·(Tg − Tdb)/(1 + 0.2·v)`, constrained to `Tnwb ≤ Tdb`.
5. Direct solar load is flagged when S ≥ 120 W/m² (the WMO sunshine threshold), which selects the outdoor WBGT formula.
6. Gaussian measurement noise (σ ≈ 0.15 °C; 0.22 °C globe; 1 % RH) is added. Noisy Tnwb is clipped to ≤ Tdb.
7. Faults: `missing` (no value) or `invalid` (−127 °C, a typical disconnected-probe sentinel), per probe or for
   the whole station; they can be scheduled (Scenario E) or triggered manually.
8. Network outage: readings are queued in an edge buffer (up to 720) and delivered with `late_sync=true` on recovery.
9. After a scenario's duration the profile runs backwards (ping-pong), so a long demo has no jumps.

These are consistency heuristics for demonstration and **not a validated thermal model**. Every reading carries
`data_origin: "SIMULATED"`. `ground_truth` (noise-free values) is used only by the evaluation module and is
never sent to clients.

## Scenarios

| Code | id | Environment | Description |
|---|---|---|---|
| A | `normal` | outdoor | Early morning, light cloud, breeze; WBGT ≈ 23–25 °C |
| B | `increasing_heat` | outdoor | Build-up to midday; WBGT ≈ 24.5 → 33 °C over 3 h |
| C | `construction_radiant` | outdoor | Concrete deck, full sun, low wind; WBGT ≈ 28.5–31 °C |
| D | `industrial_indoor` | indoor | Furnace radiant heat, poor ventilation; WBGT ≈ 27.5–29.5 °C |
| E | `sensor_failure` | outdoor | Globe drop-out (min 15–30), invalid wet-bulb (40–55), full outage (70–85) |

## Standalone client

```bash
python simulator.py --api http://localhost:8000/api --worksite ws_kumasi_tower --scenario increasing_heat --interval 3
```

Run the backend with `HEATGUARD_SIM_AUTOSTART=false` so the readings are not duplicated.
