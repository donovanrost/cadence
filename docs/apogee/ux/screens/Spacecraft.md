# Spacecraft: the directory and a spacecraft's page (Setup) — not on the canvas

Routes: directory `M/setup/spacecraft` · a spacecraft `M/setup/spacecraft/:spacecraftId` · its app pages
`M/setup/spacecraft/:spacecraftId/apps/:appKey/:surface?` (AppSurfaces.md, U103). Adding spacecraft is its own flow
(AddSpacecraft.md). Owner: fe-setup; words: mms-ux. Written from the console as built (the Setup gap audit, #305),
so the spec matches what ships; items marked **gap** are console work on the board.

## A · Directory (`M/setup/spacecraft`)
Header: lbl `EARENDIL · SETUP`, h1 `Spacecraft`, subline "550 spacecraft · 2 profiles" (parts dropped when
unknown). Primary `Add spacecraft` (organization admins only).
- **A1 Directory** (ApTable), with a filter box ("Name, SCID or profile") in the panel header. Columns:
  - Name (link to the spacecraft's page)
  - SCID and NORAD (mono; a missing NORAD reads `not set`)
  - Profile (name + `v4`; no profile: "No profile", caution)
  - Plane · slot
  - Routing rules (count; none: `none`, caution)
  - Setup (`Ready` with a nominal mark, or the caution tag `Incomplete`)
  - Last heard (time; never heard: off mark + "Awaiting first AOS"; history down: "Not known right now")
- A missing profile name reads "Deleted profile" today. U25 allows "Deleted …" only where the server says so, so
  that waits on api confirming that null means deleted (**gap**, audit S2).
- **Empty:** "No spacecraft yet" + "Add one spacecraft or a whole launch batch from a profile or a manifest." with
  `Add spacecraft`. Without the right: "An organization admin adds spacecraft to this mission." and no button.
- **No match:** "No spacecraft match" + "Nothing matches “<query>”. Filter by name, SCID or profile."
- **Telemetry history down** (caution, above the table): "Last received may be incomplete: the telemetry history
  isn't answering, so only what arrived since the last restart shows."

## B · A spacecraft's page (`…/:spacecraftId`)
Header: the spacecraft's name (U25: "Unknown spacecraft" when null), with the tag `Ready` (nominal) or `Incomplete`
(caution). Panels:
- **D1 Readiness:** the spacecraft's findings, as Setup.md's rows.
- **D2 Identity:** name, SCID, NORAD, plane and slot. Edited through `Edit` (organization admins), which stages.
- **D3 Profile & version:** the profile and its version; none: "No profile".
- **D4 Routing:** the rules that cover it (columns incl. Enabled / Disabled) and its extra routes (U79). None:
  "No routing rule" + "It can't be contacted until a routing rule covers it."
  - Removing a route: sheet `Remove <route>?`, "…Booked and running contacts keep the routes they were booked
    with."
  - An extra route that's gone: "This extra route can't be opened for editing. It may have been removed."
- **D5 Operation:** the Commanding and Telemetry switches (U40), each with who last set it (U101). Switches are
  staged **here** (ux, audit S1); turning one off opens U40's consequence sheet, and a staged switch shows `STAGED ·
  APPLIES WITH r7`. Today it's staged through `Edit`, with no sheet and no staged tag (**gap**, #309).
- **S9 Apps:** the spacecraft-scope apps (U103).
- **Archive** (U40): `Archive <name>?` sheet and its holds.
- Last heard, when the history is down: "Not known right now (history unavailable)".
- A `Readiness` link in the header (legacy parity, U103) is a **gap**.
