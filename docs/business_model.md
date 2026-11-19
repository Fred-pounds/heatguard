# Business model, pricing and pilot plan

> **Status:** recommended prices and plan for the challenge submission, based on public market prices (sources at
> the end). They are to be validated with customers during the pilot. The team has no pilot partner yet; the plan
> below starts from that.

## Market

| Figure | Value | Source |
|---|---|---|
| Construction workers in the UAE | ~1.4 million (2023) | ILOSTAT (via Gitnux); MoHRE private-sector data reports ~1.416 million |
| Construction establishments | ~81,000 | MoHRE private-sector data (via Aletihad) |
| Midday-break fine | AED 5,000 per worker, up to AED 50,000 | MoHRE (via Khaleej Times) |
| Working hours lost to heat, Arab States, 2030 | ~1%, construction hardest hit | ILO, *Working on a warmer planet* (2019) |
| Abu Dhabi requirement | Employers must run a heat stress programme with WBGT-based risk assessment | ADOSH-SF Code of Practice 11.0, *Safety in the Heat* (ADPHC) |
| Typical labourer wage | ~AED 2,800 a month (job-board data; sources vary widely) | Naukrigulf |

First customers: contractors on Abu Dhabi projects, through their HSE managers. Next: oil and gas, utilities,
logistics, ports and landscaping, then Saudi Arabia and Qatar (the rules engine is configurable).

## What the market pays today

| Product | Model | Public price |
|---|---|---|
| Handheld WBGT meters (UAE) | Buy once, read manually | Extech HT30 AED 795; HT200 AED 1,182; Kestrel 5400 from US$479-549 |
| Fixed heat-stress stations | Hardware | US$2,000-10,000 per station (market report) |
| Perry Weather (US): site weather/WBGT station with alerts | Yearly subscription with hardware lease | ~US$3,750 per location per year (school-district contract); ~US$1,100 per site per year in an older 6-site contract |
| SlateSafety BAND V2: wearable on each worker | Device plus monthly software per device | ~US$849 per device (reseller) plus ~US$15 per device per month (third-party evaluation) |
| Kenzen: wearable on each worker | Per worker per month | ~US$160 per worker per month (third-party estimate from rental rates) |

HeatGuard is environment-first like Perry Weather (one station protects a whole site), but adds what UAE
contractors need: crew-specific NIOSH limits, a shift plan, a multilingual worker app, symptom escalation, the
midday break and ADOSH-SF reporting. Wearables are optional, not required.

## Recommended prices

| Plan | Price | Includes |
|---|---|---|
| **Site plan** | **AED 1,100 per site per month**, billed yearly (AED 13,200) | One leased sensor station, dashboard, shift plan, alerts, worker app for every worker on site, reports and exports, support |
| Summer plan | AED 1,400 per site per month, June to September only (AED 5,600) | Same, for contractors who only need the hot season |
| Extra zone station | AED 250 per month | For sites with zones of different exposure (e.g. a deck and a basement) |
| Wearables add-on | Partner device price plus 15% | Optional, consent-based, through device partners |
| Enterprise (10+ sites) | 15-20% discount | HSE-system integration (API), single sign-on, quarterly review |

Why this price:
* It matches what customers already pay for a site alert service (~US$3,750 ≈ AED 13,800 a year) while offering much
  more for UAE crews.
* On a 150-worker site it is about **AED 7 per worker per month**, about 0.25% of a labourer's monthly wage, and a
  small fraction of wearable-only systems (~AED 570,000 in year one for 150 SlateSafety devices with software).
* One avoided midday-break fine (AED 5,000 per worker) or one avoided heat-illness incident covers months of the
  subscription.

### Our costs per site (estimate)

| Item | Estimate |
|---|---|
| Station build (ESP32, DS18B20 in a 150 mm black globe, air temperature/humidity sensor, natural wet-bulb wick, LTE modem, solar panel, battery, IP65 enclosure, tripod), assembled and calibrated | ~AED 1,800, used over 3 years ≈ AED 50 a month |
| Mobile data (SIM) | ~AED 30 a month |
| Cloud hosting share | ~AED 30 a month |
| **Total** | **~AED 110 a month per site**, against AED 1,100 revenue |

The station design follows published low-cost globe-thermometer research (DS18B20 in a metallic black globe). Each
station is checked against a reference WBGT meter before use.

## Pilot plan (no partner yet)

| When | Phase | What happens | Success measure |
|---|---|---|---|
| Dec 2026 - Feb 2027 | Field-ready | Build 3 stations; calibrate them side by side with a reference WBGT meter (Kestrel 5400) for 2+ weeks; contact 20+ HSE managers of Abu Dhabi contractors; apply to the Hub71 Sandbox Programme (connects startups with regulators and testbeds); ask the challenge co-creators for introductions | Stations within ±1 °C WBGT of the reference; 1-2 signed free-pilot agreements |
| Mar - May 2027 | Free pilot | 1 contractor, 1-2 sites, ~200 workers; translations reviewed by native speakers; data-protection impact assessment; agreement with worker representatives on non-punitive use; supervisor and first-aider training | Weekly use by supervisors; stations up ≥98% of the time; worker notice understood by ≥80% (survey) |
| Jun - Sep 2027 | Paid summer pilot | Up to 5 sites at 50% of the price (AED 550 per site per month); compare with the previous summer | Alert lead time ≥15 min; ≥95% of heat alerts with a recorded action; heat-related first-aid cases and lost time vs previous summer; written case study |
| 2028 | Launch | Convert pilot sites; 2-3 more contractors; 30 sites | ~AED 400,000 a year |
| 2029 | Scale | 120 sites; HSE-system integration; Saudi Arabia and Qatar rules | ~AED 1.6 million a year |

Pilot budget: about AED 9,000 (3 stations ~AED 5,400; reference meter ~AED 2,000; SIMs and hosting for 6 months
~AED 1,000; travel and printing extra). The team covers it, or uses prize money or Hub71 incentives if awarded.

## Sources

* [Aletihad: UAE private-sector labour figures](https://en.aletihad.ae/news/business/4436352/uae-s-business-environment-booms-with-increase-in-private-se)
* [Gitnux: UAE construction statistics (ILOSTAT 2023)](https://gitnux.org/uae-construction-industry-statistics/)
* [MoHRE: Midday Break 2025](https://mohre.gov.ae/en/media-center/news/3/6/2025/mohre-to-implement-midday-break-for-the-21st-consecutive-year-from-15-june-to-15-september-2025)
* [Khaleej Times: midday break 2025 and fines](https://www.khaleejtimes.com/uae/uae-midday-break-2025-june-15-to-september-15)
* [ILO Arab States: heat stress and working hours](https://www.ilo.org/wcmsp5/groups/public/---arabstates/---ro-beirut/---ilo-qatar/documents/presentation/wcms_880718.pdf)
* [ADPHC: ADOSH-SF Code of Practice 11.0, Safety in the Heat](https://www.adphc.gov.ae/-/media/Project/ADPHC/ADPHC/PDF/OSHAD-SF/Codes-of-Practise/11---Safety-in-the-Heat-v31-English.pdf)
* [Naukrigulf: construction worker salary in the UAE](https://www.naukrigulf.com/salaries/construction-worker-salary-in-uae)
* [Shawnee Mission School District: Perry Weather contract](https://go.boarddocs.com/ks/smsd/Board.nsf/files/D9NR7H6C9CAA/$file/BOE%20Reference%20-%20Perry%20Weather%20Monitoring%20and%20Alert%20System.pdf)
* [City of Lebanon, Missouri: Perry Weather purchase](https://www.lebanonmissouri.org/DocumentCenter/View/37481/Council-Bill-No-6539--Purchase-Weather-Alert-System-Perry-Weather)
* [Perry Weather pricing](https://perryweather.com/pricing/)
* [Levitt-Safety: SlateSafety BAND V2 listing](https://www.levitt-safety.com/Catalog/Fast-Track/Heat-Stress-First-Aid/ISLS023)
* [SKC: BAND V2 annual portal access](https://skcinc.com/products/band-v2-annual-software-service-subscription)
* [SlateSafety: BAND V2 evaluation (software subscription)](https://slatesafety.com/band-v2-rated-best-physiological-monitoring-system/)
* [AI Home Building: wearable heat sensor costs (Kenzen estimate)](https://aihomebuilding.com/articles/wearable-heat-sensors-construction-worker-resistance)
* [Anaum: heat stress meters in the UAE](https://anaum.com/collections/heat-stress-meters)
* [Future Market Insights: heat stress monitor market](https://www.futuremarketinsights.com/reports/heat-stress-monitor-market)
* [Kestrel 5400 Heat Stress Tracker](https://kestrelmeters.com/kestrel-5400-heat-stress-tracker)
* [ScienceDirect: low-cost black globe thermometers](https://www.sciencedirect.com/science/article/abs/pii/S0168192319305076)
* [Hub71 Sandbox Programme](https://www.hub71.com/program/sandbox-programme)
