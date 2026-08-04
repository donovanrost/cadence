defmodule Cadence.Reads.DataSources do
  @moduledoc """
  Read boundary for desired and observed Data Sources state.

  Callers receive domain values rather than persistence rows and never need to
  know which plane owns the authoritative write or projection.
  """

  import Ecto.Query

  alias Cadence.Management.DataSources.Credentials
  alias Cadence.Management.DataSources.Store
  alias Cadence.Management.DataSources.Store.DataBindingEventRow
  alias Cadence.Projections.DataSources.{Health, Watermarks}
  alias Cadence.Projections.DataSources.Health.EventRow, as: SourceHealthEventRow
  alias Cadence.Projections.DataSources.Watermarks.EventRow, as: SourceWatermarkEventRow
  alias Cadence.Repo

  defdelegate default_managed_data_source(), to: Store
  defdelegate default_limits_data_source(), to: Store
  defdelegate default_operational_observables_data_source(), to: Store
  defdelegate default_events_data_source(), to: Store
  defdelegate default_flight_telemetry_binding(), to: Store
  defdelegate default_flight_limits_binding(), to: Store
  defdelegate default_flight_operational_observables_binding(), to: Store
  defdelegate default_flight_events_binding(), to: Store

  defdelegate fetch_data_source(data_source_id), to: Store
  defdelegate fetch_data_binding(binding_id), to: Store
  defdelegate resolve_credential(credentials_ref, opts), to: Credentials, as: :resolve

  defdelegate resolve_credential_material(credentials_ref, opts),
    to: Credentials,
    as: :resolve_material

  defdelegate list_data_sources(organization_id \\ nil, mission_id \\ nil), to: Store
  defdelegate list_data_bindings(organization_id \\ nil, mission_id \\ nil), to: Store

  defdelegate list_data_binding_events(binding_id, opts \\ []), to: Store

  defdelegate list_data_binding_intervals(
                organization_id \\ nil,
                mission_id \\ nil,
                opts \\ []
              ),
              to: Store

  defdelegate list_data_realms(organization_id \\ nil, mission_id \\ nil, opts \\ []),
    to: Store

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

  def fetch_data_binding_event(organization_id, mission_id, event_id) do
    fetch_event(
      DataBindingEventRow,
      :data_binding_event_id,
      event_id,
      organization_id,
      mission_id,
      &DataBindingEventRow.to_domain/1,
      :data_binding_event_not_found
    )
  end

  def fetch_source_health_event(organization_id, mission_id, event_id) do
    fetch_event(
      SourceHealthEventRow,
      :source_health_event_id,
      event_id,
      organization_id,
      mission_id,
      &SourceHealthEventRow.to_domain/1,
      :source_health_event_not_found
    )
  end

  def fetch_source_watermark_event(organization_id, mission_id, event_id) do
    fetch_event(
      SourceWatermarkEventRow,
      :source_watermark_event_id,
      event_id,
      organization_id,
      mission_id,
      &SourceWatermarkEventRow.to_domain/1,
      :source_watermark_event_not_found
    )
  end

  defp fetch_event(
         schema,
         id_field,
         event_id,
         organization_id,
         mission_id,
         to_domain,
         not_found
       ) do
    schema
    |> where(
      [row],
      (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
        row.mission_id == ^mission_id and field(row, ^id_field) == ^event_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, not_found}
      row -> {:ok, to_domain.(row)}
    end
  end
end
