# Cadence visual foundations

## Status

Working visual direction for the Vue frontend proof of concept. This document
is subordinate to the [design-system charter](charter.md) and the
[operational state model](operational-state-model.md). The
[symbology specification](symbology.md) defines the invariant shapes paired
with operational status. This document defines how the interface carries
structure and semantic signal; it does not redefine domain meaning.

## Direction

Cadence uses **operational monochrome**: hard, high-contrast structure with
color reserved for information.

The memorable characteristic is not darkness, glow, or science-fiction
decoration. It is the precision of a system whose boundaries, alignment, and
signals can be trusted under sustained use.

## Structural color

- Dark mode uses white boundaries on a near-black canvas.
- Light mode uses black boundaries on a white canvas.
- Primary boundaries are one-pixel solid lines.
- Subordinate separators may use reduced opacity of the same monochrome line.
- Surface changes remain neutral and must not introduce a colored cast.
- Dark and light modes must communicate the same hierarchy and state.

Darkness and brightness are environmental modes, not semantic states. Neither
mode may imply urgency, authority, health, or time context.

## Informative color

Chroma must answer a specific question:

| Role      | Information communicated                                                                |
| --------- | --------------------------------------------------------------------------------------- |
| Action    | A primary interaction, commitment path, or selected control.                            |
| Signal    | Live data, active telemetry, focus, or a selected observation.                          |
| Nominal   | A confirmed successful or nominal condition when that confirmation needs to be visible. |
| Attention | A condition requiring timely awareness or investigation.                                |
| Immediate | Failure, danger, destructive action, or immediate consequence.                          |

Color must not be used to decorate headings, brand routine surfaces, separate
arbitrary content groups, or make nominal data appear more interesting. Text,
shape, position, and accessible semantics must retain the meaning without
color. Status color follows the redundant color-and-shape vocabulary in the
[symbology specification](symbology.md); it is not selected locally by a
component.

## Geometry

- Border radius is zero for every interface surface and control.
- Shadows and simulated elevation are not part of the visual language.
- Panels connect through shared boundaries rather than floating as cards.
- Layering is expressed through placement, borders, spacing, and surface
  contrast.
- Circular or curved geometry is reserved for data whose actual shape is
  meaningful, such as an orbit, body, polar plot, or plotted observation. It is
  also permitted for invariant status symbology whose geometry carries learned
  meaning. It is not a component treatment.

## Typography

The system uses two typographic voices:

1. **Interface:** Archivo for navigation, labels, instructions, hierarchy, and
   actions.
2. **Evidence:** JetBrains Mono for values, units, times, coordinates,
   identifiers, command material, and other machine-readable evidence.

Typography must remain compact and explicit. Large type is reserved for the
few values or identities that establish the operator's present task. Serif or
editorial typography is not part of this direction.

## Motion and depth

Motion describes bounded progress or a meaningful transition. It must not make
nominal, live, or connected state continuously pulse. Hover and focus behavior
may change contrast or line color but must not lift controls from the surface.

Gradients, glows, textures, and shadows are excluded from the structural
system. Data visualization may use transparent semantic fills when they encode
an interval, uncertainty, or magnitude rather than atmosphere.

## Component requirements

Every shared component must:

- render with zero radius and no shadow;
- use the monochrome boundary token for structure;
- use semantic color only through an explicit state or interaction role;
- preserve invariant status-symbol geometry when rendering operational state;
- remain legible in both modes without changing its meaning;
- preserve a visible keyboard focus indicator;
- avoid color-only state communication; and
- expose native state and evidence rather than deriving meaning from visual
  tone.

## Verification

Storybook defaults to dark mode and provides a global dark/light switch. Public
stories must be checked in both modes. Visual review should reject:

- cream, paper, or tinted neutral surfaces;
- soft cards, pills, and rounded controls;
- decorative accent color;
- shadows, glow, or faux depth;
- continuously animated nominal status;
- color used as the only state distinction; and
- disconnected panels that should read as one operational instrument.
