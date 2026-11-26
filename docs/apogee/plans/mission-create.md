# L4 console mission create: shape proposal (fe-setup → api, cc lead)

fe-setup, 2026-11-13. BACKLOG §11 L4. ux: `information-architecture.md` ("Mission creation: Org › Missions › New.
Not on the canvas; build as a reading-layout form"). Replaces the `New mission` link out to the LiveView
`/missions/new` (DECISIONS #64, d50ca428) with the console route `org.missions.new` (`/org/missions/new`).

## What exists (read, 2026-11-13)
- `Cadence.Missions.Creation.create/2` (the LiveView's `MissionPage` save): `{"mission" => {display_name, slug}}`,
  both trimmed, 1–255 bytes; slug `^[a-z0-9][a-z0-9-]*$` ("Use lowercase letters, numbers, and hyphens.").
  Authorizes `:operate_organization` against **`scope.organization_id`**, so it creates in the scope's org, not
  one named in a path. Returns `{mission: {id, display_name, slug, href}}`.
- Slugs are unique per organization (`missions_org_slug_idx`). A clash comes back as a changeset error, not a
  field message the console can show.
- The outside-console `POST /api/organizations/:organization_id/missions` (`MissionController.create`,
  `:manage_missions`) takes the same pair through `IdentityParams.mission/2`. (Retired by #384, director
  2026-11-19, with `IdentityParams`.)
- The console already reads `GET /api/console/v1/organizations/:id/missions` (`{missions: [{id, slug, name,
  spacecraft_count, worst_state}]}`, pass-2 #11).
- Nothing records a mission's creation, so org Audit can't say who created it.

## Proposed endpoints (`/api/console/v1/organizations/:organization_id`)
Who may create: organization admins (and platform admins), the same people the console shows `New mission` to
(`canAdministerOrganization`). Everyone else gets `403 forbidden`.

### M1 slug check (the form's live check, as AD1's)
```
GET /missions/slug?slug=   → {slug, available: bool, suggestion|null}
```
- `suggestion` is a free slug near the asked one (`earendil-2`), only when `available` is false.
- A malformed slug is `available: false` with `suggestion` = the slug normalised (lowercase, hyphens), or null.

### M2 create
```
POST /missions {name, slug}
  → 201 {mission: {id, name, slug}}
  → 422 invalid_params, details {name?: msg, slug?: msg, suggestion?: slug|null}   (flat, as AD1)
  → 403 forbidden
```
- Validation is `Creation.validate/1`'s, mapped to `name` / `slug` keys directly in `details` (the console's
  `fieldErrors` reads them there; AD1's create sends `{"slug" => message, "suggestion" => …}` the same way). A slug clash is a `slug` field error
  ("This slug is already in use.") plus `suggestion`, the same shape as AD1's organization create, so the console
  shows both in one line.
- Authorize and create in **the path's organization** (not `scope.organization_id`), so a member of several orgs
  creates where they are looking.
- **Record it** (org Audit, Organization source): "Mission EARENDIL created by Mira K." Optional for the first cut;
  without it the console says nothing about who created it.

## Console (fe-setup, against fixtures until M1/M2 land)
- `org.missions.new` (`/org/missions/new`): a reading-layout form, not a takeover (IA row "Mission creation";
  U5 reserves takeovers for multi-step wizards, and this is one step). Fields: **Name**; **Slug** (filled
  from the name until edited, live-checked with M1, mono, hint "Used in links: /console/<org>/<slug>").
  Actions: **Create mission** (primary), **Cancel** (back to Missions).
- After 201, a full load to the new mission's **Setup › Readiness**
  (`/console/<org>/<slug>/setup`), so the session bootstrap includes the mission (as accepting an invitation
  does). Readiness is the empty mission's checklist: add a catalog, a profile, spacecraft.
- `org.missions` `New mission` becomes a RouterLink to `org.missions.new`; the host link goes away.
- Errors: 422 fields on the fields; 403 "Only organization admins can create missions."; anything else
  through `failureOutcome`.
