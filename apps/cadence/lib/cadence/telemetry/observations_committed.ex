defmodule Cadence.Telemetry.ObservationsCommitted do
  @moduledoc """
  Data-plane fact emitted after a canonical telemetry observation batch commits.

  The fact describes the changed source identity and time intervals without
  naming any downstream cache, projection, or dashboard consumer.
  """

  @type time_range :: %{
          required(:axis) => atom(),
          required(:from) => DateTime.t(),
          required(:to) => DateTime.t()
        }

  @type t :: %__MODULE__{
          organization_id: binary() | nil,
          mission_id: binary(),
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          realm: atom() | binary() | nil,
          replay_run_id: binary() | nil,
          observable_id: binary() | nil,
          time_ranges: [time_range()],
          evidence_ref: map(),
          committed_at: DateTime.t()
        }

  @enforce_keys [
    :organization_id,
    :mission_id,
    :data_source_id,
    :binding_id,
    :realm,
    :replay_run_id,
    :observable_id,
    :time_ranges,
    :evidence_ref,
    :committed_at
  ]
  defstruct @enforce_keys
end
