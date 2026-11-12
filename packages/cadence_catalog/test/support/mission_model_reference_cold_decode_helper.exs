# Run this helper in a separate VM (2026-11-12: a fresh :4011 couldn't decode a stored
# `criteria` reference role). No atom literals for kinds or roles here, and no importer
# loaded first: either would create the atoms and hide the regression.
importers = [
  Cadence.Catalog.Importers.CadenceYamlDatabase,
  Cadence.Catalog.Importers.Xtce13.Translator
]

for module <- importers, do: false = :code.is_loaded(module)

for kind <- Enum.map(Cadence.Catalog.MissionModel.Reference.kinds(), &Atom.to_string/1),
    role <- Enum.map(Cadence.Catalog.MissionModel.Reference.roles(), &Atom.to_string/1) do
  reference =
    Cadence.Catalog.MissionModel.Reference.new(%{
      "expected_kind" => kind,
      "source_ref" => "/stored",
      "role" => role
    })

  ^kind = Atom.to_string(reference.expected_kind)
  ^role = Atom.to_string(reference.role)
end

"criteria" =
  %{"expected_kind" => "parameter", "source_ref" => "/HK/sc_mode", "role" => "criteria"}
  |> Cadence.Catalog.MissionModel.Reference.new()
  |> Map.fetch!(:role)
  |> Atom.to_string()

for module <- importers, do: false = :code.is_loaded(module)
IO.puts("MISSION_MODEL_REFERENCE_COLD_DECODE_OK")
