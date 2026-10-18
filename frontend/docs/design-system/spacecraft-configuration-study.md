# Spacecraft configuration study

This Storybook study explores spacecraft setup as a connected workspace. The
spacecraft stays in context while the user chooses definitions, configures their
consumers, connects communications, and reviews a specific change. It tests the
confirmed requirement that spacecraft in one mission can use different catalog
revisions simultaneously.

The default study runs inside the production `ApplicationShell` and `HostPage`.
Cadence's primary navigation and page chrome stay in place; the visual fleet
selector opens from **Switch spacecraft** in the heading. The original isolated
composition remains in **Isolated Reference** for comparison.

Open **Design Studies / Spacecraft / Configuration** in Storybook:

- [Explore](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--explore)
- [First spacecraft](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--first-spacecraft)
- [Upgrade catalog](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--upgrade-catalog)
- [Review changes](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--review-changes)
- [Missing packet input](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--missing-packet-input)
- [Fleet switcher](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--fleet-switcher)
- [Isolated reference](http://127.0.0.1:6006/?path=/story/design-studies-spacecraft-configuration--isolated-reference)

Run `corepack pnpm storybook` from `frontend` if Storybook is not already running.

## Journeys

### First setup: definitions to an active configuration

Start with **First spacecraft**, or use **Switch spacecraft** to select KESTREL-03. This is
an existing spacecraft with no active configuration; mission transports and
imported catalogs already exist in the sample mission.

1. Choose **Catalog & applications**, then **Choose catalog**. Compare the two
   imported revisions and use one in the spacecraft's draft. The catalog
   reference opens in a separate tab, preserving setup context.
2. Open **Telemetry Decom**, enable it, and connect **OBC downlink · VC 0**.
   A payload stream stays visible with a specific incompatibility explanation.
3. Open **Commanding** and enable it. Its definitions come from the OBC binding.
4. In **Communications**, choose framing directly or copy the optional Kestrel
   bus preset. Connect the S-band delivery path separately.
5. **Save draft**. Saving is useful even when setup is incomplete. The saved
   draft does not change active applications or command discovery.
6. In **Changes**, resolve any remaining setup gaps, inspect the comparison,
   and **Submit for review**. Use **Simulate approval**, then **Activate
   configuration** to explore the proposed lifecycle.
7. **Open in Ops** previews the commands supplied by the active catalog for
   this spacecraft. The study ends at discovery; command preparation and
   execution have their own study.

Overview reveals the next relevant actions as configuration progresses. The
sections remain navigable throughout; this is not a mandatory linear wizard.

### Upgrade one spacecraft in a mixed fleet

KESTREL-01 starts on r3.4, while KESTREL-02 starts on r3.3. Open each in Ops:
r3.4 includes the sample `CAPTURE_IMAGE` command; r3.3 does not.

On KESTREL-02, **Browse revisions** or **Change revision** opens a contextual
inspector. It shows the active binding, software compatibility label, definition
counts, and additions in r3.4. Choosing r3.4 edits only this spacecraft's draft.

The comparison identifies the changed catalog and the Telemetry Decom and
Commanding consumers. Command discovery continues to use r3.3 until the reviewed
configuration is activated. KESTREL-01 retains its own binding throughout.

### Repair an incomplete application

**Missing packet input** starts with a saved r3.4 draft whose Telemetry Decom
input is disconnected. Review is blocked with an explicit repair action.
**Connect input** goes directly to the application's inspector. After choosing
VC 0 and saving, the draft is ready for review; the active r3.3 configuration
continues to serve Ops in the meantime.

### Leave and resume work

Unsaved and saved drafts are owned by each spacecraft. Switching sections,
closing an inspector, or selecting another spacecraft preserves them. The fleet
switcher marks spacecraft with changes. **Discard unsaved** restores that
spacecraft's last saved draft. Reloading Storybook resets the entire simulation.

Edits invalidate a submitted or approved review. Restoring the saved values
still requires a new review. The simulated activation consumes the exact
approved snapshot, rather than whatever happens to be in the editor.

### Navigate through Cadence and return

Change KESTREL-02's catalog to r3.4 and leave the draft unsaved. Choose **Catalog**
in the primary sidebar, or **Mission catalog** from Catalog & applications. The
mission catalog shows r3.3 active and r3.4 in draft for that spacecraft. Follow
its spacecraft link or **Return to KESTREL-02** to resume setup. Selection,
section and edits survive; the primary navigation and its collapsed state stay
mounted across the destination change.

The study intercepts ordinary sample-route clicks locally. It does not install a
second browser router or alter Storybook's history. Other shell destinations
show an explicit study boundary with a return path. Session forms are prevented
from submitting. Actual routing, Back/Forward, session transitions and server
authorization remain production-host responsibilities.

## Navigation ownership

Federation gives a feature control over its work area: selection, browsers,
inspectors, splitters and task-specific controls. The host owns Cadence identity,
organization/mission context, primary destinations, account access, route
history and page chrome. A feature's useful local navigation must fit within
that surrounding structure.

The spacecraft workspace therefore uses three distinct levels:

1. The existing primary sidebar selects a mission area such as Spacecraft,
   Catalog or Comms. It stays available while spacecraft or application context
   changes. Its existing mobile drawer remains the primary navigation on small
   screens.
2. The contextual spacecraft switcher selects the resource being configured.
   It preserves the original fleet visual treatment, active revisions and draft
   indicators without consuming a permanent sidebar column.
3. Local sections and inspectors organize the current spacecraft's task.

The study renders the actual host shell and page-heading provider. It does not
reimplement their navigation appearance in Storybook. The spacecraft-specific
switcher and sample catalog usage composition remain local design work. A
generic resource-switcher API should follow demonstrated use across resources.
The existing Ops shell is also host-selected; its broader navigation design is
outside this spacecraft iteration.

## Interaction and information hierarchy

- The fleet switcher shows active revision and configuration state independently
  of selection. Escape closes it and restores focus to its trigger.
- The shared page heading carries identity and the Ops handoff. Local section
  navigation keeps catalog, application, communications, and change context
  together.
- Overview's connection diagram gives active definitions and their consumers
  a spatial relationship. Draft catalog differences are labeled separately.
- The catalog and application browser uses compact rows. Detailed revision
  selection and application inputs appear only when requested.
- On smaller screens the inspector occupies the content area. Escape or Done
  closes it; focus returns to the originating control when it is still present.
- Save controls appear when there are unsaved edits. Review and activation
  belong to the Changes section. A simulation control for the reviewer is
  explicitly separated from the proposed product actions.
- Configured delivery and active configuration are not contact availability,
  spacecraft health, or command release permission.

## Profile exploration

The study does not make a reusable profile a prerequisite for discovering an
application or choosing a catalog. Communications offers an optional protocol
preset as a starting point. Copying it sets framing values on the selected
spacecraft; route selection remains explicit and later edits are independent.

This deliberately tests an alternative to the current profile workflow. It is
not a production rename or a decision to remove versioned configuration reuse.
Whether users need linked presets, fleet-wide updates, or a dedicated preset
library should be evaluated with the reuse journey before implementation.

The fixtures model one **onboard computer** catalog binding per spacecraft.
They do not settle whether independently versioned instruments require additional
bindings. Catalog import, spacecraft creation/identity editing, transport
creation, concurrent operators, authorization, and full command execution are
outside this study's simulation.

## Core UI ownership

| Component or pattern                      | Study decision                                                                                                                                                 |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CadenceLink`                             | Added to core UI. Owns native anchor presentation and focus; normal link attributes and modified-click behavior remain native. Used for the catalog reference. |
| `CadenceButton`                           | Reused for configuration actions, saving, review and the local Ops simulation. Production navigation must use actual destinations and anchor semantics.        |
| `CadencePageHeading`                      | Publishes identity, metadata and actions into the actual host page chrome, including in the default stories.                                                   |
| `CadencePopover`                          | Reused for the contextual spacecraft switcher, dismissal, positioning and focus restoration.                                                                   |
| `CadenceTableFrame`                       | Reused for mission catalog usage, keeping generic table presentation in core UI.                                                                               |
| `ApplicationShell`, `HostPage`            | Reused from the host for primary navigation, account controls, breadcrumbs and page regions. These remain host compositions.                                   |
| `CadenceCheckbox`                         | Reused for application enablement, with controlled state and accessible labels.                                                                                |
| `CadenceStatusSymbol`                     | Reused with text labels for configuration states. Domain meaning stays in the study.                                                                           |
| Resource section navigation               | Candidate for a shared pattern after reviewing this study alongside other resource pages. Routing and selection remain host-owned.                             |
| Inspector and compact section composition | Evaluate against `CadencePane` during integration. This study's geometry and content remain local while the layout is under review.                            |
| Configuration comparison and setup issues | Domain compositions. Reuse table/notice primitives during integration; keep activation rules, impact and repair destinations out of core UI.                   |

The study uses production tokens. Its application layout, schematic, catalog
selector, sample data and workflow state live in Storybook, separate from
production modules. It adds no server routes or mission writes.

## Validation

Storybook interaction tests cover first setup through simulated activation,
independent revisions and active command discovery, repairing a missing input,
invalidating an approval after an edit, preserving spacecraft drafts, catalog
search, and keyboard focus on inspector and switcher dismissal. Navigation
continuity coverage visits the mission catalog and returns to an unsaved draft
while checking the same shell navigation stays mounted and preserves its collapsed state. Shared link stories exercise
native anchor semantics and focus. Storybook's accessibility checks run with
these stories.

Frontend checking, the workspace test suite, the Storybook build, and browser
inspection at desktop and narrow widths validate the study. These checks do not
establish the required production changes to per-spacecraft model resolution,
application admission, persistence, review authority or runtime activation.
