defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Telemetry.Storage.ObservationIdentityState
  alias Cadence.Telemetry.Storage.WriteContext

  @primary_key {:observation_identity_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "telemetry_observation_identity_states" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:data_source_id, :string)
    field(:binding_id, :string)
    field(:observable_id, :string)
    field(:point_id, :string)
    field(:spacecraft_id, :string)
    field(:canonical_observation_id, :string)
    field(:canonical_sample_id, :string)
    field(:canonical_revision, :integer)
    field(:latest_observation_id, :string)
    field(:latest_sample_id, :string)
    field(:latest_revision, :integer)
    field(:validity_state, :string)
    field(:canonical_count, :integer, default: 0)
    field(:duplicate_count, :integer, default: 0)
    field(:conflict_count, :integer, default: 0)
    field(:superseded_count, :integer, default: 0)
    field(:advisory_count, :integer, default: 0)
    field(:first_seen_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:decided_at, :utc_datetime_usec)
    field(:decision_event_id, :string)
    field(:decision_reason, :string)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :canonical_observation_id,
    :canonical_sample_id,
    :canonical_revision,
    :latest_observation_id,
    :latest_sample_id,
    :latest_revision,
    :validity_state,
    :canonical_count,
    :duplicate_count,
    :conflict_count,
    :superseded_count,
    :advisory_count,
    :first_seen_at,
    :last_seen_at,
    :decided_at,
    :decision_event_id,
    :decision_reason,
    :payload
  ]

  @required_fields [
    :observation_identity_id,
    :mission_id,
    :realm,
    :observable_id,
    :point_id,
    :latest_observation_id,
    :latest_sample_id,
    :latest_revision,
    :validity_state,
    :first_seen_at,
    :last_seen_at,
    :payload
  ]

  @validity_states ["canonical", "duplicate", "conflict", "superseded", "advisory"]

  @spec changeset(struct(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:validity_state, @validity_states)
    |> validate_number(:canonical_revision, greater_than: 0)
    |> validate_number(:latest_revision, greater_than: 0)
    |> validate_number(:canonical_count, greater_than_or_equal_to: 0)
    |> validate_number(:duplicate_count, greater_than_or_equal_to: 0)
    |> validate_number(:conflict_count, greater_than_or_equal_to: 0)
    |> validate_number(:superseded_count, greater_than_or_equal_to: 0)
    |> validate_number(:advisory_count, greater_than_or_equal_to: 0)
  end

  @spec to_domain(%__MODULE__{}) :: ObservationIdentityState.t()
  def to_domain(%__MODULE__{} = row) do
    %ObservationIdentityState{
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
      canonical_observation_id: row.canonical_observation_id,
      canonical_sample_id: row.canonical_sample_id,
      canonical_revision: row.canonical_revision,
      latest_observation_id: row.latest_observation_id,
      latest_sample_id: row.latest_sample_id,
      latest_revision: row.latest_revision,
      validity_state: normalize_validity_state(row.validity_state),
      canonical_count: row.canonical_count,
      duplicate_count: row.duplicate_count,
      conflict_count: row.conflict_count,
      superseded_count: row.superseded_count,
      advisory_count: row.advisory_count,
      first_seen_at: row.first_seen_at,
      last_seen_at: row.last_seen_at,
      decided_at: row.decided_at,
      decision_event_id: row.decision_event_id,
      decision_reason: row.decision_reason,
      payload: row.payload || %{}
    }
  end

  defp normalize_realm(realm) when is_binary(realm) do
    Enum.find(WriteContext.realms(), realm, &(Atom.to_string(&1) == realm))
  end

  defp normalize_realm(realm), do: realm

  defp normalize_validity_state(state) when state in @validity_states,
    do: String.to_existing_atom(state)

  defp normalize_validity_state(state), do: state
end
