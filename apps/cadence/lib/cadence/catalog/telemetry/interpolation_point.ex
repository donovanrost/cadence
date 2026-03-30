defmodule Cadence.Catalog.Telemetry.InterpolationPoint do
  @moduledoc """
  One interpolation point for canonical telemetry calibration algorithms.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type t :: %__MODULE__{
          raw: number(),
          calibrated: number()
        }

  defstruct [:raw, :calibrated]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      raw: Normalize.fetch!(attrs, :raw),
      calibrated: Normalize.fetch!(attrs, :calibrated)
    }
  end
end
