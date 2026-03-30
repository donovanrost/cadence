defmodule Cadence.Telemetry.Sample do
  @moduledoc """
  Canonical telemetry sample emitted by a telemetry application handler.
  """

  @type quality_state :: :good | :suspect | :bad

  @type t :: %__MODULE__{
          sample_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          point_id: binary(),
          point_name: binary(),
          packet_definition_id: binary(),
          packet_definition_version: pos_integer(),
          packet_id: binary(),
          evidence_id: binary(),
          raw_value: term(),
          engineering_value: term(),
          quality_state: quality_state(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          provenance: map()
        }

  defstruct [
    :sample_id,
    :mission_id,
    :spacecraft_id,
    :point_id,
    :point_name,
    :packet_definition_id,
    :packet_definition_version,
    :packet_id,
    :evidence_id,
    :raw_value,
    :engineering_value,
    :quality_state,
    :generation_time,
    :receipt_time,
    provenance: %{}
  ]
end
