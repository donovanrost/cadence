defmodule Cadence.Telemetry.Storage.ObservationIdentityState do
  @moduledoc """
  Domain read model for the current state of a telemetry observation identity.

  Observation rows are immutable in the physical telemetry store. This struct is
  the queryable current-state view that consumers should use when they need to
  know which observation is currently canonical and whether duplicates,
  conflicts, or corrections exist for the same logical observation.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.WriteContext

  @type validity_state :: ObservationEnvelope.validity_state()

  @type t :: %__MODULE__{
          observation_identity_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          realm: WriteContext.realm() | binary(),
          replay_run_id: binary() | nil,
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          observable_id: binary(),
          point_id: binary(),
          spacecraft_id: binary() | nil,
          canonical_observation_id: binary() | nil,
          canonical_sample_id: binary() | nil,
          canonical_revision: pos_integer() | nil,
          latest_observation_id: binary(),
          latest_sample_id: binary(),
          latest_revision: pos_integer(),
          validity_state: validity_state(),
          canonical_count: non_neg_integer(),
          duplicate_count: non_neg_integer(),
          conflict_count: non_neg_integer(),
          superseded_count: non_neg_integer(),
          advisory_count: non_neg_integer(),
          first_seen_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          decided_at: DateTime.t() | nil,
          decision_event_id: binary() | nil,
          decision_reason: binary() | nil,
          payload: map()
        }

  defstruct [
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
    :first_seen_at,
    :last_seen_at,
    :decided_at,
    :decision_event_id,
    :decision_reason,
    canonical_count: 0,
    duplicate_count: 0,
    conflict_count: 0,
    superseded_count: 0,
    advisory_count: 0,
    payload: %{}
  ]
end
