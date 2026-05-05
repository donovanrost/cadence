defmodule CadenceWeb.CommsTransportProfileShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(%{"transport_profile_id" => transport_profile_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_transport_profile(
           scope.organization_id,
           mission.mission_id,
           transport_profile_id
         ) do
      {:ok, transport_profile} ->
        versions =
          Cadence.list_transport_profile_versions(
            scope.organization_id,
            mission.mission_id,
            transport_profile_id
          )

        path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

        {:ok,
         socket
         |> assign(:page_title, display_name(transport_profile, :transport_profile_id))
         |> assign(:nav_item, :comms)
         |> assign(:transport_profile, transport_profile)
         |> assign(:versions, versions)
         |> assign(:linked_path_count, linked_path_count(transport_profile, path_templates))
         |> assign(:linked_path_names, linked_path_names(transport_profile, path_templates))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Transport profile not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors")}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    %{
      current_scope: scope,
      current_mission: mission,
      transport_profile: transport_profile,
      linked_path_count: linked_path_count
    } = socket.assigns

    if linked_path_count > 0 do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Protocol behavior is still referenced by active link templates. Archive or update those templates first."
       )}
    else
      case Cadence.delete_transport_profile(
             scope.organization_id,
             mission.mission_id,
             transport_profile.transport_profile_id,
             %{"archived_from_ui" => true}
           ) do
        {:ok, _transport_profile} ->
          {:noreply,
           socket
           |> put_flash(:info, "Transport profile archived.")
           |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-transport-profile-show-page" class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors"}
            class="text-sm text-primary hover:underline"
          >
            &larr; Protocol Behaviors
          </.link>
          <h1 class="mt-1 text-2xl font-bold text-base-content">
            {display_name(@transport_profile, :transport_profile_id)}
          </h1>
          <p class="mt-1 font-mono text-xs text-base-content/50">
            {@transport_profile.transport_profile_id} · v{@transport_profile.version}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <button
            id="archive-transport-profile-button"
            type="button"
            phx-click="archive"
            data-confirm="Archive this protocol behavior?"
            class="btn btn-error btn-outline btn-sm"
          >
            Archive
          </button>
          <.link
            id="new-transport-profile-version-link"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors/#{@transport_profile.transport_profile_id}/new-version"
            }
            class="btn btn-primary btn-sm"
          >
            New Version
          </.link>
        </div>
      </div>

      <section
        :if={@linked_path_count > 0}
        id="transport-profile-archive-blocker"
        class="rounded border border-warning/30 bg-warning/10 p-4 text-sm"
      >
        <p class="hud-label mb-2 text-warning">Archive Blocked By Active Paths</p>
        <p>
          This protocol behavior is referenced by {@linked_path_count} active link template(s):
          {Enum.join(@linked_path_names, ", ")}.
        </p>
      </section>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200">
          <div class="card-body p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">{family_title(@transport_profile)}</p>
                <h2 class="text-lg font-semibold">{transport_summary(@transport_profile)}</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Link-local protocol behavior used when reusable link templates are realized.
                </p>
              </div>
              <.status_badge status={:info} label={human_atom(@transport_profile.target_scope)} />
            </div>

            <div class="mt-6 divide-y divide-base-300">
              <.transport_detail label="Family" value={human_atom(@transport_profile.family_key)} />
              <.transport_detail label="Target scope" value={human_atom(@transport_profile.target_scope)} />
              <.transport_detail label="Linked paths" value={Integer.to_string(@linked_path_count)} />
              <.transport_detail :for={detail <- transport_details(@transport_profile)} label={detail.label} value={detail.value} />
            </div>

            <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
              <summary class="cursor-pointer hud-label">Raw Configuration</summary>
              <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(@transport_profile.configuration, pretty: true)}</pre>
            </details>
          </div>
        </section>

        <aside class="card bg-base-200 border border-base-300">
          <div class="card-body p-5">
            <p class="hud-label mb-2">Version History</p>
            <div id="transport-profile-versions" class="space-y-3">
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

  defp transport_detail(assigns) do
    ~H"""
    <div class="grid gap-2 py-3 sm:grid-cols-[12rem_1fr]">
      <div class="hud-label text-base-content/50">{@label}</div>
      <div class="text-sm text-base-content">{@value}</div>
    </div>
    """
  end

  defp linked_path_count(transport_profile, path_templates) do
    Enum.count(path_templates, fn template ->
      transport_profile.transport_profile_id in template.transport_profile_ids
    end)
  end

  defp linked_path_names(transport_profile, path_templates) do
    path_templates
    |> Enum.filter(fn template ->
      transport_profile.transport_profile_id in template.transport_profile_ids
    end)
    |> Enum.map(&display_name(&1, :path_id))
  end

  defp family_title(%{family_key: :heartbeat_monitor}), do: "Heartbeat Monitor"
  defp family_title(%{family_key: :uplink_gateway}), do: "Uplink Gateway"
  defp family_title(%{family_key: family_key}), do: human_atom(family_key)

  defp transport_summary(%{family_key: :heartbeat_monitor, configuration: configuration}) do
    "Heartbeat every #{Map.get(configuration, "heartbeat_interval_ms", "unknown")} ms"
  end

  defp transport_summary(%{family_key: :uplink_gateway, configuration: configuration}) do
    scid =
      case Map.get(configuration, "scid") do
        nil -> "path spacecraft"
        value -> "SCID #{value}"
      end

    "TC frames · #{scid} · VCID #{Map.get(configuration, "vcid", 0)}"
  end

  defp transport_summary(%{family_key: family_key}), do: human_atom(family_key)

  defp transport_details(%{family_key: :heartbeat_monitor, configuration: configuration}) do
    [
      %{
        label: "Heartbeat interval",
        value: "#{Map.get(configuration, "heartbeat_interval_ms")} ms"
      }
    ]
  end

  defp transport_details(%{family_key: :uplink_gateway, configuration: configuration}) do
    [
      %{label: "Service name", value: optional_label(Map.get(configuration, "service_name"))},
      %{label: "Transport profile", value: Map.get(configuration, "transport_profile", "tc")},
      %{label: "Frame size", value: "#{Map.get(configuration, "frame_size", 32)} bytes"},
      %{
        label: "SCID",
        value: optional_label(Map.get(configuration, "scid"), "Derived from path")
      },
      %{label: "VCID", value: string_value(Map.get(configuration, "vcid", 0))},
      %{label: "Bypass flag", value: string_value(Map.get(configuration, "bypass_flag", 0))},
      %{
        label: "Control command flag",
        value: string_value(Map.get(configuration, "control_command_flag", 0))
      },
      %{
        label: "Segment header flag",
        value: string_value(Map.get(configuration, "segment_header_flag", 0))
      },
      %{
        label: "Initial frame sequence",
        value: string_value(Map.get(configuration, "initial_frame_seq", 0))
      },
      %{
        label: "COP-1 mode",
        value: configuration |> Map.get("cop1_mode", "disabled") |> String.upcase()
      },
      %{label: "COP-1 timeout", value: "#{Map.get(configuration, "cop1_timeout_ms", 5000)} ms"},
      %{
        label: "COP-1 max retransmit",
        value: string_value(Map.get(configuration, "cop1_max_retransmit", 3))
      },
      %{
        label: "Start delay",
        value: optional_label(Map.get(configuration, "simulated_start_delay_ms"), "None")
      },
      %{
        label: "Completion delay",
        value: optional_label(Map.get(configuration, "simulated_completion_delay_ms"), "None")
      }
    ]
  end

  defp transport_details(_transport_profile), do: []

  defp optional_label(value, fallback \\ "Not set")
  defp optional_label(nil, fallback), do: fallback
  defp optional_label("", fallback), do: fallback
  defp optional_label(value, _fallback), do: string_value(value)

  defp string_value(nil), do: ""
  defp string_value(value), do: to_string(value)
end
