defmodule CadenceWeb.SpacecraftShowComponents do
  @moduledoc """
  Function components used by `CadenceWeb.SpacecraftShowLive` for the
  Spacecraft Profile binding card and the per-application summary section.
  """

  use CadenceWeb, :html

  attr :mission_id, :string, required: true
  attr :spacecraft_id, :string, required: true
  attr :type_binding, :any, required: true

  def type_binding_card(assigns) do
    ~H"""
    <.card id="spacecraft-profile-binding">
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-2">
          <p class="hud-label">Spacecraft Profile</p>
          <.type_binding_summary type_binding={@type_binding} />
        </div>
        <.type_binding_badge type_binding={@type_binding} />
      </div>

      <div class="mt-5 flex gap-4 text-sm border-t border-base-300/50 pt-4">
        <.link
          :if={@type_binding}
          navigate={
            ~p"/missions/#{@mission_id}/spacecraft/profiles/#{@type_binding.pinned.spacecraft_type_id}"
          }
          class="text-primary hover:underline"
        >
          View profile &rarr;
        </.link>
        <.link
          navigate={~p"/missions/#{@mission_id}/spacecraft/#{@spacecraft_id}/identity"}
          class="text-primary hover:underline"
        >
          {if @type_binding, do: "Change profile", else: "Select profile"}
        </.link>
      </div>
    </.card>
    """
  end

  attr :type_binding, :any, required: true

  defp type_binding_summary(%{type_binding: nil} = assigns) do
    ~H"""
    <h2 class="text-lg font-semibold text-base-content/70">No profile selected</h2>
    <p class="text-sm text-base-content/70">
      Select a spacecraft profile to pin a reusable byte-interpretation contract.
    </p>
    """
  end

  defp type_binding_summary(assigns) do
    ~H"""
    <div class="flex items-baseline gap-3">
      <h2 class="text-lg font-semibold">{@type_binding.pinned.display_name}</h2>
      <span class="mc-value-small text-base-content">v{@type_binding.pinned.version}</span>
    </div>
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
      <span class="hud-label">DOWN</span>
      <span class="font-mono uppercase text-primary/80">
        {@type_binding.pinned.downlink_protocol}
      </span>
      <span class="text-base-content/30">·</span>
      <span class="hud-label">UP</span>
      <span class="font-mono uppercase text-primary/80">
        {@type_binding.pinned.uplink_protocol}
      </span>
    </div>
    """
  end

  attr :type_binding, :any, required: true

  defp type_binding_badge(%{type_binding: nil} = assigns) do
    ~H"""
    <.status_badge status={:attention} label="Unbound" />
    """
  end

  defp type_binding_badge(%{type_binding: %{drift?: true}} = assigns) do
    ~H"""
    <.status_badge status={:attention} label={"Drift · latest v#{@type_binding.latest_version}"} />
    """
  end

  defp type_binding_badge(assigns) do
    ~H"""
    <.status_badge status={:ready} label="Current" />
    """
  end

  attr :type_binding, :any, required: true
  attr :applications, :any, required: true
  attr :applications_empty?, :boolean, required: true
  attr :mission_id, :string, required: true
  attr :spacecraft_id, :string, required: true

  def applications_card(assigns) do
    ~H"""
    <.card
      :if={@type_binding || not @applications_empty?}
      id="spacecraft-applications"
      title="Applications"
    >
      <div class="mt-3 space-y-3">
        <p :if={@type_binding} class="text-sm text-base-content/70">
          Platform applications enabled by this spacecraft's profile. Per-application configuration is set per spacecraft.
        </p>
        <p :if={is_nil(@type_binding)} class="text-sm text-base-content/70">
          Retained spacecraft installations. Select a profile to restore desired application declarations.
        </p>
        <%= if @applications_empty? do %>
          <.empty_state compact title="No applications enabled by this profile." />
        <% else %>
          <div
            id="spacecraft-profile-applications"
            class="grid gap-3 md:grid-cols-2"
            phx-update="stream"
          >
            <div
              :for={{dom_id, application} <- @applications}
              id={dom_id}
              class="rounded border border-base-300 bg-base-100/40 p-4"
            >
              <div class="flex items-start justify-between gap-3">
                <p class="font-medium">{application.display_name}</p>
                <.link
                  :if={application.manageable?}
                  navigate={
                    ~p"/missions/#{@mission_id}/spacecraft/#{@spacecraft_id}/applications/#{application.application_key}"
                  }
                  class="text-xs text-primary hover:underline"
                >
                  Manage
                </.link>
              </div>
              <div class="mt-2">
                <.status_badge status={application.status.tone} label={application.status.label} />
              </div>
            </div>
          </div>
        <% end %>
        <.link
          navigate={~p"/missions/#{@mission_id}/spacecraft/#{@spacecraft_id}/applications"}
          class="mt-3 inline-flex text-sm text-primary hover:underline"
        >
          View applications &rarr;
        </.link>
      </div>
    </.card>
    """
  end
end
