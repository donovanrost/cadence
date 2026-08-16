defmodule Cadence.Catalog.Bundle do
  @moduledoc """
  Portable Mission Model declaration output shared by catalog importers.
  """

  alias Cadence.Catalog.MissionModel.Layer

  @type t :: %__MODULE__{
          declaration_layers: [Layer.t()],
          metadata: map()
        }

  defstruct declaration_layers: [], metadata: %{}

  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{
      declaration_layers:
        Map.get(attrs, :declaration_layers, Map.get(attrs, "declaration_layers", [])),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
