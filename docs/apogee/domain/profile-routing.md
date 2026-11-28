# Profile-level routing, overrides and the profile field schema (DECISIONS #3)

Owner: **domain**. Status: **draft 1 for review** (2026-11-08). Reviewers: director, api, fe-setup, ux.
UX contract: `docs/apogee/ux/screens/Profile.md` (P1 field schema, P2 rules, P3 overrides, P4 effect).
Depends on `change-sets.md`: every write here is a change-set op. `L` = `apps/cadence/lib/cadence`.

## 0. Summary

1. **Routing rules become part of the Spacecraft Profile version.** One profile rule is
   "for each spacecraft on this profile × each station in [...], route these legs, named by this
   template". Rules are versioned with the profile, because the profile is the versioned template
   and spacecraft pin a version.
2. **Routes are materialized per spacecraft, into the existing `comms_routing_rules` table**, which
   becomes the route table (`origin: profile | spacecraft`). Contact scheduling, booking, validation
   and dashboards keep reading it unchanged. Materialization happens on apply, in the same
   transaction as the revision.
3. **Ground stations become real in routing.** A transport gets a first-class `ground_station_id`
   (today it is seed-only metadata), and stations get a short `code` (`SVB`). Opportunity search
   starts sending the station ref, which it hard-codes to `[]` today.
4. **One override model for every section.** A spacecraft override is `(spacecraft, path) → value`
   with who, why and `since rN`. Effective config = pinned profile version ⊕ overrides. Overrides
   **replace the synthetic per-spacecraft profiles** that activation forks today.
5. **The profile field schema is served by the domain** (label, type, unit, enum, range, default,
   overridable). It contains **only fields the runtime really consumes.** Several canvas fields have
   no backing and are not in it (§3).
6. **Migration lifts today's per-spacecraft rules into profile rules + overrides**, staged as a
   reviewable change set whose preview proves the effective routes are identical.

## 1. What exists

Detail and refs: change-sets.md §1, plus these routing facts:
- A rule is one spacecraft × one exact transport version, with direction
  (`inbound|outbound|bidirectional`) and role (`primary|candidate|contributing`). There is no
  station, no PK, and uniqueness is on id only (`L/comms/routing_rule_row.ex`).
- Saving materializes a new PathTemplate + LinkAssignment per direction **on every save and never
  retires the old ones**; orphans stay `active` (`L/comms/routing_rule_store.ex:288-390`).
- The only runtime consumer is `ProviderScheduling.list_ready_downlink_routes/resolve_rule`
  (`L/contacts/provider_scheduling.ex:75-314`), which handles downlink only. Contacts snapshot the
  path template at booking, so rule changes never touch booked contacts.
- Rules pin a transport *version*, and nothing re-points them when the transport changes.
- `PathTemplate` + `LinkSetup.apply_link_template/5` is an older template-to-many mechanism with
  name patterns. `LinkAssignment` already supports per-spacecraft overrides of provider refs.

## 2. Model

### 2.1 Profile rules (part of a profile version)

```
spacecraft_type_routing_rules
  org, mission, spacecraft_type_id, spacecraft_type_version, rule_id, position,
  display_label, name_template, purpose_label, enabled,
  stations  jsonb  [{ground_station_id, transport_id}]      -- transport_id optional, see below
  legs      jsonb  [{direction: downlink|uplink, role: primary|candidate|contributing}]
  PK (mission_id, spacecraft_type_id, spacecraft_type_version, rule_id)
```

- **Stations → transport:** each station entry names the transport that reaches it. If it is
  omitted, the station's single active transport that is compatible with every leg is used.
  Ambiguity or no match is a validation error ("Svalbard has 2 downlink transports, pick one").
  Rules reference `transport_id`, **not a version**. Materialization resolves the current version
  at apply. Since transport edits are change-set ops too, a transport change re-materializes its
  routes in the same revision. That fixes today's "nothing re-points" gap.
- **Legs** replace `direction`. `bidirectional` is two legs. Each leg's direction is checked
  against `transport.direction_capability`, which is not checked today.
- **Name template tokens:** `{station}` (station code), `{station_name}`, `{spacecraft}`
  (display name), `{scid}`, `{direction}`. Unknown tokens are a validation error. The rendered
  name is ≤ 200 chars (the existing `display_name` limit).
- **Count:** routes = |spacecraft inheriting| × |stations| × |legs| − exclusions.
- **Editing a rule** is a `profile_routing_rule` op (create/update/delete/reorder). On apply it
  becomes part of profile version v+1 (see §2.4).

### 2.2 Materialized routes (the existing table, extended)

`comms_routing_rules` gains:
- `id` bigserial PK
- `origin` (`profile | spacecraft | legacy`)
- `profile_rule_id`, `spacecraft_type_id`, `spacecraft_type_version`
- `ground_station_id`, `leg_direction`

It also gets a unique index on `(mission_id, spacecraft_id, profile_rule_id, ground_station_id,
leg_direction) WHERE origin = 'profile'`. `direction` keeps its current values (`inbound`/`outbound`)
so readers don't change. `routing_rule_id` for profile routes is deterministic:
`route:<rule_id>:<spacecraft_id>:<station_id>:<leg>`, so re-materialization is an upsert, not a mint.

**Materialization (in `kind.apply`, inside the apply transaction)** works per affected spacecraft:
1. Compute the desired route set from the pinned profile version's rules, minus overrides.
2. Diff against the current `origin: profile` rows. Upsert the changed ones, and archive the gone
   ones.
3. Re-materialize PathTemplate/LinkAssignment **only for routes that changed**, and **retire**
   (soft-delete) the superseded template/assignment. That fixes the orphan leak.
4. Write route add/remove counts into the revision entry (not one entry per route: a rule change
   on 500 spacecraft is one entry with `effect: {added: 500, removed: 0}`).

`origin: spacecraft` rows are spacecraft-local extra routes (kind `spacecraft_route`). They appear
in P3 as overrides ("adds a route via Inuvik"). `origin: legacy` marks rows not yet lifted (§6).

### 2.3 Overrides

```
spacecraft_config_overrides
  org, mission, spacecraft_id, path, value jsonb, reason NULL,
  set_by (doc), set_in_revision, set_at
  PK (mission_id, spacecraft_id, path)
```

- `path` must be a schema field with `overridable: true` (§3), or a routing path:
  - `routing.<rule_id>.excluded_stations`: a list of station ids
  - `routing.<rule_id>.enabled`: `false` to opt out of a rule
- **Effective config** (`Cadence.SpacecraftType.Effective.resolve(profile_version, overrides)`)
  is pure and used everywhere: materialization, spacecraft configuration entries for the binding
  set, reads, preview.
- When the profile changes a path that a spacecraft overrides, the **override wins** (P4 "keeps
  1 SC"). If an override ends up equal to the new profile value, the read flags it
  (`redundant: true`) so P3 can offer Reset. It is not auto-deleted, because the user pinned it.
- Reset is a `spacecraft_override` op `reset` (delete the row). `since rN` = `set_in_revision`.
  Overrides set before change sets land (or by the migration) have `set_in_revision: nil` and
  `set_at`, and the UI shows "since <date>".
- Kinds: `spacecraft_override` (set/reset) and `spacecraft_route`.

### 2.4 Profile versions under change sets (answers Profile.md P4 "v5 / pinned spacecraft")

A `spacecraft_profile` update op (fields, rules, catalog) produces **one new version v+1 on apply**.
The op carries `rollout`:
- `all` (default): every spacecraft pinned to the profile's current version moves to v+1;
- `spacecraft: [ids]`: a subset (catalog C3 rollout "Block 2 only");
- `none`.

Spacecraft on older versions stay where they are and show as drift (existing `stale_versions`).
"Inherited by 500" = spacecraft pinned to the current version. The effect preview counts
`changes` = moved spacecraft without an override on the path, and `keeps` = moved spacecraft with
an override, plus spacecraft not moved.

### 2.5 Catalog on the profile

A profile version gets `catalog_revision_id` (nullable). Spacecraft configuration entries take the
effective value (profile, or a `catalog_revision_id` override). The `catalog_assignment` op is
sugar for "profile catalog update with rollout" or "override on a subset". This fixes the plan's
"profiles using a catalog" gap: catalog usage counts come from effective config.

## 3. Field schema (P1 form generation)

`Cadence.SpacecraftType.Schema.sections/0` returns, per section, a list of
`%{path, label, type, unit, enum, range, default, overridable, runtime_impact, help}`:
- `type`: `integer | boolean | enum | string | reference`
- `enum`: `[%{value, label}]` (e.g. `%{value: "tm", label: "CCSDS TM"}`), so the UI never
  hard-codes protocol names
- `runtime_impact`: `generation | routes | none`

It is backed by the fields that the profile form, `ConfigurationInput.from_profile` and the decoders
actually consume today:

| Section | Path | Label | Type / range | Default | Overridable |
| --- | --- | --- | --- | --- | --- |
| framing | `downlink_protocol` | TM transfer frame | enum `tm, aos, uslp` | `tm` | yes |
| framing | `uplink_protocol` | TC transfer frame | enum `tc, uslp` | `tc` | yes |
| framing | `packet_protocol` | Packet protocol | enum `space_packet` | `space_packet` | no |
| framing | `frame_parameters.frame_size` | TM frame length | integer, bytes, 1..65535 (TM/AOS ≤ 2048; validated per protocol) | 1115 | yes |
| framing | `frame_parameters.secondary_header_length` | Secondary header | integer, bytes, 0..64 | 0 | yes |
| framing | `frame_parameters.insert_zone_length` | Insert zone (AOS) | integer, bytes, 0..frame size (validated with the frame) | 0 | yes |
| framing | `frame_parameters.ocf_length` | Operational control field | enum `0, 4` (bytes) | 0 | yes |
| framing | `frame_parameters.truncated_primary_header` | Truncated primary header (USLP) | boolean | false | yes |
| catalog | `catalog_revision_id` | Catalog revision | reference → catalog revisions | none | yes |
| routing | rules (§2.1) | | structured editor, not key/value | | per rule (§2.3) |
| apps | `applications.<key>.*` | from each app's declared config schema | | | per app |

**Not in the schema (no model backing; the UI must not render them as editable):** spacecraft id
source, virtual channel list, frame error control/FEC, TC segment, randomizer, and "protocol
behavior". Protocol behavior is a retired concept; Spacecraft Profile + Transports + Routing Rules
replaced it. ux: the P2 "Protocol behavior: default" line and the Readiness "3,000 routes use
default protocol behavior" finding should go. If you want VCs/FEC/randomizer, that is a
framing-model extension in the CCSDS pipeline and a director-level scope call.

**Limits & Commanding sections:** limit definitions are **mission-wide per point** today
(`governed_limit_definitions` has no spacecraft or profile). Per-profile limits and the canvas
override "VBAT red limit 23.5 V on EARENDIL-047" are **not backed**. The honest v1 is a read-only
Limits section ("Limits apply mission-wide; per-profile limits are not supported yet"), until the
director decides whether limits move onto the profile. Commanding has no profile-level settings
today, beyond what each app declares in `applications`.

## 4. How this reaches the runtime

- **Framing / protocol / apps / catalog** reach it through the spacecraft configuration entries
  built from **effective** config at apply → binding set → activation generation (change-sets.md
  §7). Activation stops forking synthetic profiles: the pin stays on the real profile and
  overrides carry the difference.
- **Routes** reach it through materialized rows → read at scheduling/booking. Apply calls
  `Contacts.Scheduler.notify_contact_changed`. Booked or running contacts keep their snapshot.
- **Gap I'm not fixing here (flag for api/fe-ops):** provider scheduling only consumes downlink
  routes. Uplink legs materialize (and validate) but don't reach realized contacts through the
  provider-scheduling path today.

## 5. Read shapes (targets from Profile.md)

```
profile_detail(scope, profile_id) →
  %{profile: %{id, name, version, catalog_revision, protocols, last_change: %{revision, at, actor}},
    inherit_count, override_count,
    sections: [%{key, fields: [%{schema..., value, overridden_by: n}]}],
    rules: [%{id, stations: [%{id, code, name, transport_id}], legs: [%{direction, role}],
              name_template, route_count, samples: [string] (3), enabled}],
    overrides: [%{spacecraft: %{id, name}, section, path, profile_value, spacecraft_value,
                  reason, since_revision, set_at, actor, redundant}]}
```

- `samples` are rendered from the first spacecraft × stations in order.
- ux's shape has `legs: [{direction, transport}]`. In the model, transport is per *station* (a leg
  is direction + role). The canvas's "downlink → archive · uplink ← console" destinations do not
  exist as a model concept, so ux please render legs as direction + role.
- `stations[].code` is a new short code on ground stations, unique per mission, required for new
  stations, backfilled from the display name for existing ones.

## 6. Migration of existing data

All of it is **staged as change sets** by a mix/release task
(`mix cadence.config.lift_routing --mission <id>`). Nothing changes until someone reviews and
applies it, and the revision says exactly what moved.

**A. Schema migrations (no behaviour change):** add the route columns + PK, the
`ground_station_id` column on transports (backfilled from `metadata["ground_station_id"]`), station
`code`, `spacecraft_type_routing_rules`, `spacecraft_config_overrides`, and the profile
`catalog_revision_id`. Existing rule rows get `origin: legacy`.

**B. Lift legacy rules** (per mission, per profile version):
1. Group active rules by the spacecraft's pinned profile version. Signature = `(transport_id,
   direction, role, provider_path_ref)`. Station = the transport's `ground_station_id`.
2. A signature held by ≥ half of the version's spacecraft becomes a station/leg of a profile rule.
   Signatures with the same (direction, role) merge into one rule with a station list.
3. A spacecraft missing a lifted signature gets an `excluded_stations` override. A spacecraft with
   extra signatures keeps them as `origin: spacecraft` routes.
4. Disabled rules count as absent. Spacecraft without a profile keep their rules as
   `origin: spacecraft`.
5. `name_template` is inferred when every display name matches one token pattern. Otherwise it
   defaults to `"{station} · {spacecraft}"`. Renaming routes is visible in the diff.
6. **Proof:** the preview compares the set of effective `(spacecraft, transport, direction, role)`
   before and after. Any difference is a NO-GO naming the spacecraft.
7. Orphaned PathTemplates/LinkAssignments from past re-saves are retired in the same revision.

**C. Synthetic profiles → overrides.** For each spacecraft pinned to
`spacecraft_configuration_profile_*`, the original profile is not recorded (activation overwrote
the pin). Base = the mission's non-synthetic profile with the same protocol pair used by the most
spacecraft. The overrides are the framing paths that differ. If no base fits, the synthetic profile
is promoted to a named profile ("EARENDIL-389 framing (migrated)"). Note: synthetic profiles today
silently drop the base profile's `applications`. The migration preview lists those spacecraft as a
HOLD.

**D. Seed and fixtures:** `dev/seed/earendil.exs` creates the shared profile, per-site transports,
and spacecraft routes through the REST change-set API. `RoutingRuleStore.create_routing_rule`
stays for `origin: spacecraft` and for tests until P3.

## 7. Placement

- Profile rules, schema and effective config: `L/spacecraft_type*` (identity context).
- Route materialization: `L/comms/route_materializer.ex` (comms context; comms → identity is
  allowed).
- Kinds `profile_routing_rule`, `spacecraft_route` → `L/comms/config_kinds/`.
- Kinds `spacecraft_override`, `spacecraft_profile` → `L/spacecraft/config_kinds/`.
- Station code and the transport station link: `L/comms/`.

## 8. Open questions

- **director:** Limits on the profile (and per-spacecraft limit overrides) are a model change in
  the telemetry/limits context. In or out for this phase? (I recommend out; Limits is read-only
  with an honest note.)
- **director:** VCs / FEC / randomizer framing fields: out (not in the pipeline) unless you say
  otherwise.
- **api:** Is the station `code` (short, unique per mission) acceptable as a new required field on
  station create?
- **fe-setup / ux:** The lift threshold "≥ half of a version's spacecraft" is my default. Any
  preference? The review page will show the result either way.
- **fe-ops:** Uplink legs don't reach realized contacts via provider scheduling (§4). Is that known
  on your side for Command/Uplink?
