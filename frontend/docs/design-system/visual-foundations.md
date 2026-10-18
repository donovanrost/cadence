# Production visual foundations

The current Cadence application is the visual reference. The deliberately contrasting federation
experiment was used to detect mixed styles and is retired; it is not a candidate product theme.

The canonical foundations are `packages/design-tokens/src/theme.css`: production surfaces,
semantic color roles, system and monospace typography, spacing, control shape, elevation, motion,
stacking, and decoration. Core component recipes live in `packages/ui/src/styles`.

Storybook's **Foundations / Production Tokens** renders these definitions alongside actual
controls. Its **Reduced decoration** toolbar option exercises the existing legibility skin.
Production application stories provide context beyond isolated controls.

See [architecture](architecture.md) for ownership and changes, [charter](charter.md) for product
principles, and [operational state model](operational-state-model.md) for state semantics.
