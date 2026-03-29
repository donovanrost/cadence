defmodule Cadence.Missions.Mission do
  @moduledoc """
  Organization-owned mission runtime boundary.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          mission_id: binary(),
          organization_id: binary(),
          slug: binary(),
          display_name: binary(),
          metadata: map()
        }

  defstruct [:mission_id, :organization_id, :slug, :display_name, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      mission_id: Map.get(attrs, :mission_id, Map.get(attrs, "mission_id", Ids.new("mission"))),
      organization_id: Map.fetch!(attrs, :organization_id),
      slug: Map.fetch!(attrs, :slug),
      display_name: Map.fetch!(attrs, :display_name),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
