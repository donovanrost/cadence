defmodule Cadence.Management.Commanding.StageItemAuthoringTest do
  use Cadence.DataCase, async: false
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandRequestRow, CommandStage, StagedCommandItemRow, StageStore}

  alias Cadence.Management.Commanding.{
    RequestAuthoring,
    StageCatalog,
    StageDrafts,
    StageItemAuthoring
  }

  setup do
    c = CommandAuthoringFixtures.fixture!()

    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Draft commands",
          owner: %{"user_id" => c.user.user_id},
          visibility: :private
        })
      )

    Map.put(c, :stage, stage)
  end

  test "new draft persists the validated explicit intent and reviewed model without a formal request",
       c do
    input = preview_input(c, nil)

    assert {:ok, held} =
             StageItemAuthoring.preview(c.scope, c.mission, c.stage.command_stage_id, nil, input)

    public = StageItemAuthoring.public_preview(held)

    assert Jason.decode!(public["command"]["resolved_argument_values_json"]) == %{
             "amount" => 2,
             "delay_s" => 5
           }

    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
    assert {:ok, receipt} = save(c, held)
    assert receipt["item_id"] == held.item_id
    assert receipt["actor_id"] == c.user.user_id
    item = Repo.get!(StagedCommandItemRow, held.item_id)
    assert item.argument_values_document == %{"value" => %{"amount" => 2}}
    assert item.mission_model_revision_id == c.model.revision_id
    assert item.submitted_command_request_id == nil
    assert item.lifecycle_state == "draft"
    assert item.notes == String.duplicate("é", 2_000)
    assert Repo.aggregate(CommandRequestRow, :count) == 0
    assert {:error, _} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 1
  end

  test "edited command intent keeps durable identity and rejects a retained item version", c do
    {:ok, original} =
      StageItemAuthoring.preview(
        c.scope,
        c.mission,
        c.stage.command_stage_id,
        nil,
        preview_input(c, nil)
      )

    {:ok, _} = save(c, original)
    input = preview_input(c, original.item_id)
    input = put_in(input, ["command", "argument_values_json"], Jason.encode!(%{"amount" => 7}))

    assert {:ok, edit} =
             StageItemAuthoring.preview(
               c.scope,
               c.mission,
               c.stage.command_stage_id,
               original.item_id,
               input
             )

    assert {:ok, receipt} = save(c, edit)
    assert receipt["item_id"] == original.item_id

    assert Repo.get!(StagedCommandItemRow, original.item_id).argument_values_document == %{
             "value" => %{"amount" => 7}
           }

    assert {:error, :command_stage_changed} = save(c, edit)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 1
    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  test "stale model previews cannot create a draft under a substituted model", c do
    {:ok, held} =
      StageItemAuthoring.preview(
        c.scope,
        c.mission,
        c.stage.command_stage_id,
        nil,
        preview_input(c, nil)
      )

    CommandAuthoringFixtures.activate!(c.org, c.mission, 3)
    assert {:error, :command_authoring_basis_changed} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
  end

  test "invalid arguments, mismatched stage and foreign item identity cannot become draft writes",
       c do
    input = preview_input(c, nil)

    assert {:error, _} =
             StageItemAuthoring.preview(
               c.scope,
               c.mission,
               c.stage.command_stage_id,
               nil,
               put_in(
                 input,
                 ["command", "argument_values_json"],
                 Jason.encode!(%{"amount" => 999})
               )
             )

    assert {:error, _} =
             StageItemAuthoring.preview(
               c.scope,
               c.mission,
               c.stage.command_stage_id,
               "item_foreign",
               %{input | "expected_item" => String.duplicate("a", 64)}
             )

    {:ok, held} =
      StageItemAuthoring.preview(c.scope, c.mission, c.stage.command_stage_id, nil, input)

    {:ok, _} = StageStore.update_stage(c.org, %{c.stage | stage_name: "Changed"})
    assert {:error, :command_stage_changed} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
  end

  defp save(c, held) do
    token = StageDrafts.new_write_token()

    input = %{
      "expected_write" => token,
      "expected_preview" => held.token,
      "expected_stage" => held.expected_stage,
      "notes" => String.duplicate("é", 2_000),
      "order" => 3
    }

    input = if held.new?, do: input, else: Map.put(input, "expected_item", held.expected_item)
    StageItemAuthoring.save(c.scope, c.mission, c.stage.command_stage_id, token, held, input)
  end

  defp preview_input(c, item_id) do
    {:ok, stage} =
      StageCatalog.workbench(
        c.scope,
        c.mission,
        c.stage.command_stage_id,
        if(item_id, do: %{"item" => item_id}, else: %{})
      )

    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    %{
      "expected_stage" => stage["stage"]["expected_stage"],
      "expected_item" => if(item_id, do: stage["selected_item"]["expected_item"], else: nil),
      "command" => %{
        "expected_basis" => catalog["basis"]["token"],
        "source_endpoint_ref" => c.target.source_endpoint_id,
        "command_id" => c.model.commands_by_name["COMMAND_1"],
        "argument_values_json" => Jason.encode!(%{"amount" => 2}),
        "priority" => 3,
        "not_before" => nil,
        "expires_at" => nil
      }
    }
  end
end
