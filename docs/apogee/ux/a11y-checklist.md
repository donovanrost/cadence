# Accessibility checklist: interactions and newer surfaces (ux, for qa's §6 pass)

qa's run 2 (`qa/a11y/README.md`) covered axe, h1 and landmarks, and Tab traversal, read-only, on 36 screens. This
list covers what that method can't see: what happens when something is **opened, confirmed or closed**. It also
covers surfaces built after 11-13. The rules are design-language §6. Each line is one pass/fail check. Run at 1440
and 390 as admin and member, as before, and record results in the screen's `qa/a11y/<screen>.md`.

## A. Every sheet and dialog (check each one listed in C)
1. **Opens with focus inside it:** on the first field. For a **danger** sheet, focus goes to the safe button
   (`Cancel`, `Keep contact`), never to the danger action.
   *Danger sheets with a required reason* (ReasonSheet's revokes, Send back; ux 11-16, from the setup audit): focus
   goes to the **Reason** field. That's safe because the danger action stays disabled until a reason is given, and
   Enter in a textarea adds a line, it doesn't submit. The field does **not** move above the consequence: the order
   stays title → consequence sentence → Reason → failure → Cancel, then the action. Because focus skips the sentence,
   the sheet must be described by it (`aria-describedby` on the dialog pointing at the sentence), so it's read on
   open. Without that, it fails A1.
2. **Named:** the dialog's accessible name is its title (`aria-labelledby`).
3. **Trapped:** Tab and Shift+Tab cycle inside it, never reaching the page behind.
   *Exception, the non-modal side sheet*: Tab may leave it for the page. It covers two kinds and no others:
   - Dashboards edit's Widget sheet, which keeps the board usable.
   - A **detail sheet beside what it details** (#243): the sheet shows the row or point picked from a list or plot
     that stays on screen, and from 1100px the same detail is an inline pane. Picking another one swaps the
     sheet's content. Today: Contact history's pass sheet and Investigate's Sample aside (U80), both at 768–1099px.

   It's then `role="dialog"` **without** `aria-modal`, still named (A2), focus still goes into it on open (A1), Esc
   still closes it and returns focus to the opener (A4, A5), and the opener moves focus back into the open sheet.
   For a detail sheet, picking another one also moves focus into the sheet, and Esc returns it to the one last
   picked. Below 768px both kinds are modal (ApSheet does this). Any other sheet that lets Tab out fails A3.
4. **Esc closes** it without acting.
5. **Focus returns** to the control that opened it, after Cancel, Esc **and** after the action. If that control
   is gone (the row resolved), focus goes to the row's new state line or the list heading, never to `<body>`.
6. **Required-field errors** ("Give a reason first.") are announced: `aria-invalid` plus `aria-describedby` on the
   field, not colour alone. A required field that starts empty may instead keep its action disabled with the
   reason ("Give it a name.", A7). Then the field carries `aria-required="true"`, and it gets **no** `aria-invalid`:
   an untouched empty field isn't an error yet. Either pattern passes; a form uses one, not both.
7. A **disabled action's reason** is reachable by keyboard (focusable text, or `aria-describedby` on the button),
   not only on hover.

## B. Every screen
1. Tab order follows reading order: rail → top bar → page header actions → panels left→right, top→bottom.
2. Status is shape + colour + word. A ▲/◆ mark is `aria-hidden` and its word is read. Where there's no word (matrix
   cells, plot marks, out-of-range cells), there's an `aria-label`.
3. Disclosures (`Technical details`, `Show`, `Show all 98`, Timeline folds, dashboard sections) are buttons or
   `<summary>` with `aria-expanded`, toggled by Enter and Space.
   - A popover that lists **links that navigate** (the mission switcher) is a disclosure too: `aria-expanded` +
     `aria-controls`, no `aria-haspopup`, no menu roles; Tab moves through the links, Esc closes and returns focus
     to the button. `role="menu"` (kit `ApMenuButton`/`ApMenuItem`, arrow keys) is only for menus of **actions**,
     such as `⋯`. (lead's §6 call, 11-16)
4. Live updates (Now rows arriving or resolving, counts changing) never move focus. A new crit flash honours
   `prefers-reduced-motion`.
5. Charts are `role="img"` with a sentence that states the **result**, not the encoding ("Realization was 92%
   over 7 days, under the 95% target on 2 days.", not "Bars show realization per day"), and each plotted value is
   reachable without hover (a table, a list, or focusable marks with names). (#189, dashboards' R3 finding)
6. **An action's outcome is announced without moving focus.** A result, refusal or failure after the person acts
   (a refusal line, an error inside a sheet, a failed `Load more` / `Older`, a row's result note) is in a live region:
   `role="alert"` for refusals and failures, `role="status"` (polite) for results. That includes results with nothing
   to show: a search with no matches, a download started ("Export started: Power.csv"), a comparison finished. Focus
   stays where it was (B4). (#189 'live' and 'outcome')
   - **The role follows what happened, not the callout's tone** (#257 check; #276, dashboards' sweep). A caution-toned
     refusal of the person's own act is still `alert`, so a callout that derives its role from its tone must let the
     caller set it. For an outcome object, nominal is `status` and caution or crit is `alert`.
   - **A load is an outcome only when the person acted:** a failure after Load more, Older, a typed search, Retry or
     a filter change is `alert`; the page's first load failing on mount is `status`.
   - An act that ran and changed nothing is a result (`status`); a refused one is `alert`. A failed background save
     (autosave) is `alert`, once, when it appears.
   - Standing cautions (shown on render, not after an act) keep the kit default; no role prop is needed.
7. **Every control names what it acts on.** A button repeated per row, widget or section carries its object in its
   name ("Edit Battery voltage", "Remove section Power"); an untitled one uses its kind and position ("Edit untitled
   widget 3"), never a name ending in a space. A list row's buttons reuse the row's title: "Discard, EARENDIL-001,
   SNTG 00:13Z pass, 3 connections refused" (U107). `aria-keyshortcuts` lists every key it answers, modifiers
   included. (#189 'name')
8. **Screen-wide keys never override a focused control that uses that key.** Present's Space and ←/→ and Kiosk's
   Esc yield to the focused control only when it uses the key. Space presses a button, link or summary and ticks a
   box. The arrow keys move in a field, a radio group, tabs, a menu, a listbox, a grid, a tree or a slider. A focused
   button doesn't use the arrows, so ←/→ still step slides from it; Space on it presses it. Esc yields only to an
   open sheet or menu, which it closes; from a focused field it still leaves Kiosk or Present. (#189, Present; #245's
   `focusedControlOwns`)

## C. Surfaces to check by hand (opened, confirmed, closed)
| Screen | What to open or do | Specific checks |
| --- | --- | --- |
| Now | A U45–U57 row: `Mark as seen`, `Acknowledge`, `Retry…` / `Close without retry…` (U54), `Discard…` (U49) | A on each sheet; after acting, focus lands on the row's resolved line; rows arriving above don't steal focus; the row title link comes before its buttons |
| Contacts › selected pass | `Cancel contact…` / `End contact now…` (U55); `Release commands…` (U46); `Release` (booking); `Book a pass` | A, with focus on `Keep contact` / `Cancel`; the blocks (U45–U50, U57) read in order with each `Technical details` collapsed; refusal lines appear without moving focus |
| Book a pass sheet | Search → pick an offer → book | Offers are a list with names. Once U58 (b) ships (#361; not built yet: the server has no `listener_overlap` field), a `LISTENER OVERLAP` offer reads its sentence before the book button |
| Compose | Catalog listbox; `VERIFIERS DIFFER` block `Show` (U51); Per-target table | The catalog search is a combobox over a listbox, the same pattern as the palette (`aria-activedescendant`): ↑↓ move the active command, ↵ adds the active one (the first match until ↑↓ moves), and each option's name includes Hazardous and its argument count. "No commands match" is read from a region that stays mounted (B6). `Show` lists names and keeps focus on the list; the chip's tag is read |
| Approve | The own-values table (per-target values); `Show all 98` | An out-of-range cell is focusable, with ▲ and the reason in its name; the table has a caption naming the command |
| Uplink & verify | Per-point verifier plots (U51); a target row's `OWN VALUES` line | Each plot has a sentence and a caption naming its targets |
| Dashboards viewer | Kiosk (Esc out); Present (←/→, Space, Esc); a section's disclosure; `⋯` menu | Keys work with focus anywhere in the takeover; after Esc, focus returns to `⋯ › Kiosk`; collapsed sections say `3 WIDGETS` |
| Dashboards edit | `Add section` sheet; a heading's `Edit` and `⋯` (Move up/down/Remove section…); Remove's in-place callout; `Save…` | A; a disabled Move's reason ("It's already first.") is read; after Remove, focus goes to the next section's heading, else the previous one's, else `Add section`; widgets move by keyboard (the ⠿ handle: arrows move, Shift+arrows resize, each move announced; dashboards 8e14ea148) |
| Admin › data source bindings | `Switch…` (U53): type-to-confirm; `History` | A; the confirm input is labelled `Type default_flight_telemetry to confirm`; Switch's disabled reason is read; when counts change the line is announced (polite) and the typed name clears |
| Mission settings | Per-field `Override` / `Change` / `Reset to inherited`; a ratio field's hint and `Use 90%` | `Use 90%` follows the field in Tab order; Reset's outcome line is announced |
| Contact planning | Requirement page: `Plan 11-14`, the inline `book a pass` link; occurrence `Close…` / `Cancel…` | A; the inline link is distinguishable without colour (underline) |
| Timeline | A fold group; a row's link | Fold buttons have `aria-expanded` and the group's label ("Telemetry stored") |

## D. 390 only
1. The bottom tab bar is reachable and in order after the page content, and it doesn't cover the focused element
   (scroll into view).
2. Sheets are full-height (design-language §9: title and actions pinned, only the body scrolls), and focus doesn't
   land behind the on-screen keyboard. The Widget side sheet traps focus at this width.
