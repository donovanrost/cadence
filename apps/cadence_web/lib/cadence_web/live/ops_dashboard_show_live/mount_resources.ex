defmodule CadenceWeb.OpsDashboardShowLive.MountResources do
  alias Cadence.Reads.Replay, as: ReplayReads
  @moduledoc false

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.OperationalObservable

  def load(scope, mission, opts \\ []) do
    organization_id = scope.organization_id
    mission_id = mission.mission_id

    %{
      points: list_ops_telemetry_points(opts).(organization_id, mission_id),
      operational_observables:
        backed_operational_observables(list_operational_observables(opts).()),
      spacecraft: list_spacecraft(opts).(organization_id, mission_id),
      source_endpoints: list_source_endpoints(opts).(organization_id, mission_id),
      transports: list_transports(opts).(organization_id, mission_id),
      ground_stations: list_ground_stations(opts).(organization_id, mission_id),
      link_assignments: list_link_assignments(opts).(organization_id, mission_id),
      scheduled_contacts: list_scheduled_contacts(opts).(organization_id, mission_id),
      realized_contacts: list_realized_contacts(opts).(organization_id, mission_id),
      data_realms: list_dashboard_data_realms(opts).(organization_id, mission_id),
      data_bindings: list_data_bindings(opts).(organization_id, mission_id),
      replay_runs: list_replay_runs(opts).(organization_id, mission_id, limit: 25)
    }
  end

  def backed_operational_observables(observables) when is_list(observables) do
    Enum.filter(observables, &OperationalObservable.backed?(&1.observable_id))
  end

  defp list_ops_telemetry_points(opts) do
    Keyword.get(opts, :list_ops_telemetry_points, &Cadence.list_ops_telemetry_points/2)
  end

  defp list_operational_observables(opts) do
    Keyword.get(opts, :list_operational_observables, &OperationalObservable.list/0)
  end

  defp list_spacecraft(opts) do
    Keyword.get(opts, :list_spacecraft, &Cadence.SpacecraftStore.list_spacecraft/2)
  end

  defp list_source_endpoints(opts) do
    Keyword.get(opts, :list_source_endpoints, &Cadence.SourceEndpoints.list_source_endpoints/2)
  end

  defp list_transports(opts) do
    Keyword.get(opts, :list_transports, &TransportStore.list_transports/2)
  end

  defp list_ground_stations(opts) do
    Keyword.get(
      opts,
      :list_ground_stations,
      &GroundStationStore.list_ground_stations/2
    )
  end

  defp list_link_assignments(opts) do
    Keyword.get(opts, :list_link_assignments, &Cadence.Contacts.list_link_assignments/2)
  end

  defp list_scheduled_contacts(opts) do
    Keyword.get(opts, :list_scheduled_contacts, &Cadence.Contacts.list_scheduled_contacts/2)
  end

  defp list_realized_contacts(opts) do
    Keyword.get(opts, :list_realized_contacts, &Cadence.Contacts.list_realized_contacts/2)
  end

  defp list_dashboard_data_realms(opts) do
    Keyword.get(opts, :list_dashboard_data_realms, &Cadence.list_dashboard_data_realms/2)
  end

  defp list_data_bindings(opts) do
    Keyword.get(opts, :list_data_bindings, &DataSources.list_data_bindings/2)
  end

  defp list_replay_runs(opts) do
    Keyword.get(opts, :list_replay_runs, &ReplayReads.list_runs/3)
  end
end
