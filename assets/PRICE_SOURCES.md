# Room Rig price basis (Philippine peso, ₱)

Every peso figure in Room Rig — catalog items, preset room bootstraps, scan-seeded
door/window costs and the upgrade shop — is an **estimate**, not a quote. This file is
bundled with the app so the basis for each number can be checked by anyone.

## Method

* **Market:** Philippines, mid-market tier. Not the cheapest no-brand listing and not
  premium imports; the price a typical buyer in Metro Manila would pay for a sensible
  branded unit.
* **Where the bands come from:** publicly listed PH retail prices from the retailer
  classes below. Each figure is the rounded midpoint of the mid-market band seen across
  those classes when the catalog was researched (2025). Bands move with sales (9.9 /
  11.11 / 12.12), stock and brand; expect **±30 %**.
* **Retailer classes used**
  * *Marketplaces:* Lazada PH, Shopee PH (brand/official stores, not grey resellers).
  * *Appliance chains:* Abenson, SM Appliance Center, Anson's, Western Appliances.
  * *Furniture / home:* SM Home, Our Home, Mandaue Foam, Uratex, IKEA Philippines.
  * *Brand PH stores:* Xiaomi PH, Asahi, Hanabishi, Union, Carrier / Condura / Kolin,
    Firefly / Omni (lighting), Secretlab PH / Fantech (gaming).
  * *Builders' depots (doors / windows / vents):* Wilcon Depot, AllHome, CW Home Depot.
* **How to verify a line:** search the *Verify with* terms on two retailer classes
  listed for that row and compare against the band. If the midpoint has drifted outside
  the band, update the number in `lib/models/room_catalog.dart` (or the file named in
  the *Code* column) **and** this table in the same commit.
* **What "est." means in the app:** the item inspect panel and the Add-item sheet show
  `est. ₱…` plus a one-line basis hint drawn from this file via
  `lib/models/price_sources.dart`. There is no live price feed or scraper by design —
  prices are explicitly editorial and reviewed by hand.

## Catalog items (`lib/models/room_catalog.dart`)

| Item (baseId) | ₱ in app | Mid-market band | Retailer classes | Verify with |
|---|---:|---:|---|---|
| Desk (`desk`) | 4,500 | 3,000 – 7,000 | Marketplaces, SM Home / Our Home, IKEA PH | "computer desk 120cm", IKEA LINNMON/ADILS, MICKE |
| Chair (`chair`) | 3,500 | 2,500 – 6,000 | Marketplaces, Our Home, IKEA PH | "ergonomic office chair mesh", IKEA FLINTAN |
| Gaming Desk (`gaming_desk`) | 5,500 | 4,000 – 9,000 | Marketplaces (Fantech, Rakk), Secretlab PH | "gaming desk 140cm carbon fiber" |
| PC Tower (`pc`) | 45,000 | 35,000 – 65,000 | DynaQuest, PCHub, EasyPC, Shopee official stores | "RTX 4060 gaming PC build", mid-range prebuilt |
| Bed (`bed`) | 12,000 | 8,000 – 20,000 | Mandaue Foam, Uratex, SM Home | "double bed frame with foam mattress" |
| Sofa (`sofa`) | 15,000 | 10,000 – 25,000 | Mandaue Foam, SM Home, Our Home | "3-seater fabric sofa" |
| Table (`table`) | 3,500 | 2,000 – 6,000 | SM Home, IKEA PH, marketplaces | "coffee table wood", IKEA LACK/HEMNES |
| Wardrobe (`wardrobe`) | 9,000 | 6,000 – 15,000 | SM Home, Our Home, marketplaces | "2-door wardrobe cabinet" |
| Shelf (`shelf`) | 2,500 | 1,500 – 5,000 | IKEA PH, marketplaces | "5-tier bookshelf", IKEA BILLY/KALLAX |
| Plant (`plant`) | 350 | 150 – 800 | Marketplaces, weekend plant markets, SM Home | "indoor plant snake plant potted" |
| TV (`tv`) | 15,000 | 10,000 – 25,000 | Abenson, SM Appliance, Xiaomi PH | "43-inch smart TV 4K" |
| Door (`door`) | 4,500 | 3,000 – 8,000 | Wilcon Depot, AllHome, CW Home Depot | "interior door flush PVC/wood 80cm" |
| Window (`window`) | 8,000 | 5,000 – 15,000 | Wilcon Depot, AllHome, glass & aluminium shops | "aluminium sliding window 1.2m" |
| Wall AC (`ac`) | 25,000 | 18,000 – 40,000 | Abenson, SM Appliance, Carrier/Condura/Kolin | "1.0 HP inverter window type / split AC" |
| Intake Vent (`intake_vent`) | 2,500 | 1,500 – 5,000 | Wilcon Depot, marketplaces | "wall ventilation grille duct fan" |
| Exhaust Fan (`exhaust_fan`) | 1,500 | 900 – 3,000 | Abenson, Wilcon, marketplaces (Asahi, Hanabishi) | "8-inch wall exhaust fan" |
| Portable AC (`portable_ac`) | 18,000 | 14,000 – 28,000 | Abenson, SM Appliance, marketplaces | "portable aircon 1.0 HP" |
| Stand Fan (`fan`) | 1,500 | 900 – 3,000 | Abenson, marketplaces (Asahi, Hanabishi, Union) | "16-inch stand fan" |
| Space Heater (`space_heater`) | 2,000 | 1,200 – 4,000 | Marketplaces, Abenson | "electric room heater fan" |
| Task Lamp (`lamp`) | 800 | 400 – 1,800 | Marketplaces (Firefly, Omni, Xiaomi PH), IKEA PH | "LED desk lamp dimmable" |
| Floor Lamp (`floor_lamp`) | 2,500 | 1,500 – 5,000 | IKEA PH, SM Home, marketplaces | "floor lamp standing LED" |
| Ceiling Light (`ceiling_light`) | 1,800 | 900 – 4,000 | Wilcon Depot, marketplaces (Firefly, Omni) | "LED ceiling light 24W round" |
| Air Purifier (`purifier`) | 8,000 | 5,000 – 15,000 | Xiaomi PH, Abenson, marketplaces | "HEPA air purifier 30 sqm" |
| Custom item (`custom`) | 0 | — | — | User-entered; no basis |

## Preset room bootstraps (`lib/models/room_model.dart`)

Preset rooms reuse the catalog bands above; a few preset-specific SKUs differ:

| Preset item | ₱ in app | Band | Classes | Verify with |
|---|---:|---:|---|---|
| Gaming Chair | 5,500 | 4,000 – 9,000 | Marketplaces (Fantech, Rakk), Secretlab PH | "gaming chair PU leather" |
| Gaming PC Tower | 55,000 | 45,000 – 80,000 | DynaQuest, PCHub, EasyPC | "RTX 4070 prebuilt gaming PC" |
| Gaming Monitor | 6,500 | 5,000 – 10,000 | Abenson, marketplaces (AOC, Nvision, Xiaomi) | "24-inch 144Hz monitor" |
| Monitor (office) | 5,500 | 4,000 – 8,000 | Abenson, marketplaces | "24-inch IPS monitor 75Hz" |
| RGB Desk Lamp | 1,200 | 700 – 2,500 | Marketplaces (Xiaomi PH, Baseus) | "RGB monitor light bar / desk lamp" |
| Standing Desk | 10,000 | 7,000 – 18,000 | Marketplaces (Flexispot PH, Ergodesk) | "dual motor standing desk" |
| Ergonomic Chair | 8,000 | 6,000 – 15,000 | Marketplaces (Sihoo, Ergohuman PH), Our Home | "ergonomic mesh chair lumbar" |
| Murphy Bed | 18,000 | 12,000 – 35,000 | Custom carpentry quotes, marketplaces | "murphy wall bed Philippines" |
| Compact Sofa | 12,000 | 8,000 – 18,000 | Mandaue Foam, SM Home | "2-seater loveseat sofa" |
| Fold Desk | 3,500 | 2,000 – 6,000 | IKEA PH, marketplaces | "wall mounted folding desk", IKEA NORBERG |
| Low Bed Frame | 12,000 | 8,000 – 20,000 | Mandaue Foam, Uratex, IKEA PH | "platform bed frame queen" |

Scan-seeded rooms and the Create-room flow (`lib/services/scan_layout_converter.dart`,
`lib/models/app_state.dart`) bootstrap only a Door (₱4,500) and a Window (₱8,000) using
the catalog bands above.

## Upgrade shop (`lib/models/upgrade_catalog.dart`)

| Upgrade | ₱ in app | Band | Classes | Verify with |
|---|---:|---:|---|---|
| Air Circulator Fan | 1,500 | 900 – 3,000 | Abenson, marketplaces | "air circulator fan" |
| Smart Air Purifier | 8,000 | 5,000 – 15,000 | Xiaomi PH, Abenson | "smart HEPA air purifier" |
| Diffused Floor Lamp | 2,500 | 1,500 – 5,000 | IKEA PH, SM Home | "floor lamp diffused shade" |
| Smart Blinds | 8,000 | 5,000 – 15,000 | Marketplaces (Aqara, SwitchBot PH), blinds shops | "motorized roller blinds 1.2m" |

## Review log

| Date | Change |
|---|---|
| 2025 | Initial research pass; all figures set as mid-market midpoints. |
| 2026-10-27 | Basis documented and shipped in-app; no price values changed. |
