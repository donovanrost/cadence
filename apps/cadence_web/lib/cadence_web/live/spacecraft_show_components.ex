defmodule CadenceWeb.SpacecraftShowComponents do
  @moduledoc """
  Function components used by `CadenceWeb.SpacecraftShowLive` for the
  Spacecraft Profile binding card and the per-application summary section.
  """

  use CadenceWeb, :html

  import CadenceWeb.CommsComponents, only: [status_badge: 1]

  attr :mission_id, :string, required: true
  attr :spacecraft_id, :string, required: true
  attr :type_binding, :any, required: true

  def type_binding_card(assigns) do
    ~H"""
    <section
      id="spacecraft-profile-binding"
      class={[
        "card bg-base-200 border border-base-300 hud-corners",
        type_binding_accent(@type_binding)
      ]}
    >
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div class="space-y-2">
            <p class="hud-label">Spacecraft Profile</p>
            <%= if @type_binding do %>
              <div class="flex items-baseline gap-3">
                <h2 class="text-lg font-semibold">{@type_binding.pinned.display_name}</h2>
                <span class="mc-value-small text-primary/80">v{@type_binding.pinned.version}</span>
              </div>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
                <span class="hud-label text-base-content/40">DOWN</span>
                <span class="font-mono uppercase text-primary/80">
                  {@type_binding.pinned.downlink_protocol}
                </span>
                <span class="text-base-content/30">·</span>
                <span class="hud-label text-base-content/40">UP</span>
                <span class="font-mono uppercase text-primary/80">
                  {@type_binding.pinned.uplink_protocol}
                </span>
              </div>
            <% else %>
              <h2 class="text-lg font-semibold text-base-content/70">No profile selected</h2>
              <p class="text-sm text-base-content/60">
                Select a spacecraft profile to pin a reusable byte-interpretation contract.
              </p>
            <% end %>
          </div>
          <%= cond do %>
            <% is_nil(@type_binding) -> %>
              <.status_badge status={:attention} label="Unbound" />
            <% @type_binding.drift? -> %>
              <.status_badge
                status={:attention}
                label={"Drift · latest v#{@type_binding.latest_version}"}
              />
            <% true -> %>
              <.status_badge status={:ready} label="Current" />
          <% end %>
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
      </div>
    </section>
    """
  end

  defp type_binding_accent(nil), do: "border-l-2 border-l-warning/60"
  defp type_binding_accent(%{drift?: true}), do: "border-l-2 border-l-warning/60"
  defp type_binding_accent(_), do: "border-l-2 border-l-success/60"

  attr :type_binding, :any, required: true
  attr :telemetry_decom_status, :atom, required: true

  def applications_card(assigns) do
    ~H"""
    <section :if={@type_binding} id="spacecraft-applications" class="card bg-base-200">
      <div class="card-body p-6 space-y-3">
        <p class="hud-label">Applications</p>
        <p class="text-sm text-base-content/60">
          Platform applications enabled by this spacecraft's profile. Per-application configuration is set per spacecraft.
        </p>
        <%= if map_size(@type_binding.pinned.applications) == 0 do %>
          <p class="text-sm text-base-content/50">No applications enabled by this profile.</p>
        <% else %>
          <div class="grid gap-3 md:grid-cols-2">
            <div
              :for={{app_key, _config} <- Enum.sort(@type_binding.pinned.applications)}
              class="rounded border border-base-300 bg-base-100/40 p-4"
            >
              <p class="font-medium">{humanize_application_key(app_key)}</p>
              <p class="mt-1 text-xs text-base-content/60">
                {application_status_hint(app_key, @telemetry_decom_status)}
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp humanize_application_key(key) when is_atom(key),
    do: humanize_application_key(Atom.to_string(key))

  defp humanize_application_key(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp application_status_hint(:telemetry_decom, status), do: telemetry_decom_status_hint(status)
  defp application_status_hint(_other, _status), do: "Coming soon."

  defp telemetry_decom_status_hint(:applied), do: "Configured and live."
  defp telemetry_decom_status_hint(:configured), do: "Configured. Not yet applied."
  defp telemetry_decom_status_hint(:outdated), do: "Configured but out of date."
  defp telemetry_decom_status_hint(:disabled), do: "Disabled for this spacecraft."
  defp telemetry_decom_status_hint(:not_configured), do: "Not configured yet."
end
