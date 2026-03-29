defmodule Cadence.Organizations.Organization do
  @moduledoc """
  Organization tenant boundary for Cadence.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          organization_id: binary(),
          slug: binary(),
          display_name: binary(),
          metadata: map()
        }

  defstruct [:organization_id, :slug, :display_name, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      organization_id:
        Map.get(attrs, :organization_id, Map.get(attrs, "organization_id", Ids.new("org"))),
      slug: Map.fetch!(attrs, :slug),
      display_name: Map.fetch!(attrs, :display_name),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
