defmodule Cadence.Management.DataSources do
  @moduledoc """
  Management-plane boundary for data-source definitions and bindings.

  This API owns desired data-source configuration, binding history, and the
  durable lifecycle state that control-plane workers reconcile.
  """

  alias Cadence.Management.DataSources.Store

  defdelegate default_managed_data_source(), to: Store
  defdelegate default_limits_data_source(), to: Store
  defdelegate default_operational_observables_data_source(), to: Store
  defdelegate default_events_data_source(), to: Store
  defdelegate default_flight_telemetry_binding(), to: Store
  defdelegate default_flight_limits_binding(), to: Store
  defdelegate default_flight_operational_observables_binding(), to: Store
  defdelegate default_flight_events_binding(), to: Store
  defdelegate ensure_default_managed_sources!(), to: Store

  defdelegate persist_data_source(data_source, opts \\ []), to: Store
  defdelegate persist_data_binding(data_binding, opts \\ []), to: Store
  defdelegate fetch_data_source(data_source_id), to: Store
  defdelegate fetch_data_binding(binding_id), to: Store
  defdelegate disable_data_source(data_source_id, attrs \\ %{}, opts \\ []), to: Store
  defdelegate enable_data_source(data_source_id, attrs \\ %{}, opts \\ []), to: Store
  defdelegate disable_data_binding(binding_id, attrs \\ %{}, opts \\ []), to: Store
  defdelegate enable_data_binding(binding_id, attrs \\ %{}, opts \\ []), to: Store
  defdelegate supersede_data_binding(binding_id, attrs \\ %{}, opts \\ []), to: Store
  defdelegate list_data_binding_events(binding_id, opts \\ []), to: Store

  defdelegate list_data_source_events(organization_id \\ nil, mission_id \\ nil, opts \\ []),
    to: Store

  defdelegate list_data_binding_intervals(
                organization_id \\ nil,
                mission_id \\ nil,
                opts \\ []
              ),
              to: Store

  defdelegate list_data_sources(organization_id \\ nil, mission_id \\ nil), to: Store
  defdelegate list_data_bindings(organization_id \\ nil, mission_id \\ nil), to: Store

  defdelegate list_data_realms(organization_id \\ nil, mission_id \\ nil, opts \\ []),
    to: Store

  defdelegate reconcile_tsdb_backend(data_source_id, attrs \\ %{}, opts \\ []), to: Store

  defdelegate request_tsdb_backend_deprovisioning(
                data_source_id,
                attrs \\ %{},
                opts \\ []
              ),
              to: Store

  defdelegate request_tsdb_backend_provisioning(data_source_id, attrs \\ %{}, opts \\ []),
    to: Store

  defdelegate complete_tsdb_backend_provisioning(data_source_id, attrs \\ %{}, opts \\ []),
    to: Store

  defdelegate complete_tsdb_backend_deprovisioning(
                data_source_id,
                attrs \\ %{},
                opts \\ []
              ),
              to: Store
end
