defmodule Cadence.Management.Commanding.ExactArgumentAuthoringTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandStage,
    RequestStore,
    RequestValidation,
    StagedCommandItem,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Control.Commanding
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures

  alias Cadence.Management.Commanding.{
    RequestAuthoring,
    StageCatalog,
    StageDrafts,
    StageItemAuthoring,
    StageSubmission
  }

  @maximum 18_446_744_073_709_551_615
  @minimum -9_223_372_036_854_775_808
  setup do
    Fixtures.fixture!()
  end

  test "imported unsigned defaults, explicit unsigned and signed integers survive preview, encoding and persistence",
       c do
    for {command, values, resolved, bytes} <- [
          {"SET_COUNTER", %{"amount" => 2}, %{"amount" => 2, "counter" => @maximum},
           <<1, 2, @maximum::unsigned-big-64>>},
          {"SET_COUNTER", %{"amount" => 3, "counter" => @maximum},
           %{"amount" => 3, "counter" => @maximum}, <<1, 3, @maximum::unsigned-big-64>>},
          {"SET_SIGNED", %{"counter" => @minimum}, %{"counter" => @minimum},
           <<2, @minimum::signed-big-64>>},
          {"SET_ENUM", %{"counter" => @maximum}, %{"counter" => @maximum},
           <<3, @maximum::unsigned-big-64>>},
          {"SET_ENUM", %{"counter" => Integer.to_string(@maximum)},
           %{"counter" => Integer.to_string(@maximum)}, <<3, @maximum::unsigned-big-64>>}
        ] do
      assert {:ok, held} =
               RequestAuthoring.preview(c.scope, c.mission, Fixtures.input(c, command, values))

      assert held.request.argument_values == values
      assert held.request.resolved_argument_values == resolved
      assert encoded(c, held.request) == bytes
      public = RequestAuthoring.public_preview(held)
      assert Jason.decode!(public["argument_values_json"]) == values
      assert Jason.decode!(public["resolved_argument_values_json"]) == resolved
      refute Map.has_key?(public, "resolved_argument_values")

      assert {:ok, receipt} =
               RequestAuthoring.create(c.scope, c.mission, held, %{
                 "expected_preview" => held.token
               })

      assert {:ok, stored} = RequestStore.fetch_request(c.org, c.mission, receipt["request_id"])
      assert stored == held.request
    end

    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert Repo.aggregate(CommandReleaseAttemptRow, :count) == 0
  end

  test "catalog carries exact default text and wire range checks still reject out-of-range values",
       c do
    assert {:ok, catalog} =
             RequestAuthoring.load(c.scope, c.mission, %{
               "command" => c.model.commands_by_name["SET_COUNTER"]
             })

    assert catalog["version"] == 2
    counter = Enum.find(catalog["selected_command"]["arguments"], &(&1["name"] == "counter"))
    assert counter["default_value_json"] == Integer.to_string(@maximum)
    refute Map.has_key?(counter, "default_value")

    for {command, values} <- [
          {"SET_COUNTER", %{"amount" => 2, "counter" => @maximum + 1}},
          {"SET_COUNTER", %{"amount" => 2, "counter" => -1}},
          {"SET_SIGNED", %{"counter" => @minimum - 1}},
          {"SET_SIGNED", %{"counter" => -@minimum}},
          {"SET_ENUM", %{"counter" => @maximum + 1}}
        ] do
      assert {:error, _} =
               RequestAuthoring.preview(c.scope, c.mission, Fixtures.input(c, command, values))
    end

    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  test "wide draft intent survives save, selected-item read, edit and formal batch submission",
       c do
    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Exact command batch",
          owner: %{"user_id" => c.user.user_id},
          visibility: :private
        })
      )

    stage_id = stage.command_stage_id
    {:ok, workbench} = StageCatalog.workbench(c.scope, c.mission, stage_id, %{})

    input = %{
      "expected_stage" => workbench["stage"]["expected_stage"],
      "expected_item" => nil,
      "command" => Fixtures.input(c, "SET_COUNTER", %{"amount" => 2, "counter" => @maximum})
    }

    assert {:ok, held} = StageItemAuthoring.preview(c.scope, c.mission, stage_id, nil, input)

    assert Jason.decode!(
             StageItemAuthoring.public_preview(held)["command"]["argument_values_json"]
           )["counter"] == @maximum

    assert {:ok, _} = save(c, stage_id, held)
    assert Repo.aggregate(CommandRequestRow, :count) == 0

    {:ok, selected} =
      StageCatalog.workbench(c.scope, c.mission, stage_id, %{"item" => held.item_id})

    assert selected["version"] == 2
    assert Jason.decode!(selected["selected_item"]["argument_values_json"])["counter"] == @maximum
    assert Enum.all?(selected["items"]["entries"], &is_nil(&1["argument_values_json"]))

    input = %{
      "expected_stage" => selected["stage"]["expected_stage"],
      "expected_item" => selected["selected_item"]["expected_item"],
      "command" => Fixtures.input(c, "SET_COUNTER", %{"amount" => 2, "counter" => @maximum - 1})
    }

    assert {:ok, edited} =
             StageItemAuthoring.preview(c.scope, c.mission, stage_id, held.item_id, input)

    assert {:ok, _} = save(c, stage_id, edited)

    assert Repo.get!(StagedCommandItemRow, held.item_id).argument_values_document == %{
             "value" => %{"amount" => 2, "counter" => @maximum - 1}
           }

    {:ok, selected} =
      StageCatalog.workbench(c.scope, c.mission, stage_id, %{"item" => held.item_id})

    selection = %{
      "expected_stage" => selected["stage"]["expected_stage"],
      "items" => [
        %{"id" => held.item_id, "expected_item" => selected["selected_item"]["expected_item"]}
      ]
    }

    assert {:ok, batch} = StageSubmission.preview(c.scope, c.mission, stage_id, selection)
    assert {:ok, public} = StageSubmission.public_preview(batch)
    assert [preview] = public["requests"]
    assert Jason.decode!(preview["resolved_argument_values_json"])["counter"] == @maximum - 1
    token = StageDrafts.new_write_token()

    assert {:ok, receipt} =
             StageSubmission.submit(c.scope, c.mission, stage_id, token, batch, %{
               "expected_write" => token,
               "expected_preview" => batch.token
             })

    assert [request] = receipt["requests"]
    assert {:ok, stored} = RequestStore.fetch_request(c.org, c.mission, request["request_id"])
    assert stored.argument_values["counter"] == @maximum - 1
    assert stored.resolved_argument_values["counter"] == @maximum - 1
    assert encoded(c, stored) == <<1, 2, @maximum - 1::unsigned-big-64>>
    assert Repo.aggregate(CommandRequestRow, :count) == 1
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert Repo.aggregate(CommandReleaseAttemptRow, :count) == 0
  end

  test "more resolved defaults than the UI contract allows return unavailable without effects",
       c do
    parameters =
      Enum.map_join(1..65, fn n ->
        """
            - name: value_#{n}
              data_type: uint
              required: false
              default_value: 1
              bit_offset: #{(n - 1) * 8}
              bit_length: 8
        """
      end)

    extra = "  - name: MANY_DEFAULTS\n    opcode: 4\n    parameters:\n" <> parameters
    c = %{c | model: Fixtures.activate!(c.org, c.mission, extra)}
    input = Fixtures.input(c, "MANY_DEFAULTS", %{})

    assert {:error, :command_preview_unavailable} =
             RequestAuthoring.preview(c.scope, c.mission, input)

    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Existing native drafts",
          owner: %{"user_id" => c.user.user_id}
        })
      )

    {:ok, item} =
      StageStore.persist_item(
        c.org,
        StagedCommandItem.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          command_stage_id: stage.command_stage_id,
          source_endpoint_ref: c.target.source_endpoint_id,
          mission_model_revision_id: c.model.revision_id,
          command_id: c.model.commands_by_name["MANY_DEFAULTS"],
          argument_values: %{}
        })
      )

    {:ok, workbench} = StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{})

    input = %{
      "expected_stage" => workbench["stage"]["expected_stage"],
      "items" => Enum.map(workbench["items"]["entries"], &Map.take(&1, ["id", "expected_item"]))
    }

    assert {:error, :command_stage_preview_too_large} =
             StageSubmission.preview(c.scope, c.mission, stage.command_stage_id, input)

    assert Repo.get!(StagedCommandItemRow, item.staged_command_item_id).lifecycle_state == "draft"
    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  defp encoded(c, request) do
    {:ok, basis} =
      RequestValidation.resolve_basis(
        c.org,
        c.mission,
        request.mission_model_revision_id,
        request.command_id
      )

    {:ok, %{binary: bytes}} =
      Commanding.encode_command(
        basis.runtime_definition,
        request.resolved_argument_values
      )

    bytes
  end

  defp save(c, stage_id, held) do
    token = StageDrafts.new_write_token()

    input = %{
      "expected_write" => token,
      "expected_preview" => held.token,
      "expected_stage" => held.expected_stage,
      "notes" => nil,
      "order" => 0
    }

    input = if held.new?, do: input, else: Map.put(input, "expected_item", held.expected_item)
    StageItemAuthoring.save(c.scope, c.mission, stage_id, token, held, input)
  end
end
