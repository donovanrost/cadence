defmodule Cadence.Management.DataSources do
  @moduledoc """
  Management-plane boundary for data-source definitions and bindings.

  This API owns desired data-source configuration, binding history, and the
  durable lifecycle state that control-plane workers reconcile.
  """

  alias Cadence.Management.DataSources.Credentials
  alias Cadence.Management.DataSources.Store

  alias Cadence.Management.DataSources.Inventory

  defdelegate source_inventory_page(organization_id, mission_id, page, source_id \\ nil),
    to: Inventory,
    as: :sources

  defdelegate binding_inventory_page(organization_id, mission_id, page, source_id \\ nil),
    to: Inventory,
    as: :bindings

  defdelegate source_event_page(organization_id, mission_id, page, source_id),
    to: Inventory,
    as: :source_events

  defdelegate binding_event_page(organization_id, mission_id, page, binding_id),
    to: Inventory,
    as: :binding_events

  defdelegate fetch_credential_reference(credentials_ref), to: Credentials, as: :fetch_reference
  defdelegate register_credential_reference(attrs, opts), to: Credentials, as: :register_reference

  defdelegate rotate_credential_reference(credentials_ref, attrs, opts),
    to: Credentials,
    as: :rotate_reference

  defdelegate resolve_credential(credentials_ref, opts), to: Credentials, as: :resolve

  defdelegate resolve_credential_material(credentials_ref, opts),
    to: Credentials,
    as: :resolve_material

  defdelegate fetch_data_binding_event(organization_id, mission_id, event_id), to: Store

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
