defmodule CadenceWeb.CommsProviderProfileShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(%{"provider_profile_id" => provider_profile_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_provider_profile(
           scope.organization_id,
           mission.mission_id,
           provider_profile_id
         ) do
      {:ok, provider_profile} ->
        versions =
          Cadence.list_provider_profile_versions(
            scope.organization_id,
            mission.mission_id,
            provider_profile_id
          )

        path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

        {:ok,
         socket
         |> assign(:page_title, display_name(provider_profile, :provider_profile_id))
         |> assign(:nav_item, :comms_providers)
         |> assign(:provider_profile, provider_profile)
         |> assign(:versions, versions)
         |> assign(:linked_path_count, linked_path_count(provider_profile, path_templates))
         |> assign(:linked_path_names, linked_path_names(provider_profile, path_templates))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Provider profile not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/providers")}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    %{
      current_scope: scope,
      current_mission: mission,
      provider_profile: provider_profile,
      linked_path_count: linked_path_count
    } = socket.assigns

    if linked_path_count > 0 do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Provider is still referenced by active link templates. Archive or update those templates first."
       )}
    else
      case Cadence.delete_provider_profile(
             scope.organization_id,
             mission.mission_id,
             provider_profile.provider_profile_id,
             %{"archived_from_ui" => true}
           ) do
        {:ok, _provider_profile} ->
          {:noreply,
           socket
           |> put_flash(:info, "Provider profile archived.")
           |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/providers")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-profile-show-page" class="space-y-6">
      <.page_header
        title={display_name(@provider_profile, :provider_profile_id)}
        subtitle={@provider_profile.provider_profile_id}
        back_label="Providers"
        back_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
      >
        <:title_suffix>v{@provider_profile.version}</:title_suffix>
        <:actions>
          <.button
            id="archive-provider-profile-button"
            variant={:danger}
            phx-click="archive"
            data-confirm="Archive this provider?"
          >
            Archive
          </.button>
          <.button
            id="new-provider-profile-version-link"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/providers/#{@provider_profile.provider_profile_id}/new-version"
            }
          >
            New Version
          </.button>
        </:actions>
      </.page_header>

      <%!-- One-off warning callout (warning tint + dashed-free chrome); kept raw. --%>
      <section
        :if={@linked_path_count > 0}
        id="provider-profile-archive-blocker"
        class="rounded border border-warning/30 bg-warning/10 p-4 text-sm border-l-2 border-l-warning/60"
      >
        <p class="hud-label mb-2 text-warning">Archive Blocked By Active Paths</p>
        <p>
          This provider is referenced by {@linked_path_count} active link template(s):
          {Enum.join(@linked_path_names, ", ")}.
        </p>
      </section>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <.endpoint_card provider_profile={@provider_profile} linked_path_count={@linked_path_count} />
        <.version_history_card versions={@versions} />
      </div>
    </div>
    """
  end

  attr :provider_profile, :map, required: true
  attr :linked_path_count, :integer, required: true

  defp endpoint_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">Endpoint</p>
          <h2 class="font-mono text-lg font-semibold text-primary">
            {tcp_endpoint(@provider_profile.configuration)}
          </h2>
          <p class="mt-1 text-sm text-base-content/60">
            Transport adapter configuration used to move bytes between Cadence and the ground network.
          </p>
        </div>
        <.status_badge status={:info} label={human_atom(@provider_profile.adapter_key)} />
      </div>

      <div class="mt-6 space-y-1">
        <.detail_row label="Mode" value={tcp_mode(@provider_profile.configuration)} />
        <.detail_row label="Direction" value={tcp_direction(@provider_profile.configuration)} />
        <.detail_row label="Framing" value={tcp_framing(@provider_profile.configuration)} />
        <.detail_row label="TLS" value={tls_label(@provider_profile.configuration)} />
        <.detail_row label="Reconnect" value={reconnect_label(@provider_profile.configuration)} />
        <.detail_row label="Linked paths" value={Integer.to_string(@linked_path_count)} />
      </div>

      <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
        <summary class="cursor-pointer hud-label hover:text-primary">
          Raw Configuration
        </summary>
        <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(@provider_profile.configuration, pretty: true)}</pre>
      </details>
    </.card>
    """
  end

  attr :versions, :list, required: true

  defp version_history_card(assigns) do
    ~H"""
    <.card title="Version History">
      <div id="provider-profile-versions" class="space-y-1">
        <.detail_row :for={version <- @versions} label={"v#{version.version}"}>
          <span class="text-xs">
            {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
          </span>
        </.detail_row>
      </div>
    </.card>
    """
  end

  defp linked_path_count(provider_profile, path_templates) do
    Enum.count(path_templates, fn template ->
      provider_profile.provider_profile_id in template.provider_profile_ids
    end)
  end

  defp linked_path_names(provider_profile, path_templates) do
    path_templates
    |> Enum.filter(fn template ->
      provider_profile.provider_profile_id in template.provider_profile_ids
    end)
    |> Enum.map(&display_name(&1, :path_id))
  end

  defp tcp_endpoint(configuration) do
    host = Map.get(configuration, "host", "unknown")
    port = Map.get(configuration, "port", "unknown")
    "#{host}:#{port}"
  end

  defp tcp_mode(configuration), do: configuration |> Map.get("mode", "unknown") |> String.upcase()

  defp tcp_direction(configuration),
    do: configuration |> Map.get("direction", "unknown") |> String.upcase()

  defp tcp_framing(configuration) do
    framing = Map.get(configuration, "framing", %{})

    case Map.get(framing, "mode", "raw") do
      "fixed_size" ->
        size =
          Map.get(framing, "fixed_message_bytes") || Map.get(configuration, "fixed_message_bytes")

        "FIXED SIZE · #{size} bytes"

      mode ->
        String.upcase(String.replace(mode, "_", " "))
    end
  end

  defp tls_label(configuration) do
    case get_in(configuration, ["tls", "enabled"]) do
      true -> "ENABLED"
      _other -> "DISABLED"
    end
  end

  defp reconnect_label(configuration) do
    configuration
    |> get_in(["reconnect", "policy"])
    |> Kernel.||("none")
    |> String.replace("_", " ")
    |> String.upcase()
  end
end
