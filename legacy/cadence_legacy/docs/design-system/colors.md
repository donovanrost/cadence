---
title: Color Palette
tags: [reference, design, colors, tailwind]
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Color Palette

Cadence uses a dual-theme color system inspired by vaporwave aesthetics and Tokyo Night, optimized for both light and dark modes.

## Color Philosophy

- **Dark mode**: Near-black backgrounds with vibrant neon accents for extended viewing
- **Light mode**: Soft pastels that maintain vaporwave character without overwhelming
- **Semantic colors**: Meaningful color choices for success, warning, error states
- **Accessibility**: All text meets WCAG AA contrast ratios (4.5:1 minimum)

## Dark Mode (Tokyo Night)

The default theme, optimized for low-light environments and extended use.

### Background Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| Base 100 | `#16161e` | `oklch(12% 0.02 265)` | Main background |
| Base 200 | `#1f2230` | `oklch(15% 0.02 260)` | Cards, surfaces |
| Base 300 | `#292d42` | `oklch(18% 0.02 258)` | Elevated surfaces (modals, dropdowns) |
| Base Content | `#c0caf5` | `oklch(85% 0.02 250)` | Text color |

**Why very dark blue?**
Pure black (`#000000`) creates harsh eye strain. Our near-black with subtle blue undertone (`#16161e`) provides depth while being easier on the eyes during long sessions.

### Accent Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| **Primary** (Cyan) | `#7dcfff` | `oklch(80% 0.12 210)` | Primary buttons, links, active states |
| **Secondary** (Purple) | `#bb9af7` | `oklch(72% 0.15 285)` | Secondary actions, highlights |
| **Accent** (Hot Pink) | `#ff007c` | `oklch(60% 0.25 340)` | Alerts, important indicators, vaporwave energy |
| **Neutral** | `#3b4261` | `oklch(30% 0.03 260)` | Muted elements, borders |

**Design choice**: Bright, saturated accents pop against the dark background, making interactive elements immediately obvious while maintaining the vaporwave aesthetic.

### Semantic Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| **Success** (Cyan-Teal) | `#73daca` | `oklch(78% 0.10 185)` | Successful operations, spacecraft online |
| **Warning** (Orange) | `#ff9e64` | `oklch(72% 0.15 50)` | Warnings, degraded states |
| **Error** (Coral-Red) | `#f7768e` | `oklch(68% 0.20 10)` | Critical alerts, failures |
| **Info** (Blue) | `#7aa2f7` | `oklch(70% 0.14 250)` | Informational messages |

**Why cyan-teal for success?** Traditional green doesn't fit the vaporwave aesthetic. Our cyan-teal variant maintains the theme while clearly signaling success.

## Light Mode (Vaporwave Pastel)

Softer colors optimized for bright environments, maintaining the vaporwave character.

### Background Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| Base 100 | `#fafbff` | `oklch(98% 0.005 250)` | Main background (subtle blue tint) |
| Base 200 | `#f1f5f9` | `oklch(96% 0.005 250)` | Cards, surfaces |
| Base 300 | `#e2e8f0` | `oklch(92% 0.008 250)` | Elevated surfaces |
| Base Content | `#1e293b` | `oklch(25% 0.015 250)` | Text color |

### Accent Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| **Primary** (Deep Cyan) | `#0891b2` | `oklch(55% 0.12 210)` | Primary actions (darker for readability) |
| **Secondary** (Purple) | `#9333ea` | `oklch(50% 0.25 285)` | Secondary actions |
| **Accent** (Hot Pink) | `#ec4899` | `oklch(62% 0.23 340)` | Attention-grabbing elements |
| **Neutral** | `#64748b` | `oklch(45% 0.01 250)` | Muted elements |

### Semantic Colors

| Color | Hex | OKLCH | Usage |
|-------|-----|-------|-------|
| **Success** (Teal) | `#14b8a6` | `oklch(68% 0.11 185)` | Successful operations |
| **Warning** (Orange) | `#f97316` | `oklch(68% 0.18 40)` | Warnings |
| **Error** (Rose) | `#f43f5e` | `oklch(60% 0.22 10)` | Errors |
| **Info** (Sky Blue) | `#0ea5e9` | `oklch(66% 0.14 230)` | Information |

## Using Colors

### In Templates (daisyUI classes)

```heex
<!-- Background colors -->
<div class="bg-base-100">Main background</div>
<div class="bg-base-200">Card background</div>
<div class="bg-base-300">Elevated surface</div>

<!-- Accent colors -->
<button class="btn btn-primary">Primary Action</button>
<button class="btn btn-secondary">Secondary Action</button>
<button class="btn btn-accent">Accent Button</button>

<!-- Semantic colors -->
<div class="alert alert-success">Operation successful</div>
<div class="alert alert-warning">Warning message</div>
<div class="alert alert-error">Error occurred</div>
<div class="alert alert-info">Information</div>

<!-- Text colors -->
<p class="text-base-content">Main text</p>
<p class="text-base-content/60">Muted text (60% opacity)</p>
```

### In CSS (Tailwind utilities)

```css
/* Use daisyUI color tokens directly */
.custom-element {
  background-color: oklch(var(--p));  /* Primary color */
  color: oklch(var(--pc));            /* Primary content */
}

/* Or use Tailwind classes */
<div class="bg-primary text-primary-content">
  Automatically contrasting text
</div>
```

## Vaporwave Effects

### Neon Glows

Custom utility classes for the signature vaporwave glow:

```css
/* Cyan glow */
.glow-cyan {
  box-shadow: 0 0 10px oklch(80% 0.12 210 / 0.5),
              0 0 20px oklch(80% 0.12 210 / 0.3);
}

/* Purple glow */
.glow-purple {
  box-shadow: 0 0 10px oklch(72% 0.15 285 / 0.5),
              0 0 20px oklch(72% 0.15 285 / 0.3);
}

/* Pink glow */
.glow-pink {
  box-shadow: 0 0 10px oklch(60% 0.25 340 / 0.5),
              0 0 20px oklch(60% 0.25 340 / 0.3);
}

/* Hover glow (interactive elements) */
.hover-glow-cyan:hover {
  box-shadow: 0 0 8px oklch(80% 0.12 210 / 0.4),
              0 0 16px oklch(80% 0.12 210 / 0.2);
}
```

**Usage:**
```heex
<div class="card glow-cyan">Always glowing</div>
<button class="btn hover-glow-purple">Glow on hover</button>
```

### Gradients

```css
/* Full vaporwave gradient (pink → purple → cyan) */
.gradient-vaporwave {
  background: linear-gradient(135deg,
              oklch(60% 0.25 340) 0%,   /* Pink */
              oklch(72% 0.15 285) 50%,   /* Purple */
              oklch(80% 0.12 210) 100%); /* Cyan */
}

/* Subtle background gradient */
.gradient-vaporwave-subtle {
  background: linear-gradient(135deg,
              oklch(60% 0.25 340 / 0.1) 0%,
              oklch(72% 0.15 285 / 0.1) 50%,
              oklch(80% 0.12 210 / 0.1) 100%);
}
```

**Usage:**
```heex
<!-- Full gradient for hero sections -->
<div class="h-32 gradient-vaporwave text-white">
  <h1>Vaporwave Header</h1>
</div>

<!-- Subtle gradient for backgrounds -->
<div class="gradient-vaporwave-subtle p-8">
  Subtle background tint
</div>
```

## Theme Switching

Cadence supports three theme modes:

1. **System** (default): Follows OS preference
2. **Light**: Always light mode
3. **Dark**: Always dark mode

The theme is persisted in `localStorage` and automatically applied on page load.

### Programmatic Theme Control

```javascript
// Set theme
localStorage.setItem('phx:theme', 'dark');  // 'light', 'dark', or remove for 'system'
document.documentElement.setAttribute('data-theme', 'dark');

// Trigger theme change event
window.dispatchEvent(new CustomEvent('phx:set-theme', {
  target: { dataset: { phxTheme: 'dark' }}
}));
```

## Best Practices

### DO ✅

- Use semantic color names (`btn-primary`) over hex values
- Leverage daisyUI's automatic contrast (`bg-primary text-primary-content`)
- Apply vaporwave glows sparingly on interactive or important elements
- Test in both light and dark modes
- Use opacity modifiers for muted text (`text-base-content/60`)

### DON'T ❌

- Don't use pure black (`#000000`) or pure white (`#ffffff`) for backgrounds
- Don't mix custom colors with the theme - extend the daisyUI config instead
- Don't over-use glow effects - they lose impact
- Don't ignore contrast ratios for accessibility
- Don't hardcode hex values - use CSS custom properties

## Extending the Palette

To add new theme colors, edit `assets/css/app.css`:

```css
@plugin "../vendor/daisyui-theme" {
  name: "dark";
  /* ... existing config ... */
  --color-your-custom-color: oklch(70% 0.15 180);
}
```

Then use it like other daisyUI colors:
```heex
<div class="bg-your-custom-color">Custom colored element</div>
```
