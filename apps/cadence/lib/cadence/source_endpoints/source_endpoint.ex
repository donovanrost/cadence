defmodule Cadence.SourceEndpoints.SourceEndpoint do
  @moduledoc """
  Mission-owned semantic source endpoint used for ingress identity resolution and
  runtime partition ownership.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          source_endpoint_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          source_ref: binary() | nil,
          scid: non_neg_integer() | nil,
          display_name: binary() | nil,
          metadata: map()
        }

  defstruct [
    :source_endpoint_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :source_ref,
    :scid,
    :display_name,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      source_endpoint_id: Map.get(attrs, :source_endpoint_id, Ids.new("source_endpoint")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      spacecraft_id: Map.get(attrs, :spacecraft_id),
      source_ref: Map.get(attrs, :source_ref),
      scid: Map.get(attrs, :scid),
      display_name: Map.get(attrs, :display_name),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
