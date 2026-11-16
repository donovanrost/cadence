# Dashboards (a11y fixes, 11-16 live checks)

dashboards ran ux's checklist over the dashboard surfaces in code and jsdom. These are qa's
real-browser checks of what that can't show: native dialog focus, key handling in kiosk and
Present, and live-region text. Chromium (Playwright, headless), :4011, `qa-org-admin`, 1500 px.
Real screen-reader output was not captured; roles, accessible names and live-region text stand in
for it.

Commits on `ui/apogee-spa`: 55918344b (words), dbeb407d2 (focus), 8f73787ec (kit: side sheet
refocus, `aria-required`), 4519ff3fe (Library › Rename uses the disabled reason).

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

## Findings

1. **Present doesn't announce the dashboard's name** (dashboards; ux decides). ux's check asks that
   each advance announce the new dashboard's name. The region reads only the position ("2 of 6"),
   and the visible h1 is the playlist's name, so a screen-reader user hears which slot, not which
   dashboard.
2. **Present opens with focus on `<body>`** (shell / dashboards). Same family as the
   no-focus-on-route-change gap dashboards flagged to lead.

## Not checked

- **Library › Rename with an empty name (4519ff3fe).** The Library is empty, and saving a widget to
  it is a write. The sheet's markup already carries "Rename" with "Give it a name." as its reason.
- **D2** (ApSheet full-height at 390) and focus on route change: flagged to lead by dashboards;
  kit/shell work.
