defmodule Cadence.Persistence.Schemas.TelemetryLatestLimitStateRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Limits.Event
  alias Cadence.Persistence.JsonDocument

  @mission_scope_key "__mission__"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "telemetry_latest_limit_states" do
    field(:limit_event_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_scope_id, :string)
    field(:spacecraft_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
    field(:source_sample_type, :string)
    field(:sample_id, :string)
    field(:limit_definition_id, :string)
    field(:limit_definition_version, :integer)
    field(:limit_set_name, :string)
    field(:evaluated_value, :map)
    field(:limit_state, :string)
    field(:normalized_state, :string)
    field(:violation, :boolean)
    field(:generation_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:provenance, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :limit_event_id,
    :mission_id,
    :spacecraft_scope_id,
    :point_id,
    :point_name,
    :source_sample_type,
    :sample_id,
    :limit_definition_id,
    :limit_definition_version,
    :limit_set_name,
    :evaluated_value,
    :limit_state,
    :normalized_state,
    :violation,
    :receipt_time
  ]

  @spec changeset(struct(), Event.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = latest_state_row, %Event{} = event) do
    latest_state_row
    |> cast(domain_attrs(event), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :spacecraft_scope_id, :point_id],
      name: :telemetry_latest_limit_states_scope_idx
    )
  end

  @spec to_domain(struct()) :: Event.t()
  def to_domain(%__MODULE__{} = latest_state_row) do
    %Event{
      limit_event_id: latest_state_row.limit_event_id,
      mission_id: latest_state_row.mission_id,
      spacecraft_id: latest_state_row.spacecraft_id,
      point_id: latest_state_row.point_id,
      point_name: latest_state_row.point_name,
      source_sample_type: source_sample_type(latest_state_row.source_sample_type),
      sample_id: latest_state_row.sample_id,
      limit_definition_id: latest_state_row.limit_definition_id,
      limit_definition_version: latest_state_row.limit_definition_version,
      limit_set_name: latest_state_row.limit_set_name,
      evaluated_value: JsonDocument.unwrap_value(latest_state_row.evaluated_value),
      limit_state: String.to_existing_atom(latest_state_row.limit_state),
      normalized_state: String.to_existing_atom(latest_state_row.normalized_state),
      violation: latest_state_row.violation,
      generation_time: latest_state_row.generation_time,
      receipt_time: latest_state_row.receipt_time,
      provenance: latest_state_row.provenance
    }
  end

  defp domain_attrs(%Event{} = event) do
    %{
      limit_event_id: event.limit_event_id,
      mission_id: event.mission_id,
      spacecraft_scope_id: event.spacecraft_id || @mission_scope_key,
      spacecraft_id: event.spacecraft_id,
      point_id: event.point_id,
      point_name: event.point_name,
      source_sample_type: Atom.to_string(event.source_sample_type),
      sample_id: event.sample_id,
      limit_definition_id: event.limit_definition_id,
      limit_definition_version: event.limit_definition_version,
      limit_set_name: event.limit_set_name,
      evaluated_value: JsonDocument.wrap_value(event.evaluated_value),
      limit_state: Atom.to_string(event.limit_state),
      normalized_state: Atom.to_string(event.normalized_state),
      violation: event.violation,
      generation_time: event.generation_time,
      receipt_time: event.receipt_time,
      provenance: JsonDocument.encode(event.provenance)
    }
  end

  defp all_fields do
    [
      :limit_event_id,
      :mission_id,
      :spacecraft_scope_id,
      :spacecraft_id,
      :point_id,
      :point_name,
      :source_sample_type,
      :sample_id,
      :limit_definition_id,
      :limit_definition_version,
      :limit_set_name,
      :evaluated_value,
      :limit_state,
      :normalized_state,
      :violation,
      :generation_time,
      :receipt_time,
      :provenance
    ]
  end

  defp source_sample_type("telemetry_sample"), do: :telemetry_sample
  defp source_sample_type("derived_telemetry_sample"), do: :derived_telemetry_sample
end
