# Design-system architecture

Cadence preserves its production appearance while giving visual decisions one shared owner.
The high-contrast federation experiment was a diagnostic fixture, not a product theme.
DaisyUI is removed. Tailwind generates layout utilities; Cadence owns component styling;
Reka supplies interaction primitives behind Cadence's APIs.

## Packages and dependency direction

- `@cadence/design-tokens`: framework-neutral production palette, semantic colors, typography,
  spacing, shape, elevation, motion, stacking, and presentation effects. `theme.css` has no reset;
  `base.css` adds shared document defaults and reduced-motion treatment.
- `@cadence/ui`: production Vue controls, presentation/layout components, and the CSS recipes used
  by both Vue and Phoenix HEEx. It depends on tokens and Reka, with Vue as a peer dependency.
- `@cadence/plugin-sdk`: application/host contracts. It does not own appearance.
- `apps/storybook`: executable documentation for the real packages and representative production
  screens. Stories never provide an alternative production component implementation.
- Application packages: domain state, workflows, data adapters, and domain compositions.
  Applications import shared components directly; there are no local `src/ui` copies.

Phoenix remains responsible for routing, authentication, authorization, validation, and durable
state. These frontend boundaries do not change those responsibilities.

## Stylesheet ownership

The document host imports `@cadence/ui/styles.css` exactly once. Phoenix's `assets/css/app.css`
imports that source and adds its LiveView directives, template sources, and the dashboard module's
public `workspace.css` entry.
Standalone apps and Storybook use the same entry through the pinned Tailwind Vite compiler.
Each build declares its own source directories explicitly. Phoenix includes first-party remote
sources so server-authored and remote-authored utility classes both exist in its stylesheet.

Federated module entrypoints must not import a global reset or theme. They inherit document tokens
and the shared CSS contract. Their scoped component styles travel with their release.
`@cadence/dashboards-and-exploration/workspace.css` loads the installed GridStack and uPlot
styles before Cadence's `dashboard.css` overrides; its focused `charts.css` entry omits GridStack.
Components import these module-owned styles too, so standalone and federated bundles include
their required library CSS without importing a document reset or theme.

GridStack and uPlot are pinned package dependencies of the dashboard module, not vendored
source or federation-shared singletons. Consumers import Cadence components and stylesheet
entries, not re-exported library implementations. Dependency upgrades are separate from
ownership changes.

The CSS classes `btn`, `input`, `select`, `textarea`, `card`, `table`, and related variants are now
Cadence-owned recipes in `packages/ui/src/styles/controls.css`. They are also the styling API for
native Phoenix controls, which must continue to participate in LiveView forms. They do not require
DaisyUI. New Vue code should use Cadence components where the component's behavior fits.

## Tokens and customization

Change values in `packages/design-tokens/src/theme.css`. Components consume semantic roles rather
than maintaining palettes. Component styling belongs in `packages/ui`; application utilities are
for layout and composition. Avoid selectors that reach inside another component's DOM.

Canvas chart colors and typography live in `packages/design-tokens/src/charts.css`.
Charts resolve these CSS roles and redraw when the document theme changes. Heroicons are
vendored with their license in the UI package, so standalone builds do not need Phoenix dependencies.
Use `tools/import-heroicons.mjs` to regenerate that asset set from an upstream optimized checkout.

Control variants describe intent: `primary`, `secondary`, `quiet`, `danger`, and `outline`.
Controls own their default styles, disabled/busy states, and accessibility relationships.
Presentation frames provide slots for caller-owned elements and preserve native forms, events,
IDs, and reconciliation. Custom layout classes are explicit composition points, not a second theme.

`data-theme="dark"` is the current production theme. `data-skin="legible"` reduces decoration using
the same tokens. The former experimental light/monochrome themes are not supported product themes.
A new theme should implement the same semantic roles and pass the same story/interaction suite.
Do not infer status meaning from hue: freshness, health, availability, workflow, and uncertainty
remain distinct concepts governed by the charter and operational state model.

## Evolution and release policy

This is a greenfield repository: update all first-party consumers together and delete obsolete
implementations rather than introducing migration shims. UI is a build-time dependency, not a
federated singleton. Vue runtime sharing remains the host's responsibility.

The existing `cadenceThemeContract: 1` identifies the first-party host styling contract. Deploy this
consolidation with rebuilt first-party releases. Future independently deployed releases need an
explicit compatibility decision before removing or changing the meaning of public tokens/classes;
additive changes can keep the contract, breaking changes require a new admitted contract.

## Working and validating

From `frontend`:

```sh
corepack pnpm storybook
corepack pnpm storybook:test
corepack pnpm storybook:build
corepack pnpm check
corepack pnpm test
corepack pnpm build
```

Storybook runs at `http://127.0.0.1:6006`. Component stories live with the shared component.
Application examples import production screens with deterministic props and mocked actions.
Chrome-backed stories check accessibility and interactions, including theme propagation, forms,
loading/disabled states, and overlay focus. Enable `VITE_DESIGN_SYSTEM_SCREENSHOTS=true` during
`storybook:test` to retain review screenshots under the Storybook build output.

Run Phoenix asset validation and `mix precommit` from the repository root before completion.
The ownership tests reject local UI copies, experimental token imports, DaisyUI, and theme/reset
imports from federated entrypoints. New public components should include representative states and
meaningful interaction tests; shared changes should also be checked on real application stories.
