defmodule Cadence.Catalog.MissionModelIdentityTest do
  # Layer and revision ids are content digests over versioned bases (#119 on #166): identical
  # content in one organization and mission is one revision, whichever artifact, import run or file
  # name it came from. GOLDEN literals pin the bases: if one moves, every stored id moves, so bump
  # the type's basis version instead of re-pinning (DECISIONS #108, guard tests kept by #112).
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer, Provenance}

  @golden_layer_id "mission_model_layer:881e02deccf3491a36d1e6b85f0668a6a96e4076ea62da55b792ac71c3a947d4"
  @golden_revision_hex "8b4ff98d4a215be5d48570d91e167c8102059df3fd5cae02e3d835379a73746e"
  # Declaration.fingerprint/1 is what authored overrides store (checklist item 5); #119 must not
  # move it: #119 changes neither fingerprint/1 nor any field of a struct it hashes.
  @golden_fingerprint "bc16616112af33b9adac0a5fda4b1515ad894d9dd871d383d8d44b0c0846df52"

  defp layer(opts \\ []) do
    artifact = Keyword.get(opts, :artifact, "artifact-1")
    run = Keyword.get(opts, :run, "run-1")

    provenance = %{
      artifact_id: artifact,
      importer_key: "cadence_yaml",
      importer_version: "1",
      source_path: ["packets", "HEALTH"],
      source_location: %{line: 3},
      metadata: %{"import_run_id" => run}
    }

    Layer.new(%{
      organization_id: Keyword.get(opts, :org, "org-golden"),
      mission_id: Keyword.get(opts, :mission, "mission-golden"),
      name: Keyword.get(opts, :name, "bus.yaml"),
      source: %{
        "artifact_id" => artifact,
        "import_run_id" => run,
        "importer_key" => "cadence_yaml",
        "importer_version" => Keyword.get(opts, :importer_version, "1"),
        "format_key" => "cadence_yaml"
      },
      metadata: %{"source_version" => 1},
      declarations: [
        %{kind: :space_system, qualified_name: "/", provenance: provenance},
        %{
          kind: :unit,
          qualified_name: "/V",
          definition: %{"symbol" => Keyword.get(opts, :symbol, "V")},
          provenance: provenance
        }
      ]
    })
  end

  defp revision_id(layers) do
    {:ok, result} = Compiler.compile(layers)
    result.revision.revision_id
  end

  test "golden layer and revision identities" do
    layer = layer()
    assert layer.layer_id == @golden_layer_id
    # Bare hex: copied out as an identity (#166 rule 4 as amended 11-19).
    assert layer.content_sha256 ==
             String.replace_prefix(@golden_layer_id, "mission_model_layer:", "")

    {:ok, result} = Compiler.compile([layer])
    assert result.revision.revision_id == "mission_model_revision:" <> @golden_revision_hex
    assert result.revision.content_sha256 == @golden_revision_hex
  end

  test "another artifact, import run or file name is the same layer and revision" do
    renamed = layer(artifact: "artifact-2", run: "run-2", name: "renamed.yaml")

    assert renamed.layer_id == @golden_layer_id
    assert revision_id([renamed]) == revision_id([layer()])
    # The per-import facts are still recorded, as provenance only.
    assert renamed.source["artifact_id"] == "artifact-2"
    assert hd(renamed.declarations).provenance.artifact_id == "artifact-2"
  end

  test "content, importer version, organization and mission each change the identity" do
    for changed <- [
          layer(symbol: "mV"),
          layer(importer_version: "2"),
          layer(org: "org-other"),
          layer(mission: "mission-other")
        ] do
      refute changed.layer_id == @golden_layer_id
      refute revision_id([changed]) == "mission_model_revision:" <> @golden_revision_hex
    end
  end

  test "layer order is part of the revision identity" do
    other =
      Layer.new(%{
        organization_id: "org-golden",
        mission_id: "mission-golden",
        layer_kind: :authored,
        name: "overrides",
        declarations: [%{kind: :unit, qualified_name: "/A", definition: %{"symbol" => "A"}}]
      })

    refute revision_id([layer(), other]) == revision_id([other, layer()])
  end

  test "the declaration fingerprint authored overrides store doesn't move" do
    assert layer().declarations |> Enum.at(1) |> Declaration.fingerprint() == @golden_fingerprint
  end

  test "canary: a field added to a struct stays out of its basis until added on purpose" do
    declaration = Enum.at(layer().declarations, 1)
    provenance = declaration.provenance

    assert Declaration.hash_basis(Map.put(declaration, :future_field, "x")) ==
             Declaration.hash_basis(declaration)

    assert Provenance.hash_basis(Map.put(provenance, :future_field, "x")) ==
             Provenance.hash_basis(provenance)
  end
end
