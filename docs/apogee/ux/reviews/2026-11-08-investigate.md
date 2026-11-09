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

## Third look (19887eec) + Fleet, Alarms, ⌘K (2026-11-08 23:15Z, :4011 stable, api #7 live)
**Investigate:** closed except units (api). Verified `POWER · BELOW RED LIMIT`, point name in mono
in the meta, `RED LIMIT 24`, `RATE −0.43 per hour`, `LAST TLM T+00:19:03`.
**Alarms:** closed. Conditions read `below red limit` / `below yellow limit`, `23.1 / 24`, limits-off
state right.
**⌘K palette:** passes Palette.md. Combobox semantics with an active descendant; `31` → EARENDIL-031
first (SCID match); state shown by mark + words; `SHOW ALL 15 SPACECRAFT`; key hints. Nice.
**Fleet:** table + matrix, URL filters, state chips with marks, stale rows tinted, `never` for
never heard. Good. Items:
11. **Limit precision:** show a limit with the value's precision: `24.0` beside `23.1` (Investigate
    tile, Alarms `23.1 / 24.0`).
12. **Plane · slot** in the Fleet table reads `P01 · 1` → `P01 · 01` (zero-padded like Setup's
    table; Investigate's fact keeps `P01 · slot 01`).
13. **Caption truth (U13 refined):** with 10 stale spacecraft, Caution/Critical say `no telemetry
    yet`, but telemetry *was* received. Captions in priority: `limits not configured` (when ground
    limits are off, the real reason) → `no fresh telemetry` (when nothing is fresh) → the normal
    caption. The same applies on Now.

## Alarm lifecycle on Investigate (77f93bad), injected episodes, 1440×900
Injected: ground-limit episode, NEW, critical; events raised (caution) → acknowledged by Mira K. →
escalated to critical; acknowledge returns acknowledged; assign returns 502.
Verified: the episode bar with `◆ NEW` + `GROUND LIMITS · EVALUATED 00:56:55Z · T+00:12:09` (U16),
`Acknowledge` primary + `Assign`; `AT EVALUATION` readout; units; B2 lists the episode events with
marks; after ack: `■ ACKNOWLEDGED BY QA ORG ADMIN`, hero tag stays critical (correct); inline assign
row (person select + optional note + disabled Assign).
14. **Escalation callout missing:** with ack → escalated → status `new`, U16 wants `ACK CLEARED ·
    ESCALATED TO CRITICAL` (caution) in the bar until re-acked. Not shown. Check what it keys on: the
    events here are `acknowledged` then `escalated` (payload `{from, to}`).
15. After ack, say who and when: `ACKNOWLEDGED BY YOU · 01:09Z` (you = current user).
16. When the assign row is open, the header `Assign` should become `Cancel` (or carry
    `aria-expanded`). Two `ASSIGN` buttons on screen is ambiguous.
17. Rate unit compact: `V/h` (not `V per hour`).
18. **Rail `ALARMS 0`** while ground limits aren't configured: the same U13 logic applies to rail
    counts. Omit the count (or `—`) when limits aren't configured and there are no live-source episodes.
Not exercised: the assign-failure path (the picker lists no people on :4011).

**Closed (8241c0e8):** 14 verified (`Ack cleared · escalated to critical` shows), 16 verified (header toggles to `Cancel`), 17 verified (`V/h`). 15 renders `ACKNOWLEDGED BY QA ORG ADMIN · 01:14Z`: the time is there, and "by you" didn't trigger only because my mock's actor id isn't the session user's. Accepted. 18: the rail no longer shows an Alarms count. Lifecycle review closed.

## Alarms on episodes (566f6998), injected episodes, 1440×900
Verified: tabs with counts, Owner (`UNASSIGNED`) and Source columns, `23.1 V / 24.0 V`, conditions
in words, the limits-off callout, L2 By point. Items:
19. **"Active" means two things:** the h1 says `2 ALARMS ACTIVE`, but the `Active` tab counts 1
    (unacknowledged only); acknowledged alarms are still active. → tabs `New 1 · Acknowledged 1 ·
    Cleared · 24 h`, h1 `2 alarms active · 1 new`.
20. **Source column clipped** at the table's right edge (`GROUND` cut off) next to L2. → give the
    table its columns (narrow L2 to 300px or let the table scroll inside its panel), or put the
    source tag under the severity in the first column.
Not checked: the Cleared tab content (my tab click didn't land); re-check on the next pass.
