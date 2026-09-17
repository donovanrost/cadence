# Spacecraft configuration

The production spacecraft workspace implements the
[approved navigation study](spacecraft-configuration-study.md) on the existing
authenticated `/missions/:mission_id/spacecraft/:spacecraft_id` route.

The host owns primary navigation, mission context, breadcrumbs, account controls,
and the page heading. A contextual fleet switcher changes spacecraft inside that
shell. Overview, Catalog & applications, Communications, and Changes are native
links with a `section` query parameter, so they support history and deep links.

## Setup journey

1. Choose an imported catalog revision for the spacecraft's onboard computer.
2. Enable Telemetry Decom and choose a packet source and APIDs. Saving can create
   a managed spacecraft source; ingress routing remains in Comms.
3. Enable Commanding to make this spacecraft's catalog definitions available in
   Ops after activation.
4. Configure framing directly, or copy an optional protocol preset. A preset is
   not required to discover applications or bind a catalog.
5. Save an immutable configuration revision. Changes compares it with the active
   configuration and identifies any missing setup inputs.
6. Activate the saved configuration. When organization or mission Settings requires
   independent approval, submit it for another person to approve in Changes.

Parsing and compilation happen during catalog import. Spacecraft setup selects
those existing artifacts; it does not require separate model approval or replay
qualification. Activation checks their exact stored identities and runtime
readiness. Catalog revisions display their saved and active spacecraft bindings
with links back to each spacecraft's Changes page.

## State and authority

The host retains up to 100 spacecraft drafts for the current mounted session.
Section changes, fleet switching, Catalog visits, and server updates preserve
local edits. Reloading or closing the page invokes the browser's unsaved-change
prompt. Competing saved changes require an explicit comparison: use the latest
saved revision or retain local edits against that revision before saving again.

Saving does not activate configuration. Review evidence pins the saved revision,
desired application inputs, and current fleet generation. A later save or a
competing activation invalidates that review. Activating one spacecraft retains
the other spacecraft's active configurations, including when they have newer
saved drafts. Legacy mission-wide apply actions cannot replace these bindings.
Identity edits preserve reviewed framing and link back to Communications for
changes. Generated protocol records are private to that spacecraft; they do not
appear as reusable presets. Identity saves and activation serialize against the
current spacecraft so concurrent changes cannot overwrite the reviewed pin.

Runtime partitions and command validation resolve the catalog bound to their
spacecraft's source endpoint. Shared command preparation requires matching wire
definitions, argument semantics, operational policies, constraints, and verifiers;
each target retains its own model evidence. Configured commanding does not imply
delivery readiness, contact availability, or permission to release a command.

This iteration models one onboard computer binding per spacecraft. Telemetry and
commanding consume that binding. Independently versioned payload computers require
an explicit future model extension.

## Core UI boundary

`CadenceResourceNavigation` now owns reusable resource-section presentation, with
native anchors and routing supplied by the caller. The workspace reuses
`CadencePageHeading`, `CadenceLink`, `CadenceButton`, `CadencePopover`, `CadencePane`,
`CadenceCheckbox`, `CadenceStatusSymbol`, and `CadenceTableFrame`.

The fleet switcher, configuration diagram, catalog picker, change comparison, and
setup guidance remain spacecraft compositions. They use core tokens and keep
spacecraft state, permissions, review evidence, and repair destinations outside
the core UI library. Storybook retains the original simulation for design study;
production uses the authorized Phoenix read and write ports.
