defmodule Cadence.Limits.Event do
  @moduledoc """
  Canonical limit evaluation event derived from canonical telemetry or derived
  telemetry samples.
  """

  alias Cadence.Limits.Evaluator

  @type sample_source_type :: :telemetry_sample | :derived_telemetry_sample

  @type t :: %__MODULE__{
          limit_event_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          point_id: binary(),
          point_name: binary(),
          source_sample_type: sample_source_type(),
          sample_id: binary(),
          limit_definition_id: binary(),
          limit_definition_version: pos_integer(),
          limit_set_name: binary(),
          evaluated_value: term(),
          limit_state: Evaluator.limit_state(),
          normalized_state: :red | :yellow | :green | :blue,
          violation: boolean(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          provenance: map()
        }

  defstruct [
    :limit_event_id,
    :mission_id,
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
    provenance: %{}
  ]
end
