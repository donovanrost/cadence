defmodule Cadence.Catalog.MissionModel.SystemOwner do
  @moduledoc """
  The `SpaceSystem` that owns a declaration, and its qualified runtime name (ADR-020 P5, #1078
  slice A).

  A declaration lives under the nearest declared `SpaceSystem` above its path: a container at
  `/payload/containers/HK` belongs to the system `/payload` when that is declared, else to `/`.
  The lowered plans carry that ownership so a spacecraft bound to some systems of a revision can
  select the definitions of those systems (slice B and C): `space_system_id` (its semantic id),
  `space_system_path` and `runtime_name`, the system's path joined with the definition's own name
  (`/payload/HK`, and `/HK` for a definition owned by the root).
  """

  alias Cadence.Catalog.MissionModel.{Declaration, Path, Revision, SpaceSystem}

  @type index :: %{binary() => SpaceSystem.t()}

  @doc "The revision's systems by qualified path."
  @spec index(Revision.t()) :: index()
  def index(%Revision{space_systems: systems}),
    do: Map.new(Map.values(systems), &{&1.qualified_name, &1})

  @doc """
  The ownership fields for `declaration`, string-keyed for a plan document. A declaration with no
  declared system above it (a revision without a root) carries nils and its short name.
  """
  @spec fields(Declaration.t(), index()) :: %{binary() => binary() | nil}
  def fields(%Declaration{} = declaration, index) when is_map(index) do
    case owner(declaration.space_system_path, index) do
      %SpaceSystem{} = system ->
        %{
          "space_system_id" => system.semantic_id,
          "space_system_path" => system.qualified_name,
          "runtime_name" => Path.join(system.qualified_name, declaration.name)
        }

      nil ->
        %{
          "space_system_id" => nil,
          "space_system_path" => nil,
          "runtime_name" => declaration.name
        }
    end
  end

  defp owner(nil, _index), do: nil

  defp owner(path, index) do
    case Map.get(index, path) do
      %SpaceSystem{} = system -> system
      nil -> owner(Path.parent(path), index)
    end
  end
end
