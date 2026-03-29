defmodule Cadence.Spacecraft do
  @moduledoc """
  Mission-owned spacecraft asset.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          spacecraft_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          display_name: binary(),
          metadata: map()
        }

  defstruct [:spacecraft_id, :organization_id, :mission_id, :display_name, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      spacecraft_id:
        Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id", Ids.new("spacecraft"))),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      display_name: Map.fetch!(attrs, :display_name),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
