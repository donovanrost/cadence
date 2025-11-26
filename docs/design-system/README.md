# Cadence Design System

A vaporwave/Tokyo Night inspired design system for the Cadence spacecraft operations platform.

## Overview

Cadence's design system combines the cyberpunk aesthetics of vaporwave with the refined color palette of Tokyo Night, creating a modern, professional interface suitable for mission-critical spacecraft operations while maintaining visual appeal for long monitoring sessions.

## Philosophy

- **Professional yet vibrant**: Balance mission-critical reliability with engaging aesthetics
- **Easy on the eyes**: Dark mode optimized for extended use, with thoughtful contrast ratios
- **Consistent patterns**: Standardized components and layouts across the entire application
- **Accessibility first**: WCAG-compliant color contrasts and keyboard navigation
- **Responsive design**: Seamless experience from mobile to desktop

## Tech Stack

- **Framework**: Phoenix LiveView 1.1
- **CSS**: Tailwind CSS 4.1 (utility-first)
- **Components**: daisyUI (Tailwind plugin)
- **Icons**: Heroicons v2.2
- **Language**: Elixir 1.15+

## Quick Links

- **[Color Palette](./colors.md)** - Vaporwave/Tokyo Night color system
- **[Components](./components.md)** - Reusable UI component library
- **[Layouts](./layouts.md)** - Page structure and navigation patterns
- **[Live Demo](/admin/design-system)** - Interactive component showcase

## Key Features

### 🎨 Dual Theme Support
- **Dark Mode** (default): Deep navy backgrounds with bright cyan, purple, and pink accents
- **Light Mode**: Clean pastels with subtle vaporwave hints
- **System preference**: Auto-detects user's OS theme preference

### ✨ Vaporwave Effects
- **Neon glows**: Subtle box-shadow effects on hover
- **Gradients**: Pink → Purple → Cyan gradients for special elements
- **Smooth transitions**: 300ms easing for all interactive elements

### 🧩 Component Library
- **Core components**: Buttons, forms, tables, modals, dropdowns
- **Navigation**: Sidebar layout with context-aware routing
- **Data display**: Tables with action dropdowns, cards, badges
- **Feedback**: Toast notifications, loading states, empty states

### 📱 Responsive Design
- **Mobile**: Drawer navigation with hamburger menu
- **Tablet**: Optimized touch targets and spacing
- **Desktop**: Fixed sidebar with full navigation

## Getting Started

### Using Components

All components are available in `CadenceWeb.CoreComponents`:

```elixir
# In your LiveView template
<.button>Click me</.button>
<.badge variant="primary">New</.badge>
<.avatar email="user@example.com" size="md" />
```

### Applying Colors

Use Tailwind/daisyUI color classes:

```heex
<div class="bg-primary text-primary-content">
  Primary colored element
</div>

<button class="btn btn-secondary">
  Secondary button
</button>
```

### Using Layouts

Configure sidebar layout in your router:

```elixir
live_session :authenticated,
  layout: {CadenceWeb.Layouts, :sidebar} do
  live "/dashboard", DashboardLive.Index
end
```

## File Locations

- **Theme configuration**: `assets/css/app.css`
- **Core components**: `lib/cadence_web/components/core_components.ex`
- **Layout components**: `lib/cadence_web/components/layouts.ex`
- **Design system page**: `lib/cadence_web/live/design_system_live/index.ex`

## Contributing

When adding new components or modifying the design system:

1. Follow existing component patterns in `core_components.ex`
2. Use daisyUI classes where possible
3. Add vaporwave glow effects with `hover-glow-*` utilities
4. Ensure accessibility (keyboard navigation, ARIA labels)
5. Test in both light and dark modes
6. Update documentation and live design system page

## Version History

- **v0.1.0** (2025-11-16): Initial design system implementation
  - Vaporwave/Tokyo Night color palette
  - Sidebar navigation layout
  - Core component library
  - Actions dropdown pattern for tables
