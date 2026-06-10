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
      <.page_header
        title={@profile.display_name}
        back_label="Spacecraft Profiles"
        back_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"}
      >
        <:title_suffix>
          <span class="mc-value-medium text-primary/80">v{@profile.version}</span>
          <span class="hud-label text-base-content/40">{@profile.lifecycle_state}</span>
        </:title_suffix>
      </.page_header>

      <.byte_interpretation_card profile={@profile} />

      <.applications_card profile={@profile} />

      <.version_history versions={@versions} />
    </div>
    """
  end

  attr :profile, :any, required: true

  defp byte_interpretation_card(assigns) do
    ~H"""
    <.card title="Byte Interpretation">
      <div class="mt-5 grid gap-x-8 gap-y-2 md:grid-cols-2">
        <.detail_row label="Downlink Protocol">
          <span class="uppercase">{@profile.downlink_protocol}</span>
        </.detail_row>
        <.detail_row label="Uplink Protocol">
          <span class="uppercase">{@profile.uplink_protocol}</span>
        </.detail_row>
        <.detail_row label="Packet Protocol" value={to_string(@profile.packet_protocol)} />
        <.detail_row label="Lifecycle" value={to_string(@profile.lifecycle_state)} />
      </div>

      <div :if={map_size(@profile.frame_parameters) > 0} class="mt-5">
        <div class="hud-divider"></div>
        <p class="hud-label mb-3">Frame Parameters</p>
        <div class="grid gap-x-8 gap-y-1 md:grid-cols-2">
          <.detail_row
            :for={{key, value} <- Enum.sort(@profile.frame_parameters)}
            label={humanize(key)}
            value={format_value(value)}
          />
        </div>
      </div>
    </.card>
    """
  end

  attr :profile, :any, required: true

  defp applications_card(assigns) do
    ~H"""
    <.card title="Applications">
      <%= if map_size(@profile.applications) > 0 do %>
        <ul class="mt-4 space-y-2">
          <li
            :for={{key, _config} <- Enum.sort(@profile.applications)}
            class="flex items-center gap-3 rounded border border-base-300 bg-base-100/40 p-3 text-sm border-l-2 border-l-primary/60"
          >
            <.icon name="hero-bolt" class="h-4 w-4 text-primary/70" />
            <span class="font-medium">{humanize(key)}</span>
          </li>
        </ul>
      <% else %>
        <p class="mt-4 text-sm text-base-content/40 italic">No applications enabled.</p>
      <% end %>
    </.card>
    """
  end

  attr :versions, :list, required: true

  defp version_history(assigns) do
    ~H"""
    <.card :if={length(@versions) > 1} title="Version History">
      <.table
        id="spacecraft-profile-version-history"
        rows={@versions}
        row_accent={false}
        class="mt-3"
      >
        <:col :let={version} label="Version" mono>v{version.version}</:col>
        <:col :let={version} label="Lifecycle" mono class="text-base-content/60">
          {version.lifecycle_state}
        </:col>
        <:col :let={version} label="Downlink" mono class="uppercase text-primary/80">
          {version.downlink_protocol}
        </:col>
        <:col :let={version} label="Uplink" mono class="uppercase text-primary/80">
          {version.uplink_protocol}
        </:col>
      </.table>
    </.card>
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
