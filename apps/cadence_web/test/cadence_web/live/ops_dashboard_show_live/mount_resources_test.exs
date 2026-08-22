defmodule CadenceWeb.OpsDashboardShowLive.MountResourcesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.OperationalObservable
  alias CadenceWeb.OpsDashboardShowLive.MountResources

  test "load gathers dashboard mount resources for the current organization and mission" do
    scope = %{organization_id: "org-1"}
    mission = %{mission_id: "mission-1"}

    resources =
      MountResources.load(scope, mission,
        list_ops_telemetry_points: fn "org-1", "mission-1" ->
          [%{point_id: "HK.temp"}]
        end,
        list_operational_observables: fn ->
          [
            observable("comms.transport.downlink_bitrate"),
            observable("future.unbacked.observable")
          ]
        end,
        list_spacecraft: fn "org-1", "mission-1" ->
          [%{spacecraft_id: "SC-1"}]
        end,
        list_source_endpoints: fn "org-1", "mission-1" ->
          [%{source_endpoint_id: "endpoint-1"}]
        end,
        list_transports: fn "org-1", "mission-1" ->
          [%{transport_id: "transport-1"}]
        end,
        list_ground_stations: fn "org-1", "mission-1" ->
          [%{ground_station_id: "ground-1"}]
        end,
        list_link_assignments: fn "org-1", "mission-1" ->
          [%{link_assignment_id: "link-1"}]
        end,
        list_scheduled_contacts: fn "org-1", "mission-1" ->
          [%{scheduled_contact_id: "contact-scheduled-1"}]
        end,
        list_realized_contacts: fn "org-1", "mission-1" ->
          [%{realized_contact_id: "contact-realized-1"}]
        end,
        list_dashboard_data_realms: fn "org-1", "mission-1" ->
          ["flight", "rehearsal"]
        end,
        list_data_bindings: fn "org-1", "mission-1" ->
          [%{binding_id: "flight-binding"}]
        end,
        list_replay_runs: fn "org-1", "mission-1", [limit: 25] ->
          [%{replay_run_id: "replay-run-1"}]
        end
      )

    assert resources == %{
             points: [%{point_id: "HK.temp"}],
             operational_observables: [observable("comms.transport.downlink_bitrate")],
             spacecraft: [%{spacecraft_id: "SC-1"}],
             source_endpoints: [%{source_endpoint_id: "endpoint-1"}],
             transports: [%{transport_id: "transport-1"}],
             ground_stations: [%{ground_station_id: "ground-1"}],
             link_assignments: [%{link_assignment_id: "link-1"}],
             scheduled_contacts: [%{scheduled_contact_id: "contact-scheduled-1"}],
             realized_contacts: [%{realized_contact_id: "contact-realized-1"}],
             data_realms: ["flight", "rehearsal"],
             data_bindings: [%{binding_id: "flight-binding"}],
             replay_runs: [%{replay_run_id: "replay-run-1"}]
           }
  end

  test "backed_operational_observables keeps only observables with implemented backing" do
    assert MountResources.backed_operational_observables([
             observable("ground.station.connection_state"),
             observable("future.unbacked.observable")
           ]) == [observable("ground.station.connection_state")]
  end

  defp observable(observable_id) do
    %OperationalObservable{
      observable_id: observable_id,
      name: observable_id,
      description: "",
      owner: :test,
      value_kind: :metric,
      value_type: :float,
      primary_scope: :mission,
      product: :test,
      storage: :projection
    }
  end
end
