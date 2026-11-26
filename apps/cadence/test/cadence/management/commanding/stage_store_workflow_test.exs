defmodule Cadence.Management.Commanding.StageStoreWorkflowTest do
  use Cadence.DataCase, async: false
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandStage,
    CommandStageRow,
    LifecyclePolicy,
    StagedCommandItem,
    StageStore
  }

  setup do
    c = CommandAuthoringFixtures.fixture!()

    stage =
      CommandStage.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        stage_name: "Flight review",
        owner: %{"user_id" => c.user.user_id},
        visibility: :shared
      })

    {:ok, stage} = StageStore.persist_stage(c.org, stage)
    Map.put(c, :stage, stage)
  end

  test "duplicate stage and item identities never report an unpersisted value", c do
    assert {:error, _} =
             StageStore.persist_stage(c.org, %{c.stage | stage_name: "Forged replacement"})

    assert {:ok, actual} = StageStore.fetch_stage(c.org, c.mission, c.stage.command_stage_id)
    assert actual == c.stage
    first = item!(c)
    assert {:error, _} = StageStore.persist_item(c.org, %{first | notes: "Forged replacement"})
    assert {:ok, actual} = StageStore.fetch_item(c.org, c.mission, first.staged_command_item_id)
    assert actual == first
  end

  test "stage owner, parent stage and submitted request pointers remain immutable", c do
    assert {:error, :command_stage_owner_immutable} =
             StageStore.update_stage(c.org, %{c.stage | owner: %{"user_id" => "other"}})

    assert {:error, :invalid_command_stage_transition} =
             StageStore.update_stage(c.org, %{c.stage | lifecycle_state: :submitted})

    first = item!(c)

    {:ok, other} =
      StageStore.persist_stage(c.org, %{c.stage | command_stage_id: Cadence.Ids.new("stage")})

    assert {:error, :staged_command_parent_immutable} =
             StageStore.update_item(c.org, %{first | command_stage_id: other.command_stage_id})

    assert {:error, :staged_command_submission_immutable} =
             StageStore.update_item(c.org, %{first | submitted_command_request_id: "request"})

    assert {:error, :invalid_staged_command_transition} =
             StageStore.update_item(c.org, %{first | lifecycle_state: :submitted})
  end

  test "cancellation and ordering of unchanged draft intent do not need an active model", c do
    first = item!(c)
    Repo.delete!(Repo.get!(ActiveBindingSetRow, c.mission))

    assert {:ok, edited} =
             StageStore.update_item(c.org, %{first | notes: "Retain for later", item_order: 9})

    assert edited.item_order == 9
    assert {:ok, canceled} = StageStore.update_item(c.org, %{edited | lifecycle_state: :canceled})
    assert canceled.lifecycle_state == :canceled
    assert {:error, _} = StageStore.update_item(c.org, %{canceled | lifecycle_state: :draft})
  end

  test "unknown stored lifecycle strings never become editable drafts", c do
    Repo.update!(
      Ecto.Changeset.change(Repo.get!(CommandStageRow, c.stage.command_stage_id),
        lifecycle_state: "unknown"
      )
    )

    assert {:error, _} =
             LifecyclePolicy.ensure_stage_editable(%{
               command_stage_id: c.stage.command_stage_id,
               lifecycle_state: "unknown"
             })

    assert {:error, _} = StageStore.update_stage(c.org, c.stage)
  end

  defp item!(c, attrs \\ %{}) do
    item =
      StagedCommandItem.new(
        Map.merge(
          %{
            organization_id: c.org,
            mission_id: c.mission,
            command_stage_id: c.stage.command_stage_id,
            source_endpoint_ref: c.target.source_endpoint_id,
            mission_model_revision_id: c.model.revision_id,
            command_id: c.model.commands_by_name["COMMAND_1"],
            argument_values: %{"amount" => 2},
            item_order: 0
          },
          attrs
        )
      )

    {:ok, item} = StageStore.persist_item(c.org, item)
    item
  end
end
