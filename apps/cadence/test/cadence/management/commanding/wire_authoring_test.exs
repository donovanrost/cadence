defmodule Cadence.Management.Commanding.WireAuthoringTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source

  alias Cadence.Commanding.{
    CommandRequestRow,
    CommandStage,
    StagedCommandItem,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Management.Commanding.{
    RequestAuthoring,
    StageCatalog,
    StageItemAuthoring,
    StageSubmission
  }

  alias Cadence.{
    CommandAuthoringFixtures,
    CommandReviewFixtures,
    Ids,
    MissionModelFixtures,
    MissionModels
  }

  setup do
    c = CommandReviewFixtures.scope!()
    Map.put(c, :target, CommandAuthoringFixtures.target!(c.org, c.mission))
  end

  test "native string model rejects truncation in direct and staged previews before persistence",
       c do
    c = activate(c, "string", 16)
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => c.command})
    assert catalog["selected_command"]["supported"]
    invalid = input(c, catalog, "abc")

    assert {:error, :invalid_command_wire_values} =
             RequestAuthoring.preview(c.scope, c.mission, invalid)

    assert {:ok, stage} =
             StageStore.persist_stage(
               c.org,
               CommandStage.new(%{
                 organization_id: c.org,
                 mission_id: c.mission,
                 stage_name: "Wire review",
                 owner: %{"user_id" => c.user.user_id}
               })
             )

    assert {:ok, workbench} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{})

    staged = %{
      "expected_stage" => workbench["stage"]["expected_stage"],
      "expected_item" => nil,
      "command" => invalid
    }

    assert {:error, :invalid_command_wire_values} =
             StageItemAuthoring.preview(c.scope, c.mission, stage.command_stage_id, nil, staged)

    refute Repo.exists?(CommandRequestRow)
    assert {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, "é"))

    assert {:ok, receipt} =
             RequestAuthoring.create(c.scope, c.mission, held, %{"expected_preview" => held.token})

    row = Repo.get!(CommandRequestRow, receipt["request_id"])
    assert row.resolved_argument_values_document == %{"value" => %{"value" => "é"}}
  end

  test "an imported but unsupported float width is unavailable for authoring", c do
    c = activate(c, "float", 16)
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => c.command})
    refute catalog["selected_command"]["supported"]

    document = %{
      context: catalog["context"],
      data: %{catalog: catalog, preview: nil, operation: nil}
    }

    probe =
      Path.expand(
        "../../../../../../frontend/modules/commanding/src/features/command-authoring/producer-consumer-probe.mjs",
        __DIR__
      )

    {output, code} = System.cmd("node", [probe, Jason.encode!(document)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/COMMAND_AUTHORING_INPUT=([A-Za-z0-9+\/=]+)/, output)
    assert Jason.decode!(Base.decode64!(encoded)) == %{"unavailable" => true}

    assert {:error, :unsupported_command_wire_definition} =
             RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.0))

    refute Repo.exists?(CommandRequestRow)
  end

  test "native float32 requests reject overflow while preserving representable values", c do
    c = activate(c, "float", 32)
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => c.command})
    assert catalog["selected_command"]["supported"]
    assert {:error, _} = RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.0e100))
    refute Repo.exists?(CommandRequestRow)
    assert {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.5))
    assert held.request.resolved_argument_values == %{"value" => 1.5}
  end

  test "a previously stored invalid wire value rejects the entire batch without partial requests",
       c do
    c = activate(c, "string", 16)

    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Old drafts",
          owner: %{"user_id" => c.user.user_id}
        })
      )

    items =
      for {value, order} <- [{"ok", 0}, {"abc", 1}] do
        StagedCommandItem.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          command_stage_id: stage.command_stage_id,
          source_endpoint_ref: c.target.source_endpoint_id,
          mission_model_revision_id: c.revision,
          command_id: c.command,
          argument_values: %{"value" => value},
          item_order: order
        })
        |> StagedCommandItemRow.changeset()
        |> Repo.insert!()
      end

    {:ok, workbench} = StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{})

    selection = %{
      "expected_stage" => workbench["stage"]["expected_stage"],
      "items" => Enum.map(workbench["items"]["entries"], &Map.take(&1, ["id", "expected_item"]))
    }

    assert {:error, _} =
             StageSubmission.preview(c.scope, c.mission, stage.command_stage_id, selection)

    assert {:error, _} =
             StageStore.submit_items(
               c.org,
               c.mission,
               stage.command_stage_id,
               Enum.map(items, & &1.staged_command_item_id),
               %{"actor_kind" => "user", "user_id" => c.user.user_id}
             )

    refute Repo.exists?(CommandRequestRow)

    for item <- items do
      persisted = Repo.get!(StagedCommandItemRow, item.staged_command_item_id)
      assert persisted.lifecycle_state == "draft"
      assert is_nil(persisted.submitted_command_request_id)
    end
  end

  defp input(c, catalog, value) do
    %{
      "expected_basis" => catalog["basis"]["token"],
      "source_endpoint_ref" => c.target.source_endpoint_id,
      "command_id" => c.command,
      "argument_values_json" => Jason.encode!(%{"value" => value}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }
  end

  defp activate(c, type, bits) do
    source =
      Source.new(%{
        artifact_id: Ids.new("wire_model"),
        organization_id: c.org,
        mission_id: c.mission,
        catalog_family: :combined,
        artifact_name: "wire.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        commands:
          - name: CHECK_WIRE
            opcode: 7
            parameters:
              - name: value
                data_type: #{type}
                required: true
                bit_offset: 0
                bit_length: #{bits}
        """
      })

    {:ok, imported} = CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("wire_import")})
    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    model =
      MissionModelFixtures.activate_imported_model!(c.org, c.mission, %{
        "mission_model" => %{"revision_id" => compilation.revision.revision_id}
      })

    Map.merge(c, %{command: model.commands_by_name["CHECK_WIRE"], revision: model.revision_id})
  end
end
