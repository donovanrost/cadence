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
      organization_id: map_value(attrs, :organization_id, "organization_id") || Ids.new("org"),
      slug: map_fetch!(attrs, :slug, "slug"),
      display_name: map_fetch!(attrs, :display_name, "display_name"),
      metadata: map_value(attrs, :metadata, "metadata") || %{}
    }
  end

  defp map_fetch!(attrs, atom_key, string_key) when is_map(attrs) do
    case map_value(attrs, atom_key, string_key) do
      nil -> raise KeyError, key: atom_key, term: attrs
      value -> value
    end
  end

  defp map_value(attrs, atom_key, string_key) when is_map(attrs) do
    Map.get(attrs, atom_key) || Map.get(attrs, string_key)
  end
end
