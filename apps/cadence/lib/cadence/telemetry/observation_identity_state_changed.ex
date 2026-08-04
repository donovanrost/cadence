defmodule Cadence.Telemetry.ObservationIdentityStateChanged do
  @moduledoc """
  Data-plane fact emitted after an observation identity state decision commits.

  Consumers decide independently whether the state change affects their own
  projections or runtime artifacts.
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
          dependency: map() | nil,
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
    :dependency,
    :committed_at
  ]
  defstruct @enforce_keys
end
