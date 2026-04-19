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
    <div class="fixed top-5 right-5 max-md:top-auto max-md:bottom-3 max-md:left-3 max-md:right-3 z-[3] grid gap-3">
      <p
        :if={info = Phoenix.Flash.get(@flash, :info)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-[rgba(147,242,200,0.24)] rounded-[1rem] bg-[rgba(6,12,19,0.92)] shadow-[0_28px_90px_rgba(0,0,0,0.42)]"
      >
        {info}
      </p>
      <p
        :if={error = Phoenix.Flash.get(@flash, :error)}
        class="m-0 min-w-[16rem] max-w-[min(24rem,calc(100vw-2rem))] max-md:min-w-0 py-[0.9rem] px-4 border border-[rgba(255,142,133,0.32)] rounded-[1rem] bg-[rgba(6,12,19,0.92)] shadow-[0_28px_90px_rgba(0,0,0,0.42)]"
      >
        {error}
      </p>
    </div>
    """
  end

  @doc """
  Bell icon with unread badge and recent-notifications dropdown.

  Attrs:
    * `count` — unread count (integer)
    * `notifications` — list of `%Cadence.Notifications.Notification{}` (top 5)
  """
  attr :count, :integer, default: 0
  attr :notifications, :list, default: []

  def notifications_bell(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-circle relative" aria-label="Notifications">
        <span class="hero-bell h-5 w-5"></span>
        <%= if @count > 0 do %>
          <span class="badge badge-primary badge-xs absolute -top-0.5 -right-0.5 font-mono">
            {format_count(@count)}
          </span>
        <% end %>
      </div>
      <div
        tabindex="0"
        class="dropdown-content menu bg-base-200 z-[100] w-80 p-2 shadow-lg border border-primary/20 max-h-96 overflow-y-auto"
      >
        <li class="menu-title px-3 py-2">
          <span class="hud-label text-base-content/60">
            Notifications
            <%= if @count > 0 do %>
              <span class="text-primary">({@count} unread)</span>
            <% end %>
          </span>
        </li>
        <%= if @notifications == [] do %>
          <li class="px-3 py-4 text-center text-sm text-base-content/50">
            No notifications
          </li>
        <% else %>
          <li :for={n <- @notifications}>
            <.link navigate={~p"/notifications"} class="flex items-start gap-2 px-3 py-2">
              <span :if={is_nil(n.read_at)} class="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
              <span :if={n.read_at} class="mt-1.5 w-1.5 h-1.5 flex-shrink-0"></span>
              <span class="flex-1 min-w-0">
                <span class="block text-xs font-semibold text-base-content truncate">{n.title}</span>
                <span :if={n.body} class="block text-xs text-base-content/50 truncate">{n.body}</span>
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
    * `scope` — `%Cadence.Auth.Scope{}` with `:user` and optional `:organization`
    * `memberships` — list of `%{membership: OrganizationMembership.t(), organization: Organization.t()}`
    * `platform_admin?` — boolean
  """
  attr :scope, :any, required: true
  attr :memberships, :list, default: []
  attr :platform_admin?, :boolean, default: false

  def user_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button type="button" tabindex="0" class="btn btn-ghost btn-sm gap-1" aria-haspopup="menu">
        <span class="text-xs text-base-content/60">{@scope.user.display_name}</span>
        <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform"></span>
      </button>

      <div
        tabindex="0"
        role="menu"
        class="dropdown-content menu bg-base-200 z-[100] w-72 p-2 shadow-lg border border-primary/20"
      >
        <li role="presentation" class="px-3 py-2">
          <p class="text-sm font-semibold text-base-content">{@scope.user.display_name}</p>
          <p class="text-xs text-base-content/50 truncate">{@scope.user.email}</p>
        </li>

        <.user_menu_org_block scope={@scope} memberships={@memberships} />

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
    <li :if={@scope.organization} role="presentation" class="border-t border-primary/10 mt-1 pt-1">
      <span class="hud-label text-base-content/60 px-3 py-1 block">ORGANIZATION</span>
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
    </li>
    """
  end
end
