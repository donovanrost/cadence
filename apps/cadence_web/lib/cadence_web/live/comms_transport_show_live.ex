defmodule CadenceWeb.CommsTransportShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportKind
  alias Cadence.Comms.TransportStore

  @impl true
  def mount(%{"transport_id" => transport_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case TransportStore.fetch_transport(
           scope.organization_id,
           mission.mission_id,
           transport_id
         ) do
      {:ok, transport} ->
        versions =
          TransportStore.list_transport_versions(
            scope.organization_id,
            mission.mission_id,
            transport.transport_id
          )

        {:ok,
         socket
         |> assign(:page_title, transport.display_name)
         |> assign(:nav_item, :comms_transports)
         |> assign(:navigation, navigation_dto(mission, transport))
         |> assign(:transport_details, transport_dto(transport))
         |> assign(:version_history, version_history_dto(versions))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Transport not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/transports")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-transport-show-page">
        <.vue
          id="comms-transport-show-component"
          v-component="FederatedFullPageSurface"
          application_key="comms"
          surface_id="transport"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp navigation_dto(mission, transport) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{
          label: "Transports",
          href: ~p"/missions/#{mission.mission_id}/comms/transports"
        },
        %{label: transport.display_name, href: nil}
      ]
    }
  end

  defp transport_dto(transport) do
    summary = transport_summary(transport)

    %{
      display_name: transport.display_name,
      transport_id: transport.transport_id,
      origin_badge: %{
        id: "transport-origin-badge",
        label: origin_label(transport.origin)
      },
      version: "v#{transport.version}",
      summary_tiles: [
        summary_tile("transport-origin-summary", "Origin", origin_label(transport.origin)),
        summary_tile("transport-provider-summary", "Provider", provider_label(transport)),
        summary_tile("transport-operator-summary", "Delivery", operator_summary(transport)),
        summary_tile("transport-readiness-summary", "Readiness", readiness_label(transport))
      ],
      capability: %{
        eyebrow: "Byte-Moving Capability",
        endpoint: summary.endpoint,
        description:
          "Durable transport setup. Runtime Links and Contacts are realized later under execution context.",
        kind: human_atom(transport.transport_kind),
        details: capability_details(transport, summary),
        diagnostics: %{
          id: "transport-admin-diagnostics",
          json_id: "transport-admin-diagnostics-json",
          label: "Administrator Diagnostics",
          json: diagnostics_json(transport)
        }
      }
    }
  end

  defp summary_tile(id, label, value), do: %{id: id, label: label, value: value}

  defp capability_details(transport, summary) do
    [detail("Origin", origin_label(transport.origin))] ++
      provider_details(transport) ++
      [
        detail("Direction Capability", human_text(summary.direction_capability)),
        detail("Mode", human_text(summary.mode)),
        detail("Framing", human_text(summary.framing)),
        detail("TLS", if(summary.tls_enabled?, do: "Enabled", else: "Disabled")),
        detail("Readiness", readiness_label(transport))
      ]
  end

  defp provider_details(%{origin: :provider_managed} = transport) do
    [
      detail(
        "Mission Provider",
        "#{provider_label(transport)} · v#{transport.mission_provider_version}",
        href:
          ~p"/missions/#{transport.mission_id}/comms/providers/#{transport.mission_provider_id}"
      ),
      detail("Service Profile", profile_ref_label(transport.service_profile_ref), mono: true),
      detail("Delivery Profile", profile_ref_label(transport.delivery_profile_ref), mono: true)
    ]
  end

  defp provider_details(_transport), do: []

  defp detail(label, value, opts \\ []) do
    %{
      label: label,
      value: value,
      mono: Keyword.get(opts, :mono, false),
      href: Keyword.get(opts, :href)
    }
  end

  defp version_history_dto(versions) do
    %{
      id: "transport-versions",
      title: "Version History",
      rows:
        Enum.map(versions, fn version ->
          %{
            id: "transport-version-#{version.version}",
            label: "v#{version.version}",
            lifecycle_state: version.lifecycle_state |> Atom.to_string() |> String.upcase()
          }
        end)
    }
  end

  defp transport_summary(transport) do
    {:ok, entry} = TransportKind.fetch(transport.transport_kind)
    entry.module.display_summary(transport.configuration)
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> human_text()
  end

  defp human_text(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.upcase()
  end

  defp origin_label(:provider_managed), do: "Provider managed"
  defp origin_label(:direct), do: "Direct"

  defp provider_label(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["provider", "display_name"]) ||
      transport.mission_provider_id
  end

  defp provider_label(_transport), do: "Cadence"

  defp operator_summary(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["delivery_profile", "operator_summary"]) ||
      "Provider-managed delivery"
  end

  defp operator_summary(%{transport_kind: kind}), do: "Direct #{human_atom(kind)}"

  defp readiness_label(%{origin: :provider_managed} = transport) do
    if get_in(transport.provider_configuration_snapshot, ["delivery_profile", "state"]) == "ready",
      do: "Ready",
      else: "Profile drift"
  end

  defp readiness_label(_transport), do: "Configured"

  defp profile_ref_label(%{"id" => id, "version" => version}), do: "#{id} · v#{version}"
  defp profile_ref_label(_reference), do: "Not selected"

  defp diagnostics_json(transport) do
    Jason.encode!(
      %{
        "origin" => Atom.to_string(transport.origin),
        "configuration" => transport.configuration,
        "provider_configuration_snapshot" => transport.provider_configuration_snapshot,
        "compatibility_provider_profile_id" => transport.materialized_provider_profile_id
      },
      pretty: true
    )
  end
end
