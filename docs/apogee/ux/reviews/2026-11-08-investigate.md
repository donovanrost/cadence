# Review: Investigate (fe-ops, 2d7f0aaa), 1440×900, live server + intercepted data

Live: no limits on :4011, so I injected a critical alarm (`HK.battery_voltage` 23.1 vs red low
24.0, yellow 24.5) for EARENDIL-001, two caution sisters (002, 004), a 6 h falling history, and
mission-scope limit intervals.

**Verdict: the structure is right and honest.** The page holds still, the breadcrumb follows
fleet → plane, prev/next is disabled with a reason at the plane's end, facts are omitted when
unknown (U10), and Ack/Assign/B3 are hidden. B2 shows an honest unavailable state, B4 uses the
agreed title and count `2 OF 24`. The chart draws dashed limit lines, a crit wash below red and a
min–max band. Fixes:

1. **Hero status contradicts the alarm.** With an active critical alarm the header still says
   `AWAITING FIRST CONTACT`. The hero tag is the worst *active* state (precedence §2): `◆ CRITICAL ·
   POWER` (subsystem from the alarm). An alarm always outranks fleet `never_heard` (that combination
   is a data race, not a state).
2. **`LIMIT —` while the limit is known.** The alarm carries `thresholds.red_low = 24.0` and the
   intervals agree, but the tile says unknown. → `RED LIMIT 24.0 V` (and the rate tile, see 4).
3. **Literal ids are uppercased.** The B1 title renders `HK.BATTERY_VOLTAGE`, and so do the B4 rows.
   Ids are never case-transformed (design-language §3). → B1 title in words: `<subsystem> ·
   <condition>` ("Power · below red limit"), with the literal id as mono, **not** uppercased, in the
   header meta or Technical details. B4 rows: name + mono `HK.battery_voltage 24.4 V`, no transform.
4. **Rate lives in the legend as `−0.427 per hour`.** → a `RATE` readout tile beside Now / Red
   limit, 2 significant decimals, unit: `−0.43 V/h` (`V/orb` once orbit period exists). The legend
   keeps only the key: series, band, limits.
5. **No units anywhere** (`23.1`, axis `24 / 26`). The alarm/point shape has no unit → **api**:
   add `point.unit` to alarms (M9) and history (M10). UI: unit after values (13px `text-4`) and on
   the y-axis label.
6. Consistency: orbit `P01 · slot 1` → `P01 · slot 01` (as in Setup).

## Second look at 975d9756 (2026-11-08 ~23:05Z; server went flaky mid-review)
Verified: hero tag `CRITICAL · POWER`, B1 title in words (`POWER · OUT OF LIMITS`), RATE tile
(`−0.43` per hour), `P01 · slot 01`. The `LIMIT —` I saw came from my mock sending
`condition: below_low`, which isn't in the contract (`red_low`, `yellow_low`, …), so re-check pending.
New small items:
7. B1 meta shows the point **id** (`point-hk-vbat`); show the point **name** (`HK.battery_voltage`,
   mono, untransformed). Ids stay in Technical details.
8. `LAST TLM 13m 10s ago`: "ago" phrasing is out (design-language §4) → `T+13m` (or
   `22:38:02Z · T+13m`).

## Alarms (31e77d5a), first look
Live (no limits): h1 `GROUND LIMITS OFF` + sentence + `SET UP`. That's exactly the OpsLists rule,
never "0 active". With injected alarms: `3 ALARMS ACTIVE` plus the limits-off callout, table sorted
severity then oldest, L2 By point. Items:
9. The Point column shows the raw condition token (`HK.battery_voltage · below_low`). → words:
   `below red low` / `below yellow low` / `above red high`… (map from `red_low` etc.).
10. `NOW / LIMIT` shows `/ —` with my invalid mock; re-check with valid conditions.

## Fleet (a59f5110)
Not reviewed yet: it stayed on `LOADING FLEET…` for 4.5 s in both views while the server was
struggling. Re-check when :4011 is stable.
