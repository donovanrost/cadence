defmodule Cadence.Catalog.MissionModel.LegacyNames do
  @moduledoc false

  alias Cadence.Catalog.MissionModel.Path

  def paths(items, id_fun, kind, name_fun) do
    {_seen, paths} =
      Enum.reduce(items, {%{}, %{}}, fn item, {seen, acc} ->
        base_path = Path.join("/", Atom.to_string(kind) <> "s/" <> name_fun.(item))
        occurrence = Map.get(seen, base_path, 0) + 1
        path = if occurrence == 1, do: base_path, else: base_path <> "~#{occurrence}"

        {Map.put(seen, base_path, occurrence), Map.put(acc, id_fun.(item), path)}
      end)

    paths
  end
end
