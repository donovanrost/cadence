# Layout Patterns

Cadence uses a sidebar-based layout system optimized for desktop and mobile spacecraft operation workflows.

## Layout Components

All layouts are defined in:
```
lib/cadence_web/components/layouts.ex
```

---

## Sidebar Layout

The primary layout for authenticated users, featuring context-aware navigation.

### Structure

```
┌─────────────────────────────────────────────────┐
│ [Logo] CADENCE                                  │  ← Sidebar (fixed on desktop)
│                                                 │
│ • Dashboard                                     │
│ • Organizations                                 │
│ • Design System                                 │
│                                                 │
│ [Theme Toggle]                                  │
├─────────────┬───────────────────────────────────┤
│             │  [User/Org Menu ▼]                │  ← Top bar (content area)
│             ├───────────────────────────────────┤
│             │                                   │
│             │  Page Content                     │
│             │                                   │
│             │                                   │
└─────────────┴───────────────────────────────────┘
```

### Usage in Router

```elixir
scope "/admin", CadenceWeb do
  pipe_through [:browser, :require_authenticated_user, :require_system_admin]

  live_session :admin,
    layout: {CadenceWeb.Layouts, :sidebar},  # ← Sidebar layout
    on_mount: [
      {CadenceWeb.LiveAuth, :require_authenticated},
      {CadenceWeb.LiveAuth, :require_system_admin},
      {CadenceWeb.LiveAuth, :put_current_path}
    ] do
    live "/", AdminLive.Index, :index
    live "/organizations", OrganizationLive.Index, :index
  end
end
```

### Layout Props

The sidebar layout expects these assigns:

| Assign | Type | Description |
|--------|------|-------------|
| `flash` | `map` | Flash messages |
| `current_scope` | `Scope` | Current user and organization context |
| `current_path` | `string` | Current URI path for active nav highlighting |
| `inner_content` | `any` | Page content to render |

---

## Responsive Behavior

### Desktop (≥1024px)

- **Sidebar**: Fixed, always visible (272px wide)
- **User menu**: Top-right of content area
- **Navigation**: Visible with icons and labels

### Tablet (768px - 1023px)

- **Sidebar**: Collapsible drawer (overlay)
- **Hamburger menu**: Top-left to toggle sidebar
- **User menu**: Top-right

### Mobile (<768px)

- **Sidebar**: Drawer (slides in from left)
- **Top bar**: Hamburger menu (left) + User menu (right)
- **Backdrop**: Click to close sidebar
- **Touch-optimized**: Larger tap targets

### Implementation

Uses daisyUI's drawer component with Tailwind responsive classes:

```heex
<!-- Desktop: always open -->
<div class="drawer lg:drawer-open">
  <!-- Mobile: toggle with checkbox -->
  <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

  <!-- Content area -->
  <div class="drawer-content">
    <!-- Mobile hamburger button -->
    <div class="lg:hidden">
      <label for="sidebar-drawer" class="btn btn-ghost">
        <.icon name="hero-bars-3" />
      </label>
    </div>

    <!-- Page content -->
    <main>{@inner_content}</main>
  </div>

  <!-- Sidebar -->
  <div class="drawer-side">
    <label for="sidebar-drawer" class="drawer-overlay"></label>
    <div class="w-72 bg-base-200">
      <!-- Sidebar content -->
    </div>
  </div>
</div>
```

---

## Context-Aware Navigation

Navigation automatically changes based on the current route context.

### Admin Context (`/admin/*`)

Shown when `current_path` starts with `/admin`:

```
• Dashboard
• Organizations
• Design System
• Users (coming soon)
• Invitations (coming soon)
```

Accessible only to system administrators.

### Organization Context (everything else)

Shown for regular organization members:

```
• Dashboard
• Missions
• Targets
• Team
• Settings
```

### Implementation

```elixir
def sidebar_navigation(assigns) do
  is_admin_context = String.starts_with?(assigns.current_path, "/admin")

  ~H"""
  <%= if @is_admin_context do %>
    <!-- Admin navigation items -->
  <% else %>
    <!-- Organization navigation items -->
  <% end %>
  """
end
```

---

## User/Organization Menu

Combined dropdown in the top-right corner.

### Features

- **Avatar**: User initials with color coding
- **Organization name**: Current organization (or "System Admin")
- **User email**: Displayed below org name
- **Organization switcher**: List of all user's organizations
- **User actions**: Profile, Settings, Theme
- **Admin link**: Conditional "Admin Panel" link for system admins
- **Sign out**: Logout option

### Structure

```heex
<.dropdown id="user-org-menu">
  <:trigger>
    [Avatar] Org Name
            user@email.com  ▼
  </:trigger>

  <!-- Organizations (if user has multiple) -->
  Organizations
  • ✓ Current Organization
  • Another Organization
  ─────────────

  <!-- User actions -->
  • Your Profile
  • Account Settings
  ─────────────

  <!-- Admin link (if system admin) -->
  • 🛡️ Admin Panel
  ─────────────

  • Sign Out
</.dropdown>
```

### Behavior

- **Organization switching**: Click an organization to switch context
- **Checkmark**: Shows current active organization
- **Admin badge**: Highlighted in accent color
- **Responsive**: Avatar only on mobile, full display on desktop

---

## Sidebar Styling

### Dark Mode

```css
/* Sidebar background (darker than content) */
.sidebar-dark-bg {
  background-color: oklch(10% 0.02 265);  /* Even darker than base-100 */
}

/* Active nav item */
.sidebar-nav-item.active {
  background: oklch(80% 0.12 210 / 0.1);  /* Cyan tint */
  color: oklch(80% 0.12 210);              /* Cyan text */
  border-left: 4px solid oklch(80% 0.12 210);
  box-shadow: 0 0 10px oklch(80% 0.12 210 / 0.5);  /* Cyan glow */
}

/* Hover state */
.sidebar-nav-item:hover {
  background: oklch(72% 0.15 285 / 0.1);  /* Purple tint */
  box-shadow: 0 0 8px oklch(72% 0.15 285 / 0.4);  /* Purple glow */
}
```

### Logo & Branding

```heex
<.link navigate={~p"/"} class="flex items-center gap-3">
  <img src={~p"/images/logo.svg"} width="32" class="glow-cyan" />
  <span class="text-xl font-bold gradient-vaporwave bg-clip-text text-transparent">
    CADENCE
  </span>
</.link>
```

The logo text uses a vaporwave gradient that transitions from pink → purple → cyan.

---

## Page Structure

### Standard Page Layout

```heex
<div class="max-w-7xl mx-auto">  <!-- Container -->
  <.header>
    Page Title
    <:subtitle>Optional description</:subtitle>
    <:actions>
      <.button>Primary Action</.button>
    </:actions>
  </.header>

  <!-- Page content -->
  <div class="mt-8">
    <!-- Cards, tables, forms, etc. -->
  </div>
</div>
```

### Recommended Max Widths

| Content Type | Max Width | Class |
|--------------|-----------|-------|
| **Default** | 1280px | `max-w-7xl` |
| **Wide content** | 1536px | `max-w-screen-2xl` |
| **Narrow forms** | 672px | `max-w-2xl` |
| **Article content** | 768px | `max-w-3xl` |

### Spacing Guidelines

```css
/* Section spacing */
.section {
  margin-top: 3rem;    /* mt-12 */
  margin-bottom: 3rem; /* mb-12 */
}

/* Content spacing */
.content > * + * {
  margin-top: 2rem;    /* space-y-8 */
}

/* Card padding */
.card {
  padding: 1.5rem;     /* p-6 */
}
```

---

## Empty States

Design pattern for pages with no data.

### Example

```heex
<div class="text-center py-12">
  <.icon name="hero-inbox" class="h-16 w-16 mx-auto text-base-content/30" />
  <h3 class="mt-4 text-lg font-semibold">No organizations yet</h3>
  <p class="mt-2 text-base-content/60">
    Get started by creating your first organization
  </p>
  <.button class="mt-6" patch={~p"/organizations/new"}>
    <.icon name="hero-plus" class="h-5 w-5" />
    Create Organization
  </.button>
</div>
```

---

## Loading States

### Skeleton Screens

```heex
<div class="animate-pulse">
  <div class="h-4 bg-base-300 rounded w-3/4 mb-4"></div>
  <div class="h-4 bg-base-300 rounded w-1/2 mb-4"></div>
  <div class="h-4 bg-base-300 rounded w-5/6"></div>
</div>
```

### Loading Buttons

```heex
<button class="btn btn-primary loading">
  Processing...
</button>
```

### Loading Spinners

```heex
<.icon name="hero-arrow-path" class="h-5 w-5 motion-safe:animate-spin" />
```

---

## Modal Layouts

### Full Modal Structure

```heex
<.modal id="edit-modal" show={@live_action == :edit} on_cancel={JS.patch(~p"/")}>
  <.header>Edit Item</.header>

  <div class="mt-6">
    <.simple_form for={@form} phx-submit="save">
      <.input field={@form[:name]} label="Name" />
      <.input field={@form[:description]} type="textarea" label="Description" />

      <:actions>
        <.button>Save Changes</.button>
        <button type="button" class="btn btn-ghost" phx-click={JS.patch(~p"/")}>
          Cancel
        </button>
      </:actions>
    </.simple_form>
  </div>
</.modal>
```

### Modal Best Practices

- **Header**: Always include a clear title
- **Actions**: Put primary action on the right, cancel on the left
- **Escape**: Always provide escape routes (ESC key, backdrop click, Cancel button)
- **Focus**: Auto-focus first input field
- **Max width**: Keep modals narrow (max-w-2xl) for readability

---

## Grid Layouts

### Responsive Grid

```heex
<!-- 1 column on mobile, 2 on tablet, 3 on desktop -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  <div class="card bg-base-200 p-6">Card 1</div>
  <div class="card bg-base-200 p-6">Card 2</div>
  <div class="card bg-base-200 p-6">Card 3</div>
</div>
```

### Common Patterns

```heex
<!-- Stats grid -->
<div class="grid grid-cols-1 md:grid-cols-3 gap-6">
  <.stat />
  <.stat />
  <.stat />
</div>

<!-- Form two-column -->
<div class="grid grid-cols-1 md:grid-cols-2 gap-6">
  <.input field={@form[:first_name]} />
  <.input field={@form[:last_name]} />
</div>

<!-- Sidebar + content -->
<div class="grid grid-cols-1 lg:grid-cols-4 gap-8">
  <aside class="lg:col-span-1">Sidebar</aside>
  <main class="lg:col-span-3">Content</main>
</div>
```

---

## Accessibility

### Keyboard Navigation

- **Tab order**: Logical, follows visual order
- **Escape**: Closes modals and dropdowns
- **Enter**: Submits forms, activates buttons
- **Space**: Toggles checkboxes, opens dropdowns
- **Arrow keys**: Navigate dropdown items

### ARIA Labels

```heex
<!-- Screen reader text for icon buttons -->
<button aria-label="Close modal">
  <.icon name="hero-x-mark" />
</button>

<!-- Hidden labels -->
<span class="sr-only">Search</span>

<!-- Accessible navigation -->
<nav aria-label="Main navigation">
  <ul>...</ul>
</nav>
```

### Focus Management

```elixir
# Auto-focus first input in modal
<.input field={@form[:name]} phx-hook="AutoFocus" />
```

---

## Layout Best Practices

### DO ✅

- Use semantic HTML5 elements (`<nav>`, `<main>`, `<aside>`)
- Provide skip links for keyboard users
- Test on actual mobile devices, not just browser dev tools
- Ensure touch targets are at least 44×44px
- Use consistent spacing throughout the app
- Test with sidebar collapsed and expanded

### DON'T ❌

- Don't use fixed positioning except for modals and sidebar
- Don't assume screen size (always make it responsive)
- Don't nest layouts more than 2 levels deep
- Don't hardcode widths - use max-width and responsive classes
- Don't forget to test dark mode styling

---

## Adding New Layouts

To create a custom layout:

1. **Define the layout function** in `layouts.ex`:

```elixir
attr :flash, :map, required: true
attr :inner_content, :any, required: true

def my_custom_layout(assigns) do
  ~H"""
  <div class="custom-layout">
    {@inner_content}
    <.flash_group flash={@flash} />
  </div>
  """
end
```

2. **Use in router**:

```elixir
live_session :custom,
  layout: {CadenceWeb.Layouts, :my_custom_layout} do
  live "/special-page", SpecialLive.Index
end
```

3. **Pass required assigns** from LiveView:

```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, :page_title, "Special Page")}
end
```
