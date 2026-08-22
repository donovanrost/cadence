defmodule Cadence.DerivedTelemetry.Sample do
  @moduledoc """
  Canonical derived telemetry sample emitted from the canonical telemetry log.
  """

  alias Cadence.Telemetry.Sample, as: TelemetrySample

  @type quality_state :: TelemetrySample.quality_state()

  @type t :: %__MODULE__{
          derived_sample_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          point_id: binary(),
          point_name: binary(),
          derived_definition_id: binary(),
          derived_definition_version: pos_integer(),
          trigger_sample_id: binary(),
          value: term(),
          quality_state: quality_state(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          provenance: map()
        }

  defstruct [
    :derived_sample_id,
    :mission_id,
    :spacecraft_id,
    :point_id,
    :point_name,
    :derived_definition_id,
    :derived_definition_version,
    :trigger_sample_id,
    :value,
    :quality_state,
    :generation_time,
    :receipt_time,
    provenance: %{}
  ]
end
