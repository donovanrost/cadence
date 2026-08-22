defmodule Cadence.Catalog.MissionModel.SpaceSystem do
  @moduledoc "Resolved semantic namespace and composition node."

  alias Cadence.Catalog.MissionModel.{Canonical, Path, Provenance}

  @type t :: %__MODULE__{
          semantic_id: binary(),
          name: binary(),
          qualified_name: binary(),
          parent_id: binary() | nil,
          aliases: [binary()],
          metadata: map(),
          provenance: Provenance.t() | nil
        }

  @enforce_keys [:semantic_id, :name, :qualified_name]
  defstruct @enforce_keys ++ [:parent_id, aliases: [], metadata: %{}, provenance: nil]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    qualified_name = attrs |> value(:qualified_name) |> Path.normalize()
    name = value(attrs, :name, qualified_name |> String.split("/", trim: true) |> List.last())

    %__MODULE__{
      semantic_id:
        value(attrs, :semantic_id, Canonical.semantic_id(:space_system, qualified_name)),
      name: name || "/",
      qualified_name: qualified_name,
      parent_id: value(attrs, :parent_id),
      aliases: value(attrs, :aliases, []),
      metadata: value(attrs, :metadata, %{}),
      provenance: attrs |> value(:provenance) |> Provenance.new()
    }
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
