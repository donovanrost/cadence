# Component Library

Cadence provides a comprehensive set of reusable UI components built on Phoenix LiveView, Tailwind CSS, and daisyUI.

## Component Location

All core components are defined in:
```
lib/cadence_web/components/core_components.ex
```

Import them automatically in any LiveView or component:
```elixir
use CadenceWeb, :live_view  # Imports all components
```

---

## Buttons

Consistent, accessible buttons with navigation support.

### Variants

```heex
<!-- Primary button (default) -->
<.button>Primary Action</.button>

<!-- Explicit primary -->
<.button variant="primary">Primary</.button>

<!-- daisyUI button classes -->
<button class="btn">Default</button>
<button class="btn btn-secondary">Secondary</button>
<button class="btn btn-accent">Accent</button>
<button class="btn btn-ghost">Ghost</button>

<!-- Sizes -->
<button class="btn btn-sm">Small</button>
<button class="btn">Normal</button>
<button class="btn btn-lg">Large</button>

<!-- States -->
<button class="btn" disabled>Disabled</button>
<button class="btn btn-primary loading">Loading</button>
```

### With Navigation

```heex
<.button navigate={~p"/dashboard"}>Go to Dashboard</.button>
<.button patch={~p"/edit"}>Edit (LiveView patch)</.button>
<.button href="https://example.com">External Link</.button>
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `variant` | `"primary"` \| `nil` | Button style variant |
| `navigate` | `string` | Phoenix route for navigation |
| `patch` | `string` | LiveView patch route |
| `href` | `string` | External URL |
| `class` | `string` | Additional CSS classes |

---

## Badges

Small status indicators with color variants.

### Usage

```heex
<.badge>Default</.badge>
<.badge variant="primary">Primary</.badge>
<.badge variant="secondary">Secondary</.badge>
<.badge variant="accent">Accent</.badge>
<.badge variant="success">Success</.badge>
<.badge variant="warning">Warning</.badge>
<.badge variant="error">Error</.badge>
<.badge variant="info">Info</.badge>
```

### Common Use Cases

```heex
<!-- User role badge -->
<.badge variant="primary">Admin</.badge>

<!-- Status indicator -->
<.badge variant="success">Active</.badge>
<.badge variant="error">Suspended</.badge>

<!-- Count badge -->
<.badge variant="neutral">5 missions</.badge>
```

---

## Avatars

User avatars with automatic initial generation and color coding.

### Basic Usage

```heex
<!-- Email only (uses first letter) -->
<.avatar email="john@example.com" />

<!-- With full name (uses initials) -->
<.avatar email="jane@example.com" name="Jane Doe" />

<!-- Different sizes -->
<.avatar email="user@example.com" size="sm" />
<.avatar email="user@example.com" size="md" />
<.avatar email="user@example.com" size="lg" />
```

### How It Works

- **Initials**: Extracts first letter of email or first+last initials from name
- **Colors**: Generates consistent color from email hash (same email = same color always)
- **5 color variants**: Uses primary, secondary, accent, info, or success colors

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `email` | `string` | ✅ | User's email address |
| `name` | `string` | ❌ | Full name for better initials |
| `size` | `"sm"` \| `"md"` \| `"lg"` | ❌ | Avatar size (default: `"md"`) |
| `class` | `string` | ❌ | Additional CSS classes |

---

## Dropdowns

Flexible dropdown menus for actions, navigation, or selections.

### Basic Usage

```heex
<.dropdown id="user-menu">
  <:trigger>
    <button class="btn">Menu</button>
  </:trigger>

  <li><a href="/profile">Profile</a></li>
  <li><a href="/settings">Settings</a></li>
  <li class="border-t border-base-300 my-1"></li>
  <li><a href="/logout">Sign Out</a></li>
</.dropdown>
```

### With Icons

```heex
<.dropdown id="actions">
  <:trigger>
    <button class="btn btn-ghost btn-sm">
      <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
    </button>
  </:trigger>

  <li>
    <a class="flex items-center gap-2">
      <.icon name="hero-pencil" class="h-4 w-4" />
      Edit
    </a>
  </li>
  <li>
    <a class="flex items-center gap-2 text-error">
      <.icon name="hero-trash" class="h-4 w-4" />
      Delete
    </a>
  </li>
</.dropdown>
```

### Dropdown Positions

```heex
<!-- Default: end (right-aligned) -->
<div class="dropdown dropdown-end">...</div>

<!-- Start (left-aligned) -->
<div class="dropdown dropdown-start">...</div>

<!-- Top -->
<div class="dropdown dropdown-top">...</div>
```

---

## Tables

Data tables with built-in actions dropdown.

### Standard Table

```heex
<.table
  id="organizations"
  rows={@streams.organizations}
  row_click={fn {_id, org} -> JS.navigate(~p"/organizations/#{org}") end}
>
  <:col :let={{_id, org}} label="Name"><%= org.name %></:col>
  <:col :let={{_id, org}} label="Status"><%= org.status %></:col>
  <:col :let={{_id, org}} label="Created">
    <%= Calendar.strftime(org.inserted_at, "%Y-%m-%d") %>
  </:col>

  <:action :let={{_id, org}}>
    <.link navigate={~p"/organizations/#{org}"}>
      <.icon name="hero-eye" class="h-4 w-4" />
      View
    </.link>
  </:action>

  <:action :let={{_id, org}}>
    <.link patch={~p"/organizations/#{org}/edit"}>
      <.icon name="hero-pencil" class="h-4 w-4" />
      Edit
    </.link>
  </:action>

  <:action :let={{id, org}}>
    <.link
      phx-click={JS.push("delete", value: %{id: org.id}) |> hide("##{id}")}
      data-confirm="Are you sure?"
      class="text-error"
    >
      <.icon name="hero-trash" class="h-4 w-4" />
      Delete
    </.link>
  </:action>
</.table>
```

### Actions Dropdown Pattern

All `:action` slots are automatically wrapped in a dropdown with a three-dot menu button. This is the **standard pattern** for all tables.

**Best practices:**
- Add icons to actions for clarity
- Use `text-error` class for destructive actions
- Include confirmation for delete actions
- Keep action labels concise (1-2 words)

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `string` | Unique table ID (required) |
| `rows` | `list` \| `LiveStream` | Table data |
| `row_click` | `function` | Optional row click handler |
| `row_id` | `function` | Custom row ID function |

### Slots

| Slot | Description |
|------|-------------|
| `:col` | Table column with `label` attribute |
| `:action` | Action menu item (auto-wrapped in dropdown) |

---

## Forms

### Input Component

Comprehensive form input with label and error handling.

```heex
<!-- Text input -->
<.input field={@form[:name]} type="text" label="Organization Name" />

<!-- Email input -->
<.input field={@form[:email]} type="email" label="Email Address" />

<!-- Select dropdown -->
<.input
  field={@form[:role]}
  type="select"
  label="Role"
  options={[
    {"Member", "member"},
    {"Admin", "admin"},
    {"Owner", "owner"}
  ]}
/>

<!-- Textarea -->
<.input field={@form[:description]} type="textarea" label="Description" />

<!-- Checkbox -->
<.input field={@form[:accept_terms]} type="checkbox" label="I agree to the terms" />
```

### Simple Form

Form wrapper with error handling:

```heex
<.simple_form for={@form} phx-submit="save">
  <.input field={@form[:name]} type="text" label="Name" />
  <.input field={@form[:email]} type="email" label="Email" />

  <:actions>
    <.button>Save</.button>
    <.button type="button" variant="ghost" phx-click="cancel">Cancel</.button>
  </:actions>
</.simple_form>
```

---

## Modals

Full-screen modals with backdrop and escape handling.

### Usage

```heex
<.modal
  id="org-modal"
  show={@live_action == :edit}
  on_cancel={JS.patch(~p"/organizations")}
>
  <.header>Edit Organization</.header>

  <.simple_form for={@form} phx-submit="save">
    <.input field={@form[:name]} label="Name" />
    <:actions>
      <.button>Save Changes</.button>
    </:actions>
  </.simple_form>
</.modal>
```

### Modal Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `string` | Unique modal ID |
| `show` | `boolean` | Whether to show modal |
| `on_cancel` | `JS` | Handler for closing modal (ESC or backdrop click) |

---

## Sidebar Navigation

Navigation items for the sidebar layout.

### Usage

```heex
<.sidebar_nav_item navigate={~p"/dashboard"} active={@current_path == "/dashboard"}>
  <:icon><.icon name="hero-home" class="h-5 w-5" /></:icon>
  Dashboard
</.sidebar_nav_item>

<.sidebar_nav_item navigate={~p"/settings"} active={false}>
  <:icon><.icon name="hero-cog-6-tooth" class="h-5 w-5" /></:icon>
  Settings
</.sidebar_nav_item>
```

### Active States

Active items get:
- Cyan accent color
- Left border (4px)
- Cyan glow effect
- Bold font weight

Inactive items:
- Muted text color
- Purple glow on hover
- Smooth transitions

---

## Icons

Using Heroicons v2.2 throughout the application.

### Usage

```heex
<!-- Basic icon -->
<.icon name="hero-home" class="h-6 w-6" />

<!-- With color -->
<.icon name="hero-check-circle" class="h-5 w-5 text-success" />

<!-- In buttons -->
<button class="btn btn-primary">
  <.icon name="hero-plus" class="h-5 w-5" />
  Add New
</button>
```

### Common Icons

| Icon | Name | Usage |
|------|------|-------|
| 🏠 | `hero-home` | Dashboard, home |
| 👥 | `hero-users` | Users, team |
| ⚙️ | `hero-cog-6-tooth` | Settings |
| ✏️ | `hero-pencil` | Edit |
| 🗑️ | `hero-trash` | Delete |
| 👁️ | `hero-eye` | View |
| ✓ | `hero-check` | Success, selected |
| ✉️ | `hero-envelope` | Invitations, email |
| 🏢 | `hero-building-office` | Organizations |
| 🚀 | `hero-rocket-launch` | Missions |

**Browse all icons**: https://heroicons.com

---

## Flash Messages

Toast-style notifications in the top-right corner.

### Usage

```elixir
# In LiveView
socket
|> put_flash(:info, "Organization created successfully!")
|> redirect(to: ~p"/organizations")

socket
|> put_flash(:error, "Unable to delete organization")
```

### Flash Variants

- **`:info`** - Blue info icon, informational messages
- **`:error`** - Red error icon, error messages

Messages automatically dismiss on click or can be closed manually.

---

## Header

Page headers with title, subtitle, and action slots.

### Usage

```heex
<.header>
  Organizations
  <:subtitle>
    Manage spacecraft operation organizations and their settings
  </:subtitle>
  <:actions>
    <.link patch={~p"/organizations/new"}>
      <.button>New Organization</.button>
    </.link>
  </:actions>
</.header>
```

---

## Lists

Definition lists for key-value pairs.

### Usage

```heex
<.list>
  <:item title="Name"><%= @organization.name %></:item>
  <:item title="Status"><%= @organization.status %></:item>
  <:item title="Tier"><%= @organization.subscription_tier %></:item>
  <:item title="Max Missions"><%= @organization.max_missions %></:item>
</.list>
```

---

## Component Best Practices

### DO ✅

- Use semantic component props (`variant="primary"`) over inline styles
- Leverage slots for flexible content composition
- Add ARIA labels for accessibility
- Include loading and empty states
- Test components in both light and dark modes
- Add vaporwave glows to interactive elements

### DON'T ❌

- Don't bypass components to use raw HTML/CSS
- Don't hardcode colors - use theme classes
- Don't forget keyboard navigation
- Don't create duplicate components - extend existing ones
- Don't over-nest components - keep it simple

### Extending Components

To add new components, follow this pattern in `core_components.ex`:

```elixir
@doc """
Brief description of what the component does.

## Examples

    <.your_component>Content</.your_component>
"""
attr :required_attr, :string, required: true
attr :optional_attr, :string, default: "default"
slot :inner_block, required: true

def your_component(assigns) do
  ~H"""
  <div class="your-component-class">
    {render_slot(@inner_block)}
  </div>
  """
end
```
