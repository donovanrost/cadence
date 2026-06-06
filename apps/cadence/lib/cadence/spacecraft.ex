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
          scid: non_neg_integer() | nil,
          spacecraft_type_id: binary() | nil,
          spacecraft_type_version: pos_integer() | nil,
          metadata: map()
        }

  defstruct [
    :spacecraft_id,
    :organization_id,
    :mission_id,
    :display_name,
    :scid,
    :spacecraft_type_id,
    :spacecraft_type_version,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      spacecraft_id:
        Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id", Ids.new("spacecraft"))),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      display_name: Map.fetch!(attrs, :display_name),
      scid: Map.get(attrs, :scid, Map.get(attrs, "scid")),
      spacecraft_type_id:
        Map.get(attrs, :spacecraft_type_id, Map.get(attrs, "spacecraft_type_id")),
      spacecraft_type_version:
        Map.get(attrs, :spacecraft_type_version, Map.get(attrs, "spacecraft_type_version")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
