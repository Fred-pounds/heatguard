# Business model and market (draft)

> **Status:** draft for the challenge submission. Market figures are from public sources (below). **All HeatGuard
> prices are assumptions** to be validated with customers during the pilot.

## Market

| Figure | Value | Source |
|---|---|---|
| Construction workers in the UAE | ~1.4 million (2023) | ILOSTAT, as compiled by Gitnux; MoHRE private-sector data reports ~1.416 million |
| Construction establishments | ~81,000 | MoHRE private-sector data (via Aletihad) |
| Midday-break fine | AED 5,000 per worker, up to AED 50,000 | MoHRE (via Khaleej Times) |
| Working hours lost to heat, Arab States, 2030 | ~1% (construction hardest hit) | ILO, *Working on a warmer planet* (2019) |

First customers: tier-1 and tier-2 contractors on Abu Dhabi projects, through their HSE managers. Later: oil and
gas, utilities, logistics, ports and landscaping, then other Gulf countries (the rules engine is configurable).

## Revenue model (assumed prices)

| Item | Draft price | Notes |
|---|---|---|
| Site subscription | AED 1,500 per site per month | Dashboard, worker app, shift plan, alerts, reports. About AED 10 per worker per month on a 150-worker site. |
| Sensor station | AED 4,000 per site or zone, or leased | ESP32 station kit, or a certified WBGT meter with a data link (e.g. Kestrel 5400 Pro with LiNK, about US$600). |
| Optional wearables | Per consenting worker, through device partners | Never required; consent-based. |

Illustration: 100 sites × AED 1,500 × 12 months ≈ AED 1.8 million a year in subscriptions.

## Alternatives for one 150-worker site (year one)

| Approach | What it gives | Approximate cost |
|---|---|---|
| Handheld WBGT meter | Manual readings; no crew limits, shift plan or alerts | ~AED 2,000 (Kestrel 5400 from US$479-629) plus staff time |
| Wearable on every worker | Individual alerts; device and fee per worker | ~AED 470,000 for devices (SlateSafety BAND V2 ~US$849 each, 150 workers) plus annual portal access per device; Kenzen is sold per worker per month |
| HeatGuard | Crew-level limits, shift plan, alerts, worker app, midday-break compliance, reports; wearables optional | ~AED 22,000 (AED 1,500 × 12 + AED 4,000 station) |

Conversion: 1 USD = 3.6725 AED. Competitor prices are list prices from reseller or manufacturer pages and may change.

## What the pilot must confirm

* Willingness to pay at the draft price per site, and who pays (contractor, client or developer).
* Number of stations needed per site (one per work zone with different exposure).
* Hardware choice: own station kit or certified WBGT meter with a data link.
* Savings that matter to buyers: avoided heat incidents and fines, documented duty of care, lost work time.

## Sources

* [Aletihad: UAE private-sector labour figures](https://en.aletihad.ae/news/business/4436352/uae-s-business-environment-booms-with-increase-in-private-se)
* [Gitnux: UAE construction statistics (ILOSTAT 2023)](https://gitnux.org/uae-construction-industry-statistics/)
* [MoHRE: Midday Break 2025](https://mohre.gov.ae/en/media-center/news/3/6/2025/mohre-to-implement-midday-break-for-the-21st-consecutive-year-from-15-june-to-15-september-2025)
* [Khaleej Times: midday break 2025 and fines](https://www.khaleejtimes.com/uae/uae-midday-break-2025-june-15-to-september-15)
* [ILO Arab States: heat stress and working hours](https://www.ilo.org/wcmsp5/groups/public/---arabstates/---ro-beirut/---ilo-qatar/documents/presentation/wcms_880718.pdf)
* [Levitt-Safety: SlateSafety BAND V2 listing](https://www.levitt-safety.com/Catalog/Fast-Track/Heat-Stress-First-Aid/ISLS023)
* [SKC: BAND V2 annual portal access](https://skcinc.com/products/band-v2-annual-software-service-subscription)
* [Kenzen system (per worker per month)](https://forconstructionpros.com/business/construction-safety/product/21132231/kenzen-realtime-body-heat-monitoring-system)
* [Kestrel 5400 Heat Stress Tracker](https://kestrelmeters.com/kestrel-5400-heat-stress-tracker)
