defmodule Cadence.Runtime.ProcessingResultsPersisted do
  @moduledoc "Data-plane fact emitted after one ingress persistence batch commits."

  alias Cadence.Telemetry.Sample

  @type t :: %__MODULE__{
          batch_id: binary(),
          evidence_ids: [binary()],
          telemetry_samples: [Sample.t()],
          persisted_at: DateTime.t()
        }

  @enforce_keys [:batch_id, :evidence_ids, :telemetry_samples, :persisted_at]
  defstruct @enforce_keys
end
