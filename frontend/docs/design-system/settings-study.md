# Organization and mission settings study

Open **Design Studies / Settings / Organization and mission** in Storybook:

- [Explore mission settings](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--explore)
- [Organization defaults](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--organization-defaults)
- [One operator](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--single-operator)
- [Mission override](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--mission-override)
- [Enforced requirement](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--enforced-requirement)
- [View only](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--view-only)
- [Application unavailable](http://127.0.0.1:6006/?path=/story/design-studies-settings-organization-and-mission--application-unavailable)

Run `corepack pnpm storybook` from `frontend` if needed. The study uses the
production shell, primary navigation, page chrome, tokens and controls. Settings
is a destination in the existing sidebar; section navigation stays in the page.
Mission settings stay within the current mission, identified in the page header,
without a mission switcher. **View organization setting** links to the inherited
default; organization settings retain links to the sample missions.

All edits, saves, people, navigation and activations are simulated in memory.
Reloading resets the fixture. The study does not change Phoenix routes, live
policy defaults, permissions, database records or runtime activation paths.

## Journeys

### One operator

Start with **One operator**. The mission inherits an organization default allowing
one authorized person to review and activate a saved revision. Follow **Explore
activation journey**, inspect the comparison, and **Activate configuration**.

This is a supported operational workflow. Independent approval is a customer
requirement. Validation, exact revision identity and activation history still apply.

### Defaults and overrides

In **Organization defaults**, select independent approval and inspect the proposed
journey and mission impact table. Until saved, it remains an organization draft.
After saving, Kestrel inherits the requirement. Choosing another value there
creates a mission override. **Use organization default** is an explicit edit that
can be saved or discarded.

Organization and mission drafts remain separate. Switching sections, missions,
or a primary navigation destination and returning preserves them. Saving the
Commanding section does not save unsaved Governance changes.

### Enforced requirements

Choose independent approval at organization scope and clear **Allow missions to
override this requirement**. After saving, missions display **Required by
organization**, the effective value, an explanation and a link to its source.
Commanding defaults remain independently editable when permitted.

Existing mission overrides are retained while enforcement takes precedence.
Releasing enforcement restores those explicit overrides. The organization impact
table previews this behavior before saving.

### Independent review

Open the activation journey with independent approval saved. Maya submits revision
5 and sees that another person must review it. Open **Study controls**, act as Eli,
inspect the same comparison, enter a rationale and approve or reject.

Changing governance while a review is pending marks the simulated request stale.
The user must explicitly review and proceed again. The study does not activate an
old request by relaxing a setting. production now enforces the same rule at decision and activation.

### Permissions and application recovery

**View only** represents read permission without edit permission, independently
of built-in roles. The explanation identifies the action and scope involved.

Commanding contributes its workspace defaults using the same metadata and core UI
as Governance. Search locates sections by title, description and owner.
**Application unavailable** keeps the shell and other settings usable; retry
restores the sample section. This is an availability simulation, not a real remote
release outage test.

## SDK and server contract

The additive `@cadence/plugin-sdk/settings` entry introduces versioned
`settings.section` discovery metadata: stable section identity, supported scopes,
title, description and host/application ownership. It validates and copies bounded
metadata. Arbitrary routes, renderers and permissions are not admitted by this decoder.

The production screens are available at `/settings/:section_id` and
`/missions/:mission_id/settings/:section_id`, defaulting to Governance.
**Host / Settings** in Storybook renders these same production components with a
simulated transport. The original design study remains an exploratory fixture.

The host discovers backend `SettingsSectionDefinition` contributions and loads
matching compiled SDK contributions. This follows
[ADR-024](../../../docs/decisions/024-host-composition-and-vertical-frontend-modules.md):
coordinated domain modules are the current delivery boundary. Independently
published federation releases do not yet admit settings renderers.

| Owner        | Responsibility                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------- |
| Host         | Scope, routes, navigation, admitted section ports, opaque draft retention, availability and history |
| Core UI      | Section/row layout, radio cards, source presentation and editor frame                               |
| Domain owner | Value decoder, editor, defaults, validation, saved/effective values and effects                     |
| Phoenix      | Authentication, authorization, exact revision writes and scoped updates                             |

Applications declare a backend settings provider and register their corresponding
frontend contribution through the module's public entry. Platform applications
are always applicable. Installed mission/spacecraft applications can contribute
organization defaults and settings for their containing mission. Disabled or
uninstalled optional applications are excluded. Duplicate identities and reserved
host identities are excluded from application admission.

Writes reauthenticate and recheck scope, page identity, section admission and
expected revision. Each section saves independently. Conflicting updates retain
edits; unconfirmed writes require refreshing saved values before retrying.
Unsaved drafts survive internal navigation and are cleared with the host session.

Governance supports one operator, independent approval, mission inheritance,
reset and organization enforcement. Named policy actions initially allow active
human organization members; Cedar remains a future integration. The old global
flag supplies an initial default only until organization settings are saved.
See [ADR-004](../../../docs/decisions/004-activation-authorization-and-approval-policy.md).

Commanding owns its workspace shelf opening state. This is the stage/execution
shelf. A selected stage or execution opens the shelf even when the default is
minimized; subsequent server updates preserve the operator's current layout.

## Core UI ownership

| Pattern                                                                  | Decision                                                                                               |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `CadenceSettingsSection`                                                 | Added to core UI: labeled section, heading/description, status and footer slots.                       |
| `CadenceSettingRow`                                                      | Added to core UI: responsive label/control columns, source/detail slots and accessible group labeling. |
| `CadenceRadioCard`, `CadenceSettingSource`, `CadenceSettingsEditorFrame` | Shared controls and presentation for both settings owners. Domain policy stays outside core UI.        |
| Existing controls and table frames                                       | Reused. Native radios use a fieldset and legend.                                                       |
| Settings sidebar destination                                             | Host-owned navigation footer, present in organization and mission navigation.                          |
| Source, inheritance, enforcement, reset                                  | Settings-domain behavior. Shared UI does not evaluate policy.                                          |
| Save coordination and application availability                           | Feature-owned. No global save event or cross-application transaction.                                  |
| Configuration comparison and review                                      | Domain composition using shared controls.                                                              |

## Validation

Browser stories cover inheritance, overrides, reset/discard, enforcement, scoped
drafts, navigation continuity, direct activation, independent review, policy
changes during review, permissions and application recovery. Accessibility runs
with the stories. A core UI story exercises keyboard and disabled control behavior.
SDK tests cover scope/version bounds, ownership and immutable discovery metadata.

Frontend checks, workspace tests, Storybook build and desktop/narrow browser
inspection validate the study. They do not establish production persistence,
Cedar integration, federation admission or runtime activation behavior.

The production integration has separate domain and Phoenix transport tests for
scoped persistence, concurrency, policy changes and authorization. The
[Settings browser journey](../../../apps/cadence_web/browser_test/cadence_web/assets/settings_browser_test.exs)
uses the real Phoenix application to save settings, activate directly, require a
teammate's approval and observe that approval without refreshing. It also checks
the applied runtime generation and the narrow layout. The commanding browser
journey opens its workspace with a persisted mission shelf preference.
