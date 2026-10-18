# Commanding workspace

The reference interaction is operating on a selection of spacecraft: select,
prepare, stage, inspect, and follow the result while the surrounding workspace
stays visible. Dense visual selection and progressive disclosure are central to
the experience.

## Try it

Run the existing Storybook command from the frontend directory:

    corepack pnpm storybook

Open **Operations / Commanding / Workspace** for the production components with
deterministic fixtures, including a staged shelf and missing-model state. Open
**Patterns / Workspace / Resizable Workbench** for the reusable layout.

The original **Design Studies / Commanding / Workspace** remains a visual
reference. Explore starts with no
selection. Prepare, Staged, and Incompatible Targets provide populated states.
All data and execution are local simulation fixtures. The study is development
code in Storybook, not a replacement for the production commanding module.

1. Select several spacecraft in the fleet pane. Search preserves selections
   outside the filtered view; Select visible adds only visible spacecraft.
2. Choose a command. The catalog shows definition compatibility across the
   selection, and preparation opens beside it.
3. Choose shared settings. Expand per-spacecraft settings when differences
   matter. Reducing the selection to one spacecraft shows its effective value,
   including an existing override.
4. Stage the command. A resizable shelf opens with one row per endpoint, so
   targets and settings remain inspectable. Changing preparation settings
   leaves staged copies intact. Rows can be reordered or removed.
5. Review the specific rows before moving them into the simulated queue.
   Advance simulation demonstrates acknowledgement and verification as distinct
   states. Commands without a contact keep waiting; hazardous commands keep
   awaiting approval.

## Spatial behavior

The fleet, catalog, and preparation share a horizontal splitter. Preparation is
conditionally mounted with a stable panel identity and explicit order. A nested
vertical splitter separates preparation from the command shelf. Users can
resize with the pointer or focus a handle and use arrow keys. Layout sizes are
stored under study-specific keys; narrow layouts have a separate width key.

The command shelf minimizes into a compact bar at the bottom of the workspace,
showing the current stage and its item count. Expanding restores its
height and unfinished edits. `CadenceWorkspaceLayout` owns this behavior and
focus transfer; the dock content stays mounted while minimized. The production
workspace has no permanent instruction strip; action feedback appears only when
needed.

The shelf follows the pointer continuously down to the bottom edge. Crossing
11% of the vertical splitter arms minimizing and tints the existing header red
through CSS; this threshold does not constrain the shelf's height. Releasing
minimizes the shelf and focuses its
expand button. Dragging back above the threshold clears the tint;
Escape or an interrupted gesture restores the previous height. Expanding after a
snap restores the height from before the gesture and retains unfinished edits.
The tint lasts only while holding the drag past the threshold; the minimized bar
and re-expanded shelf keep their normal appearance.
The shared workbench's **Drag to Minimize** story exercises this interaction.

CadenceSplitterGroup, CadenceSplitterPanel, and CadenceSplitterResizeHandle
wrap the installed Reka primitives. Cadence owns handle styling, accessible
labels, and the consumer API. Reka owns resize mechanics. The components do not
own command selection, workflow state, or authorization.

The disclosure rules follow context:

| Context                                  | What becomes available                                   |
| ---------------------------------------- | -------------------------------------------------------- |
| No spacecraft selected                   | Visual fleet and catalog browsing context                |
| One or more selected                     | Per-command compatibility counts and preparation         |
| A command selected                       | Command-specific settings, target chips, expected effect |
| Multiple targets or an existing override | Per-spacecraft value controls                            |
| Incompatible target selected             | Specific incompatibility and blocked staging             |
| A command staged                         | Stage shelf and review action                            |
| Review entered                           | Confirmation tied to the current staged rows             |
| Queued in simulation                     | Execution rows and simulation advancement                |

Selection, health, contact availability, and definition compatibility have
separate presentations. A nominal health symbol never grants release authority.
Hiding the preparation pane or changing the selection preserves per-command
settings. Staging more commands or changing staged rows invalidates review.

## Production integration

The Commands item in the authenticated Ops rail opens
`/missions/:mission_id/ops/commands/workspace`. The route stays in the existing
`/` scope, `[:browser, :require_authenticated_scope]` pipelines and `:application`
LiveView session with the `:ops` host policy. Mission managers can prepare
commands; members receive the existing execution monitor. Each read and action
reauthorizes the current scope.

Select explicit spacecraft endpoints, inspect a command, supply shared values
or per-endpoint overrides, and preview up to 25 endpoints together. Search and
pane disclosure preserve incomplete argument text. A named private or shared
stage is chosen or created in place. Search includes spacecraft display names;
no spacecraft selection invents an implicit command endpoint.

Phoenix previews every selected endpoint against the current model and saves
all the previewed drafts in one transaction. Stage submission reuses the
existing exact reviewed request creation flow. Approval, queue, release and
verification remain distinct. An unconfirmed write consumes its attempt token;
refresh inspects server evidence without repeating the action. Draft edits and
selection changes invalidate previews. Exact integer values, numeric-looking
strings and microsecond timing survive the UI boundary.

The stage picker lives in the shelf heading. The shelf shows persisted drafts
and their review workflow. Execution status lives in the Ops context panel and
the command monitor; the shelf has no execution mode. Command building has no
permanent refresh toolbar. Full stage settings, history, request review and
execution monitoring retain the existing routes. Production shows only available
spacecraft identity and endpoint information; the study's simulated health,
contact windows and dispatch controls remain in the design study.

### Live reads

Committed stage, request, queue, release and verifier changes publish a scoped
invalidation through Phoenix PubSub. The active workspace LiveView coalesces
notifications for 250 ms and wakes the captured host read port. Notifications
carry organization/mission scope internally and page identity at the transport
boundary; they never include private stage contents. Every resulting read goes
through the existing authorization and DTO validation.

The host owns event delivery and captured page lifetime. `query: "live"` opts a
contribution into an invalidation subscription alongside its independent read
port. Commanding owns coalescing reads with local actions, discarding a read
overtaken by an action, and reconciling the result with local edits. Argument
text, selected endpoints, unfinished order edits and unchanged confirmed reviews
survive background updates. Changed selected draft, target, model or stage
evidence invalidates the affected preview. The existing write transaction still
checks all evidence at submission.

Nested stores leave notification to the outer mutation transaction. Preview
transactions do not publish changes. A 30-second server reconciliation covers
missed notices and shared catalog/access changes; the existing host reconnect
flow reauthorizes and the mounted workspace reads again after subscribing.
Subscription and timer cleanup bind updates to the current page token. A
connection/read failure exposes recovery, and an uncertain write retains
**Check result** without replaying the write.

## Component ownership

| Core UI component                                                             | Responsibility                                                                                           |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `CadenceSplitterGroup`, `CadenceSplitterPanel`, `CadenceSplitterResizeHandle` | Reka adapters, accessible resize handles and persisted geometry                                          |
| `CadenceWorkspaceLayout`                                                      | Primary browser, secondary browser, optional inspector and dock; narrow-layout stacking                  |
| `CadencePane`                                                                 | Consistent pane heading, count, actions, toolbar, scroll area and footer                                 |
| `CadenceSelectionTile`                                                        | Visual selectable object with native pressed-button semantics                                            |
| `CadencePopover`                                                              | Existing dismissal and focus behavior, now with a close callback for contextual choices                  |
| `CadencePageHeading`                                                          | Existing host-owned page heading; shared page styles bound the resizable body through transport wrappers |

Spacecraft schematics, command catalogs, target compatibility, argument editors,
selection state, stage rules and execution receipts belong to the commanding
module. The generic components accept content and controlled state; they do not
fetch mission data or hold command authority. The study and production workspace
both use the shared layout and selection tile.

## Verification

### Laptop density

The production workspace stories include the real Ops frame and host heading.
`Operations/Commanding/Workspace` has Compact Laptop (1280 × 720), Laptop
(1440 × 800), Short Desktop Window (1600 × 700), and Large Desktop (1920 × 1080)
examples. These are browser viewport sizes, independent of physical screen pixels.

Core UI owns the responsive recipe in `styles/workspace.css`. Desktop workspaces
use compact density at widths up to 1440px **or** heights up to 800px. At 900px
and below, the existing stacked layout retains its roomier controls. Density
changes through CSS; it does not remount panes or reset a saved split.

Compact page headings use 20px text, preparation headings and input values use
13px, and argument labels use 12px. Existing supporting text remains unchanged.
The breadcrumb trail sits beside the title in compact desktop headers; narrow
layouts keep the path above the title. Page actions retain their own space.
Shared panes, controls, selection tiles, and minimized docks consume the same
workspace spacing roles. Selection tiles opt into `layout="responsive"` to place
their visual beside the details on compact desktops; other tiles keep their
vertical composition. Spacecraft graphics remain domain-owned.
The command browser omits repeated instructions from each row while retaining
the selected command's argument count and significance.

Viewport stories exercise multi-spacecraft selection, editable arguments, preview
visibility with the shelf open, and draft/focus preservation when minimizing.
Larger forms still scroll within their pane; the shelf can be minimized when
more preparation space is needed.

### Workflow checks

Mounted feature tests cover exact values, preserved edits and overrides,
invalidated previews, consumed writes, receipt recovery and navigation lifetime.
Storybook interaction and accessibility checks cover progressive disclosure,
keyboard resizing, stage popover dismissal and focus return. Native Phoenix
producer tests round-trip the actual Vue controls through multi-endpoint save
and exact formal request creation, including scope and model changes. The
production browser journey covers the deployed bundle and actual LiveView
transport; `mix precommit` and `corepack pnpm verify` remain required gates.
