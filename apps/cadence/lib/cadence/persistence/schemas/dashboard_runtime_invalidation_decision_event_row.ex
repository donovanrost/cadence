defmodule Cadence.Persistence.Schemas.DashboardRuntimeInvalidationDecisionEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.RuntimeInvalidation.DecisionEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:dashboard_runtime_invalidation_decision_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dashboard_runtime_invalidation_decision_events" do
    field(:invalidation_event_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:boundary, :string)
    field(:domain_fact, :string)
    field(:decision_status, :string)
    field(:matches?, :boolean, source: :matches)
    field(:dashboard_matches?, :boolean, source: :dashboard_matches)
    field(:context_matches?, :boolean, source: :context_matches)
    field(:context_reason, :string)
    field(:refresh_allowed?, :boolean, source: :refresh_allowed)
    field(:refresh_reason, :string)
    field(:affected_placement_count, :integer)
    field(:affected_placement_ids, {:array, :string}, default: [])
    field(:affected_widget_type_ids, {:array, :string}, default: [])
    field(:affected_impact_reasons, {:array, :string}, default: [])
    field(:invalidated_artifacts, :integer, default: 0)
    field(:invalidation_occurred_at, :utc_datetime_usec)
    field(:decision_observed_at, :utc_datetime_usec)
    field(:filters, :map, default: %{})
    field(:measurements, :map, default: %{})
    field(:decision, :map, default: %{})
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :dashboard_runtime_invalidation_decision_event_id,
    :invalidation_event_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :boundary,
    :domain_fact,
    :decision_status,
    :matches?,
    :dashboard_matches?,
    :context_matches?,
    :context_reason,
    :refresh_allowed?,
    :refresh_reason,
    :affected_placement_count,
    :affected_placement_ids,
    :affected_widget_type_ids,
    :affected_impact_reasons,
    :invalidated_artifacts,
    :invalidation_occurred_at,
    :decision_observed_at,
    :filters,
    :measurements,
    :decision,
    :payload
  ]

  @required_fields [
    :dashboard_runtime_invalidation_decision_event_id,
    :invalidation_event_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :boundary,
    :decision_status,
    :decision_observed_at,
    :filters,
    :measurements,
    :decision,
    :payload
  ]

  @spec changeset(DecisionEvent.t()) :: Ecto.Changeset.t()
  def changeset(%DecisionEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:affected_placement_count, greater_than_or_equal_to: 0)
    |> validate_number(:invalidated_artifacts, greater_than_or_equal_to: 0)
    |> validate_map(:filters)
    |> validate_map(:measurements)
    |> validate_map(:decision)
    |> validate_map(:payload)
    |> unique_constraint([:dashboard_runtime_invalidation_decision_event_id],
      name: :dashboard_runtime_invalidation_decision_events_pkey
    )
  end

  @spec to_domain(%__MODULE__{}) :: DecisionEvent.t()
  def to_domain(%__MODULE__{} = row) do
    %DecisionEvent{
      dashboard_runtime_invalidation_decision_event_id:
        row.dashboard_runtime_invalidation_decision_event_id,
      invalidation_event_id: row.invalidation_event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      dashboard_id: row.dashboard_id,
      boundary: maybe_existing_atom(row.boundary),
      domain_fact: maybe_existing_atom(row.domain_fact),
      decision_status: maybe_existing_atom(row.decision_status),
      matches?: row.matches?,
      dashboard_matches?: row.dashboard_matches?,
      context_matches?: row.context_matches?,
      context_reason: maybe_existing_atom(row.context_reason),
      refresh_allowed?: row.refresh_allowed?,
      refresh_reason: maybe_existing_atom(row.refresh_reason),
      affected_placement_count: row.affected_placement_count,
      affected_placement_ids: row.affected_placement_ids || [],
      affected_widget_type_ids: row.affected_widget_type_ids || [],
      affected_impact_reasons:
        Enum.map(row.affected_impact_reasons || [], &maybe_existing_atom/1),
      invalidated_artifacts: row.invalidated_artifacts || 0,
      invalidation_occurred_at: row.invalidation_occurred_at,
      decision_observed_at: row.decision_observed_at,
      filters: restore_map(row.filters),
      measurements: restore_map(row.measurements),
      decision: restore_map(row.decision),
      payload: JsonDocument.unwrap_value(row.payload)
    }
  end

  defp domain_attrs(%DecisionEvent{} = event) do
    %{
      dashboard_runtime_invalidation_decision_event_id:
        event.dashboard_runtime_invalidation_decision_event_id,
      invalidation_event_id: event.invalidation_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      dashboard_id: event.dashboard_id,
      boundary: enum_string(event.boundary),
      domain_fact: enum_string(event.domain_fact),
      decision_status: enum_string(event.decision_status),
      matches?: event.matches?,
      dashboard_matches?: event.dashboard_matches?,
      context_matches?: event.context_matches?,
      context_reason: enum_string(event.context_reason),
      refresh_allowed?: event.refresh_allowed?,
      refresh_reason: enum_string(event.refresh_reason),
      affected_placement_count: event.affected_placement_count,
      affected_placement_ids: event.affected_placement_ids,
      affected_widget_type_ids: event.affected_widget_type_ids,
      affected_impact_reasons: Enum.map(event.affected_impact_reasons, &enum_string/1),
      invalidated_artifacts: event.invalidated_artifacts,
      invalidation_occurred_at: event.invalidation_occurred_at,
      decision_observed_at: event.decision_observed_at,
      filters: JsonDocument.wrap_value(event.filters),
      measurements: JsonDocument.wrap_value(event.measurements),
      decision: JsonDocument.wrap_value(event.decision),
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _value -> add_error(changeset, field, "must be a map")
    end
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp maybe_existing_atom(nil), do: nil

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp maybe_existing_atom(value), do: value

  defp restore_map(value) do
    value
    |> JsonDocument.unwrap_value()
    |> restore_value()
  end

  defp restore_value(value) when is_map(value) do
    Map.new(value, fn {key, value} ->
      {restore_key(key), restore_value(value)}
    end)
  end

  defp restore_value(value) when is_list(value), do: Enum.map(value, &restore_value/1)
  defp restore_value(value) when is_binary(value), do: maybe_existing_atom(value)
  defp restore_value(value), do: value

  defp restore_key(key) when is_binary(key), do: maybe_existing_atom(key)
  defp restore_key(key), do: key
end
