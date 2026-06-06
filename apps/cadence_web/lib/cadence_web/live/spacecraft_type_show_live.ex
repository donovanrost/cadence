defmodule CadenceWeb.SpacecraftTypeShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"profile_id" => profile_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.fetch_spacecraft_type(organization_id, mission.mission_id, profile_id) do
      {:ok, profile} ->
        versions =
          Cadence.list_spacecraft_type_versions(
            organization_id,
            mission.mission_id,
            profile.spacecraft_type_id
          )

        {:ok,
         socket
         |> assign(:page_title, profile.display_name)
         |> assign(:nav_item, :spacecraft)
         |> assign(:profile, profile)
         |> assign(:versions, versions)}

      {:error, :spacecraft_type_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Spacecraft profile not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/spacecraft/profiles")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="border-b border-primary/20 pb-4">
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"}
          class="hud-label text-base-content/50 hover:text-primary"
        >
          &larr; Spacecraft Profiles
        </.link>
        <div class="mt-2 flex items-baseline gap-3">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            {@profile.display_name}
          </h1>
          <span class="mc-value-medium text-primary/80">v{@profile.version}</span>
          <span class="hud-label text-base-content/40">{@profile.lifecycle_state}</span>
        </div>
      </div>

      <section class="card bg-base-200 border border-base-300 hud-corners">
        <div class="card-body space-y-5 p-6">
          <p class="hud-label">Byte Interpretation</p>

          <div class="grid gap-x-8 gap-y-2 md:grid-cols-2">
            <div class="hud-data-row">
              <span class="hud-data-label">Downlink Protocol</span>
              <span class="hud-data-value uppercase">{@profile.downlink_protocol}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Uplink Protocol</span>
              <span class="hud-data-value uppercase">{@profile.uplink_protocol}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Packet Protocol</span>
              <span class="hud-data-value">{@profile.packet_protocol}</span>
            </div>
            <div class="hud-data-row">
              <span class="hud-data-label">Lifecycle</span>
              <span class="hud-data-value">{@profile.lifecycle_state}</span>
            </div>
          </div>

          <div :if={map_size(@profile.frame_parameters) > 0}>
            <div class="hud-divider"></div>
            <p class="hud-label mb-3">Frame Parameters</p>
            <div class="grid gap-x-8 gap-y-1 md:grid-cols-2">
              <div :for={{key, value} <- Enum.sort(@profile.frame_parameters)} class="hud-data-row">
                <span class="hud-data-label">{humanize(key)}</span>
                <span class="hud-data-value">{format_value(value)}</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="card bg-base-200 border border-base-300 hud-corners">
        <div class="card-body space-y-4 p-6">
          <p class="hud-label">Applications</p>
          <%= if map_size(@profile.applications) > 0 do %>
            <ul class="space-y-2">
              <li
                :for={{key, _config} <- Enum.sort(@profile.applications)}
                class="flex items-center gap-3 rounded border border-base-300 bg-base-100/40 p-3 text-sm border-l-2 border-l-primary/60"
              >
                <.icon name="hero-bolt" class="h-4 w-4 text-primary/70" />
                <span class="font-medium">{humanize(key)}</span>
              </li>
            </ul>
          <% else %>
            <p class="text-sm text-base-content/40 italic">No applications enabled.</p>
          <% end %>
        </div>
      </section>

      <section :if={length(@versions) > 1} class="card bg-base-200 border border-base-300">
        <div class="card-body space-y-3 p-6">
          <p class="hud-label">Version History</p>
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Version</th>
                <th class="hud-label">Lifecycle</th>
                <th class="hud-label">Downlink</th>
                <th class="hud-label">Uplink</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={version <- @versions}>
                <td class="font-mono">v{version.version}</td>
                <td class="font-mono text-base-content/60">{version.lifecycle_state}</td>
                <td class="font-mono uppercase text-primary/80">{version.downlink_protocol}</td>
                <td class="font-mono uppercase text-primary/80">{version.uplink_protocol}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  defp humanize(key) when is_atom(key), do: humanize(Atom.to_string(key))

  defp humanize(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(true), do: "yes"
  defp format_value(false), do: "no"
  defp format_value(value), do: inspect(value)
end
