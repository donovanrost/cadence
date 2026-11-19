# Review: the spacecraft configuration workspace, read side (#285), from screens

ux, 11-19. Source: fe-ops' #348 Playwright spec, run by qa against :4011 at 10:03Z (report in ui-apogee-spa
`var/qa-e2e-348-1119/`), at 1440 and 390. Checked against U25, U40, U94, U98, U101, design-language §4/§8 and
the a11y checklist. Ranked: wrong meaning first, then words, then layout. Owner: fe-ops; designer: mms-ux.

## What's right
- Header, `DRAFT SAVED` (caution, mark + word) and "v3 active · v4 saved" read as U94 has them.
- The switch lines are U94's exactly: "On · set by r7.", "On · set through Setup › Changes.", and the never-set
  line naming EARENDIL-001 and its Operation panel, each with `Open Operation`.
- "1 change from v3 · Review" and the Changes tab (Setting / Active / Draft) match U94's comparison.
- 390: Setup's read-only notice, the panels stack, nothing is clipped except the tab row (4 below).

## Findings
1. **Can't view (U98) is drawn as a label, with the wrong mark.** The sentence is in the uppercase, letter-spaced
   `lbl` style with the dashed-square mark. U98 says it's the page's empty state: a sentence in body type
   (sans, `text-3`), `role="status"`. The dashed square means "not set up" (U3), which is not what happened. Use
   the empty-state pattern (ApEmpty) with no mark, or the neutral one.
2. **Can't view: the breadcrumb reads "Spacecraft / Spacecraft / Configuration".** The middle crumb has no name to
   show, and a generic noun in its place reads as a second link to the directory. U25: "Unknown spacecraft".
3. **Framing line.** "TM ↓ / TC ↑ · 1,115 B frames · headers 0/0/4 B":
   - no arrows (the audit's P7 ruling: "TM / TC");
   - "headers 0/0/4 B" gives three numbers with no names. Name them as U94's labels do: "secondary header 0 B ·
     insert zone 0 B · OCF 4 B".
4. **390: the tab row is cut off** ("COMMU…") with no cue that it scrolls. Either wrap the tabs to two rows or give
   the row a visible overflow cue, and keep the selected tab in view.
## Not findings (pending, or already ruled)
- The floating "Sign in" pill is Tidewave, a dev-only Phoenix tool (`:dev` dependency), not in a release build
  (fe-ops). Not the console's; qa may hide it for spec runs if it covers what a screen needs.
- `r7` isn't a link yet: that's U101 (#151), still to build.
- The page header has the name only. Spacecraft.md puts name + SCID on the spacecraft's page; for the
  configuration page that's optional, since the breadcrumb carries the spacecraft.
- U94's L10 "What changes" said `Decoded APIDs` while the workspace and U40 say `Handled APIDs`; the docs now say
  `Handled APIDs` in both (this PR), so the console's label is right.
