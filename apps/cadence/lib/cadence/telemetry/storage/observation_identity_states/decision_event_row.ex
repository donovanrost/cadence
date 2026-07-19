defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent
  alias Cadence.Telemetry.Storage.WriteContext

  @primary_key {:decision_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "telemetry_observation_identity_decision_events" do
    field(:observation_identity_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:data_source_id, :string)
    field(:binding_id, :string)
    field(:observable_id, :string)
    field(:point_id, :string)
    field(:spacecraft_id, :string)
    field(:decision, :string)
    field(:decision_reason, :string)
    field(:actor_id, :string)
    field(:actor_kind, :string)
    field(:evidence_ref, :map, default: %{})
    field(:previous_state, :map)
    field(:new_state, :map)
    field(:occurred_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :decision_event_id,
    :observation_identity_id,
    :organization_id,
    :mission_id,
    :realm,
    :replay_run_id,
    :data_source_id,
    :binding_id,
    :observable_id,
    :point_id,
    :spacecraft_id,
    :decision,
    :decision_reason,
    :actor_id,
    :actor_kind,
    :evidence_ref,
    :previous_state,
    :new_state,
    :occurred_at
  ]

  @required_fields [
    :decision_event_id,
    :observation_identity_id,
    :organization_id,
    :mission_id,
    :realm,
    :observable_id,
    :point_id,
    :decision,
    :decision_reason,
    :evidence_ref,
    :previous_state,
    :new_state,
    :occurred_at
  ]

  @decisions ["mark_canonical", "mark_conflict", "mark_superseded", "mark_advisory"]

  @spec changeset(ObservationIdentityDecisionEvent.t()) :: Ecto.Changeset.t()
  def changeset(%ObservationIdentityDecisionEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:decision, @decisions)
    |> validate_map(:evidence_ref)
    |> validate_map(:previous_state)
    |> validate_map(:new_state)
  end

  @spec to_domain(%__MODULE__{}) :: ObservationIdentityDecisionEvent.t()
  def to_domain(%__MODULE__{} = row) do
    ObservationIdentityDecisionEvent.new(%{
      decision_event_id: row.decision_event_id,
      observation_identity_id: row.observation_identity_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      realm: normalize_realm(row.realm),
      replay_run_id: row.replay_run_id,
      data_source_id: row.data_source_id,
      binding_id: row.binding_id,
      observable_id: row.observable_id,
      point_id: row.point_id,
      spacecraft_id: row.spacecraft_id,
      decision: normalize_decision(row.decision),
      decision_reason: row.decision_reason,
      actor_id: row.actor_id,
      actor_kind: row.actor_kind,
      evidence_ref: row.evidence_ref || %{},
      previous_state: row.previous_state || %{},
      new_state: row.new_state || %{},
      occurred_at: row.occurred_at
    })
  end

  defp domain_attrs(%ObservationIdentityDecisionEvent{} = event) do
    %{
      decision_event_id: event.decision_event_id,
      observation_identity_id: event.observation_identity_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      realm: enum_string(event.realm),
      replay_run_id: event.replay_run_id,
      data_source_id: event.data_source_id,
      binding_id: event.binding_id,
      observable_id: event.observable_id,
      point_id: event.point_id,
      spacecraft_id: event.spacecraft_id,
      decision: enum_string(event.decision),
      decision_reason: event.decision_reason,
      actor_id: event.actor_id,
      actor_kind: event.actor_kind,
      evidence_ref: JsonDocument.encode(event.evidence_ref),
      previous_state: JsonDocument.encode(event.previous_state),
      new_state: JsonDocument.encode(event.new_state),
      occurred_at: event.occurred_at
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

  defp normalize_realm(realm) when is_binary(realm) do
    Enum.find(WriteContext.realms(), realm, &(Atom.to_string(&1) == realm)) || realm
  end

  defp normalize_realm(realm), do: realm

  defp normalize_decision(decision) when decision in @decisions,
    do: String.to_existing_atom(decision)

  defp normalize_decision(decision), do: decision
end
