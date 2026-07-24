defmodule Cadence.Telemetry.ObservationIdentitySelectionChanged do
  @moduledoc """
  Data-plane fact emitted after an observation-identity selection commits.

  The fact carries the exact telemetry scope needed by downstream projections;
  it does not expose persistence rows or require the producer to know which
  projections consume it.
  """

  @type t :: %__MODULE__{
          observation_identity_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          point_id: binary(),
          spacecraft_id: binary() | nil,
          realm: atom() | binary(),
          replay_run_id: binary() | nil,
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          committed_at: DateTime.t()
        }

  @enforce_keys [
    :observation_identity_id,
    :organization_id,
    :mission_id,
    :point_id,
    :spacecraft_id,
    :realm,
    :replay_run_id,
    :data_source_id,
    :binding_id,
    :committed_at
  ]
  defstruct @enforce_keys
end
