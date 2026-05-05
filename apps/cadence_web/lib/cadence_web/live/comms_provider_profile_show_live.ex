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
      <div class="flex items-start justify-between gap-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
            class="text-sm text-primary hover:underline"
          >
            &larr; Providers
          </.link>
          <h1 class="mt-1 text-2xl font-bold text-base-content">
            {display_name(@provider_profile, :provider_profile_id)}
          </h1>
          <p class="mt-1 font-mono text-xs text-base-content/50">
            {@provider_profile.provider_profile_id} · v{@provider_profile.version}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <button
            id="archive-provider-profile-button"
            type="button"
            phx-click="archive"
            data-confirm="Archive this provider?"
            class="btn btn-error btn-outline btn-sm"
          >
            Archive
          </button>
          <.link
            id="new-provider-profile-version-link"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/providers/#{@provider_profile.provider_profile_id}/new-version"
            }
            class="btn btn-primary btn-sm"
          >
            New Version
          </.link>
        </div>
      </div>

      <section
        :if={@linked_path_count > 0}
        id="provider-profile-archive-blocker"
        class="rounded border border-warning/30 bg-warning/10 p-4 text-sm"
      >
        <p class="hud-label mb-2 text-warning">Archive Blocked By Active Paths</p>
        <p>
          This provider is referenced by {@linked_path_count} active link template(s):
          {Enum.join(@linked_path_names, ", ")}.
        </p>
      </section>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200">
          <div class="card-body p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">TCP Provider</p>
                <h2 class="text-lg font-semibold">{tcp_endpoint(@provider_profile.configuration)}</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Runtime adapter configuration used by link templates and scheduled contacts.
                </p>
              </div>
              <.status_badge status={:info} label={human_atom(@provider_profile.adapter_key)} />
            </div>

            <div class="mt-6 divide-y divide-base-300">
              <.profile_detail label="Mode" value={tcp_mode(@provider_profile.configuration)} />
              <.profile_detail label="Direction" value={tcp_direction(@provider_profile.configuration)} />
              <.profile_detail label="Framing" value={tcp_framing(@provider_profile.configuration)} />
              <.profile_detail label="TLS" value={tls_label(@provider_profile.configuration)} />
              <.profile_detail label="Reconnect" value={reconnect_label(@provider_profile.configuration)} />
              <.profile_detail label="Linked paths" value={Integer.to_string(@linked_path_count)} />
            </div>

            <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
              <summary class="cursor-pointer hud-label">Raw Configuration</summary>
              <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(@provider_profile.configuration, pretty: true)}</pre>
            </details>
          </div>
        </section>

        <aside class="card bg-base-200 border border-base-300">
          <div class="card-body p-5">
            <p class="hud-label mb-2">Version History</p>
            <div id="provider-profile-versions" class="space-y-3">
              <div :for={version <- @versions} class="flex items-center justify-between border-b border-base-300 pb-2 last:border-b-0">
                <span class="font-mono">v{version.version}</span>
                <span class="text-xs text-base-content/60">
                  {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
                </span>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp profile_detail(assigns) do
    ~H"""
    <div class="grid gap-2 py-3 sm:grid-cols-[12rem_1fr]">
      <div class="hud-label text-base-content/50">{@label}</div>
      <div class="text-sm text-base-content">{@value}</div>
    </div>
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
