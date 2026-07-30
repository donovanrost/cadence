defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @doc """
  Fixed-position flash stack. Renders :info and :error entries from the
  controller/LiveView flash map. Emits nothing when both are absent.
  """
  attr :flash, :map, required: true

  def flash_stack(assigns) do
    ~H"""
    <div class="fixed top-5 right-5 max-md:top-auto max-md:bottom-3 max-md:left-3 max-md:right-3 z-[var(--z-toast)] grid gap-3">
      <p
        :if={info = Phoenix.Flash.get(@flash, :info)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-success/40 rounded-[2px] bg-base-200/95 text-sm text-base-content shadow-lg"
      >
        {info}
      </p>
      <p
        :if={error = Phoenix.Flash.get(@flash, :error)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-error/40 rounded-[2px] bg-base-200/95 text-sm text-base-content shadow-lg"
      >
        {error}
      </p>
    </div>
    """
  end

  @doc """
  Bell icon with unread badge and recent-notifications dropdown.

  Attrs:
    * `id` — unique DOM id (layouts render this twice, so ids must differ)
    * `count` — unread count (integer)
    * `notifications` — list of `%Cadence.Notifications.Notification{}` (top 5)
  """
  attr :id, :string, required: true
  attr :count, :integer, default: 0
  attr :notifications, :list, default: []

  def notifications_bell(assigns) do
    ~H"""
    <div id={@id} phx-hook="DropdownMenu" class="dropdown dropdown-end">
      <button
        type="button"
        data-dropdown-trigger
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-menu"}
        aria-label="Notifications"
        class="btn btn-ghost btn-sm btn-circle relative"
      >
        <span class="hero-bell h-5 w-5"></span>
        <%= if @count > 0 do %>
          <span class="badge badge-primary badge-xs absolute -top-0.5 -right-0.5 font-mono">
            {format_count(@count)}
          </span>
        <% end %>
      </button>
      <div
        id={"#{@id}-menu"}
        role="menu"
        class="dropdown-content menu bg-base-200 z-[var(--z-popover)] w-80 p-2 shadow-lg border border-primary/20 max-h-96 overflow-y-auto"
      >
        <li class="menu-title px-3 py-2">
          <span class="hud-label">
            Notifications
            <%= if @count > 0 do %>
              <span class="text-primary">({@count} unread)</span>
            <% end %>
          </span>
        </li>
        <%= if @notifications == [] do %>
          <li class="px-3 py-4 text-center text-sm text-base-content/60">
            No notifications
          </li>
        <% else %>
          <li :for={n <- @notifications}>
            <.link navigate={~p"/notifications"} class="flex items-start gap-2 px-3 py-2">
              <span :if={is_nil(n.read_at)} class="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
              <span :if={n.read_at} class="mt-1.5 w-1.5 h-1.5 flex-shrink-0"></span>
              <span class="flex-1 min-w-0">
                <span class="block text-xs font-semibold text-base-content truncate">{n.title}</span>
                <span :if={n.body} class="block text-xs text-base-content/70 truncate">{n.body}</span>
              </span>
            </.link>
          </li>
        <% end %>
        <li class="border-t border-primary/10 mt-1 pt-1">
          <.link navigate={~p"/notifications"} class="text-xs text-primary uppercase tracking-wide">
            See all notifications
          </.link>
        </li>
      </div>
    </div>
    """
  end

  defp format_count(n) when n > 9, do: "9+"
  defp format_count(n), do: Integer.to_string(n)

  @doc """
  Top-right user menu — trigger plus popover panel with identity, org context,
  platform-admin shortcut (when applicable), and sign out.

  Attrs:
    * `id` — unique DOM id (layouts render this twice, so ids must differ)
    * `scope` — `%Cadence.Auth.Scope{}` with `:user` and optional `:organization`
    * `memberships` — list of `%{membership: OrganizationMembership.t(), organization: Organization.t()}`
    * `platform_admin?` — boolean
  """
  attr :id, :string, required: true
  attr :scope, :any, required: true
  attr :memberships, :list, default: []
  attr :platform_admin?, :boolean, default: false

  def user_menu(assigns) do
    ~H"""
    <div id={@id} phx-hook="DropdownMenu" class="dropdown dropdown-end">
      <button
        type="button"
        data-dropdown-trigger
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-menu"}
        class="btn btn-ghost btn-sm gap-1"
      >
        <span class="text-xs text-base-content/60">{display_label(@scope.user)}</span>
        <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform"></span>
      </button>

      <div
        id={"#{@id}-menu"}
        role="menu"
        class="dropdown-content menu bg-base-200 z-[var(--z-popover)] w-72 p-2 shadow-lg border border-primary/20"
      >
        <div role="presentation" class="px-3 py-2">
          <p class="text-sm font-semibold text-base-content">{display_label(@scope.user)}</p>
          <p
            :if={@scope.user.display_name not in [nil, ""]}
            class="text-xs text-base-content/60 truncate"
          >
            {@scope.user.email}
          </p>
        </div>

        <.user_menu_org_block scope={@scope} memberships={@memberships} />

        <li :if={@platform_admin?} role="presentation" class="border-t border-primary/10 mt-1 pt-1">
          <.link
            navigate={if(@scope.admin_mode?, do: ~p"/admin", else: ~p"/admin-mode")}
            role="menuitem"
            class="flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary"
          >
            <span class="hero-cog-6-tooth h-4 w-4 opacity-80"></span>
            {if(@scope.admin_mode?, do: "System administration", else: "Enter admin mode")}
          </.link>
        </li>

        <li :if={@scope.admin_mode?} role="presentation">
          <.form for={%{}} as={:admin_mode} action={~p"/admin-mode"} method="delete">
            <button
              type="submit"
              role="menuitem"
              class="flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary"
            >
              <span class="hero-lock-closed h-4 w-4 opacity-80"></span>
              Leave admin mode
            </button>
          </.form>
        </li>

        <li role="presentation" class="border-t border-primary/10 mt-1 pt-1">
          <.form for={%{}} as={:session} action={~p"/session"} method="delete">
            <button
              type="submit"
              role="menuitem"
              class="flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary"
            >
              <span class="hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"></span>
              Sign out
            </button>
          </.form>
        </li>
      </div>
    </div>
    """
  end

  attr :scope, :any, required: true
  attr :memberships, :list, required: true

  defp user_menu_org_block(assigns) do
    ~H"""
    <div :if={@scope.organization} role="presentation" class="border-t border-primary/10 mt-1 pt-1">
      <span class="hud-label px-3 py-1 block">ORGANIZATION</span>
      <%= if length(@memberships) > 1 do %>
        <details class="group">
          <summary class="flex items-center justify-between gap-2 px-3 py-2 cursor-pointer text-sm text-base-content list-none">
            <span class="truncate">{@scope.organization.display_name}</span>
            <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform group-open:rotate-180"></span>
          </summary>
          <ul class="mt-1 space-y-0.5">
            <li
              :for={%{organization: other} <- @memberships}
              :if={other.organization_id != @scope.organization.organization_id}
              role="presentation"
            >
              <.form for={%{}} as={:session} action={~p"/session/organization"} method="put">
                <input type="hidden" name="organization_id" value={other.organization_id} />
                <button
                  type="submit"
                  role="menuitem"
                  class="flex w-full items-center gap-2 px-3 py-2 text-xs text-base-content/70 hover:text-primary"
                >
                  <span class="truncate">{other.display_name}</span>
                </button>
              </.form>
            </li>
          </ul>
        </details>
      <% else %>
        <p class="px-3 py-2 text-sm text-base-content truncate">
          {@scope.organization.display_name}
        </p>
      <% end %>
    </div>
    """
  end

  defp display_label(%{display_name: name, email: email}) when name in [nil, ""], do: email
  defp display_label(%{display_name: name}), do: name

  @doc """
  Single-line breadcrumb trail. Items are `{label, path}` tuples; pass
  `nil` for the path to render the segment as plain text (used for the
  final segment, which represents the current page).
  """
  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    assigns = assign(assigns, :last_index, length(assigns.items) - 1)

    ~H"""
    <nav
      aria-label="Breadcrumb"
      class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
    >
      <%= for {{label, path}, index} <- Enum.with_index(@items) do %>
        <span :if={index > 0} class="text-base-content/20" aria-hidden="true">/</span>
        <%= cond do %>
          <% index == @last_index -> %>
            <span class="text-primary/90">{label}</span>
          <% path -> %>
            <.link navigate={path} class="hover:text-primary transition-colors">{label}</.link>
          <% true -> %>
            <span>{label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end

  @doc """
  A sub-page / in-card section header: an optional `eyebrow` label over a
  title and description, with right-aligned `:actions` (a badge or button).

  Distinct from `<.page_header>` (page-level). Set `title_mono` for value-style
  titles (endpoints, IDs) that render in monospace primary. Left-column content
  richer than a plain title (counts, summaries, inline version tags) should stay
  as raw markup.
  """
  attr :eyebrow, :string, default: nil
  attr :title, :string, default: nil
  attr :title_mono, :boolean, default: false
  attr :description, :string, default: nil
  attr :class, :string, default: nil
  slot :actions

  def section_header(assigns) do
    ~H"""
    <div class={["flex items-start justify-between gap-4", @class]}>
      <div>
        <p :if={@eyebrow} class="hud-label mb-2">{@eyebrow}</p>
        <h2 :if={@title} class={["text-lg font-semibold", @title_mono && "font-mono text-primary"]}>
          {@title}
        </h2>
        <p :if={@description} class="mt-1 max-w-2xl text-sm text-base-content/70">{@description}</p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center justify-end gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
