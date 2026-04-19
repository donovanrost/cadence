defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

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
            <a href="/notifications" class="flex items-start gap-2 px-3 py-2">
              <span :if={is_nil(n.read_at)} class="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
              <span :if={n.read_at} class="mt-1.5 w-1.5 h-1.5 flex-shrink-0"></span>
              <span class="flex-1 min-w-0">
                <span class="block text-xs font-semibold text-base-content truncate">{n.title}</span>
                <span :if={n.body} class="block text-xs text-base-content/50 truncate">{n.body}</span>
              </span>
            </a>
          </li>
        <% end %>
        <li class="border-t border-primary/10 mt-1 pt-1">
          <a href="/notifications" class="text-xs text-primary uppercase tracking-wide">
            See all notifications
          </a>
        </li>
      </div>
    </div>
    """
  end

  defp format_count(n) when n > 9, do: "9+"
  defp format_count(n), do: Integer.to_string(n)
end
