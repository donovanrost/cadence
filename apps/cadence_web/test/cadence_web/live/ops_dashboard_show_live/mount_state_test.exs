defmodule CadenceWeb.OpsDashboardShowLive.MountStateTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.MountState
  alias Phoenix.LiveView.Socket

  test "assign_loaded_dashboard loads resources, assigns initial state, versions, and refresh interval" do
    scope = %{organization_id: "org-1"}
    mission = %{mission_id: "mission-1"}

    socket =
      %Socket{assigns: %{__changed__: %{}}}
      |> MountState.assign_loaded_dashboard(scope, mission, document(), :published,
        resource_loader: fn %{organization_id: "org-1"}, %{mission_id: "mission-1"} ->
          resources()
        end,
        default_live_refresh_ms: 2_000,
        assign_versions: fn socket ->
          assign(socket, :dashboard_versions, [%{version: 1}])
        end,
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end,
        list_dashboard_investigation_presets: fn "org-1",
                                                 "mission-1",
                                                 "dashboard-1",
                                                 [preset_kind: :comparison] ->
          []
        end,
        engine_refresh_ms: fn socket, 2_000 ->
          assert socket.assigns.dashboard_document.dashboard_id == "dashboard-1"
          assert socket.assigns.dashboard_data_realm == "flight"
          1_500
        end
      )

    assert socket.assigns.dashboard_document.dashboard_id == "dashboard-1"
    assert socket.assigns.dashboard_document_mode == :published
    assert socket.assigns.points == [%{point_id: "HK.temp", stale_timeout_ms: 5_000}]
    assert socket.assigns.operational_observables == [%{observable_id: "bit_rate"}]
    assert socket.assigns.spacecraft == [%{spacecraft_id: "SC-1"}]
    assert socket.assigns.source_endpoints == [%{source_endpoint_id: "endpoint-1"}]
    assert socket.assigns.transports == [%{transport_id: "transport-1"}]
    assert socket.assigns.link_assignments == [%{link_assignment_id: "link-1"}]
    assert socket.assigns.scheduled_contacts == [%{scheduled_contact_id: "contact-scheduled-1"}]
    assert socket.assigns.realized_contacts == [%{realized_contact_id: "contact-realized-1"}]
    assert socket.assigns.dashboard_data_realms == ["flight", "rehearsal"]
    assert socket.assigns.dashboard_data_bindings == [%{binding_id: "flight-binding"}]
    assert socket.assigns.dashboard_replay_runs == [%{replay_run_id: "replay-run-1"}]
    assert socket.assigns.dashboard_investigation_presets == []
    assert socket.assigns.dashboard_versions == [%{version: 1}]
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}
    assert socket.assigns.dashboard_live_refresh_ms == 1_500
  end

  defp resources do
    %{
      points: [%{point_id: "HK.temp", stale_timeout_ms: 5_000}],
      operational_observables: [%{observable_id: "bit_rate"}],
      spacecraft: [%{spacecraft_id: "SC-1"}],
      source_endpoints: [%{source_endpoint_id: "endpoint-1"}],
      transports: [%{transport_id: "transport-1"}],
      link_assignments: [%{link_assignment_id: "link-1"}],
      scheduled_contacts: [%{scheduled_contact_id: "contact-scheduled-1"}],
      realized_contacts: [%{realized_contact_id: "contact-realized-1"}],
      data_realms: ["flight", "rehearsal"],
      data_bindings: [%{binding_id: "flight-binding"}],
      replay_runs: [%{replay_run_id: "replay-run-1"}]
    }
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Ops Dashboard",
      placements: [],
      metadata: %{version: 1}
    }
  end
end
