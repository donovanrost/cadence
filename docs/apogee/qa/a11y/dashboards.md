# Dashboards (a11y fixes, 11-16 live checks)

dashboards ran ux's checklist over the dashboard surfaces in code and jsdom. These are qa's
real-browser checks of what that can't show: native dialog focus, key handling in kiosk and
Present, and live-region text. Chromium (Playwright, headless), :4011, `qa-org-admin`, 1500 px.
Real screen-reader output was not captured; roles, accessible names and live-region text stand in
for it.

Commits on `ui/apogee-spa`: 55918344b (words), dbeb407d2 (focus), 8f73787ec (kit: side sheet
refocus, `aria-required`), 4519ff3fe (Library › Rename uses the disabled reason), f6d7e2057 (Present
names each dashboard and focuses its h1).

## Passed

| Check | Result |
| --- | --- |
| Time series name (B5) | `role=img`, e.g. "Mode (HK.sc_mode), 2026-11-14 07:00:00Z to 2026-11-14 07:45:00Z: no samples in this range." |
| Take snapshot opens on | the "With data" radio |
| Versions opens on | the first version's checkbox ("Compare v4") |
| Archive (directory row ⋯) opens on | "Keep it"; Keep it returns focus to "Actions for QA overlays", row kept |
| Kiosk: Esc | leaves kiosk, focus on "More dashboard actions" |
| Remove section, non-empty | the confirm opens on Cancel; Cancel returns to that section's ⋯; nothing removed |
| Discard with no changes | focus returns to Edit |
| Widget sheet open, focus out, press the widget's Edit again | focus goes back to the sheet's first input |
| Save as copy… Name | `aria-required="true"`, no `aria-invalid`, also when emptied; the button's disabled reason "Give it a name." shows |
| Present (existing playlist "Earendil — Demo Rotation", 6 dashboards) | polite region: "1 of 6"; → "2 of 6", → "3 of 6", ← "2 of 6"; Space "2 of 6, paused", Space "2 of 6"; auto-advance after the 30 s dwell "3 of 6". Focus never moved on any advance. The countdown is not in the region (unchanged after 3 s). |

Console errors: 0 on every page. No writes: the only non-GET calls were the viewer's own view
tracking (`POST …/views`) and the edit-mode preview (`POST …/preview`).

## Findings (both resolved 11-16)

1. ~~**Present doesn't announce the dashboard's name.**~~ Fixed f6d7e2057 (ux 05921ba02). Re-checked
   on the same playlist: the polite region reads "Earendil — Fleet Watch, 1 of 6"; → "Earendil —
   Spacecraft Overview, 2 of 6"; Space "Paused: Earendil — Spacecraft Overview, 2 of 6", then
   "Playing: …"; ← back to "Earendil — Fleet Watch, 1 of 6"; the 30 s auto-advance announces the
   next name. Focus never moved.
2. ~~**Present opens with focus on `<body>`.**~~ The shell's route focus (2f246c0d2) moved it to
   `<main>`, which ux didn't accept, because Present's h1 sits outside `<main>`. Fixed f6d7e2057 (ux
   82d87ca69): Present now opens on its own h1, "Playlist · Earendil — Demo Rotation". Esc returns
   to Playlists with focus on that row's Present link.

## Not checked

- **Library › Rename with an empty name (4519ff3fe).** The Library is empty, and saving a widget to
  it is a write. The sheet's markup already carries "Rename" with "Give it a name." as its reason.
- D2 (sheets full height at 390) landed 22fd13334 + 909bdf88f and passed (qa-pass-checklist);
  route-change focus landed 2f246c0d2 + 5ba25fed0 and passed.
