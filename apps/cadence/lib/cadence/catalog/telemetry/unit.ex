defmodule Cadence.Catalog.Telemetry.Unit do
  @moduledoc """
  Canonical engineering unit definition.
  """

  alias Cadence.Catalog.Telemetry.{Normalize, Provenance}
  alias Cadence.Ids

  @type t :: %__MODULE__{
          unit_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          symbol: binary() | nil,
          description: binary() | nil,
          si_conversion_factor: number() | nil,
          si_conversion_offset: number() | nil,
          si_unit: binary() | nil,
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :unit_id,
    :snapshot_id,
    :name,
    :symbol,
    :description,
    :si_conversion_factor,
    :si_conversion_offset,
    :si_unit,
    :provenance,
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      unit_id: Normalize.get(attrs, :unit_id, Ids.new("telemetry_unit")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      symbol: Normalize.get(attrs, :symbol),
      description: Normalize.get(attrs, :description),
      si_conversion_factor: Normalize.get(attrs, :si_conversion_factor),
      si_conversion_offset: Normalize.get(attrs, :si_conversion_offset),
      si_unit: Normalize.get(attrs, :si_unit),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end
end
