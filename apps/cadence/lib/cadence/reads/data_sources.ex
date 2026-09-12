defmodule Cadence.Reads.DataSources do
  @moduledoc """
  Read boundary for desired and observed Data Sources state.

  Callers receive domain values rather than persistence rows and never need to
  know which plane owns the authoritative write or projection.
  """

  alias Cadence.Projections.DataSources.{Health, Watermarks}

  alias Cadence.Management.DataSources, as: Definitions

  defdelegate source_inventory_page(organization_id, mission_id, page, source_id \\ nil),
    to: Definitions

  defdelegate binding_inventory_page(organization_id, mission_id, page, source_id \\ nil),
    to: Definitions

  defdelegate source_event_page(organization_id, mission_id, page, source_id), to: Definitions
  defdelegate binding_event_page(organization_id, mission_id, page, binding_id), to: Definitions

  defdelegate default_managed_data_source(), to: Definitions
  defdelegate default_limits_data_source(), to: Definitions
  defdelegate default_operational_observables_data_source(), to: Definitions
  defdelegate default_events_data_source(), to: Definitions
  defdelegate default_flight_telemetry_binding(), to: Definitions
  defdelegate default_flight_limits_binding(), to: Definitions
  defdelegate default_flight_operational_observables_binding(), to: Definitions
  defdelegate default_flight_events_binding(), to: Definitions

  defdelegate fetch_data_source(data_source_id), to: Definitions
  defdelegate fetch_data_binding(binding_id), to: Definitions
  defdelegate fetch_credential_reference(credentials_ref), to: Definitions
  defdelegate resolve_credential(credentials_ref, opts), to: Definitions

  defdelegate resolve_credential_material(credentials_ref, opts),
    to: Definitions

  defdelegate list_data_sources(organization_id \\ nil, mission_id \\ nil), to: Definitions
  defdelegate list_data_bindings(organization_id \\ nil, mission_id \\ nil), to: Definitions

  defdelegate list_data_binding_events(binding_id, opts \\ []), to: Definitions

  defdelegate list_data_binding_intervals(
                organization_id \\ nil,
                mission_id \\ nil,
                opts \\ []
              ),
              to: Definitions

  defdelegate list_data_realms(organization_id \\ nil, mission_id \\ nil, opts \\ []),
    to: Definitions

  defdelegate fetch_source_health_status(source_health_key), to: Health

  defdelegate fetch_source_health_for_identity(identity),
    to: Health,
    as: :fetch_status_for_identity

  defdelegate list_source_health_events(organization_id, mission_id, opts \\ []),
    to: Health

  defdelegate list_source_health_statuses(organization_id, mission_id, opts \\ []),
    to: Health

  defdelegate fetch_source_watermark_status(source_watermark_key), to: Watermarks

  defdelegate fetch_source_watermark_for_identity(identity),
    to: Watermarks,
    as: :fetch_status_for_identity

  defdelegate list_source_watermark_events(organization_id, mission_id, opts \\ []),
    to: Watermarks

  defdelegate list_source_watermark_statuses(organization_id, mission_id, opts \\ []),
    to: Watermarks

  defdelegate fetch_data_binding_event(organization_id, mission_id, event_id), to: Definitions
  defdelegate fetch_source_health_event(organization_id, mission_id, event_id), to: Health
  defdelegate fetch_source_watermark_event(organization_id, mission_id, event_id), to: Watermarks
end
