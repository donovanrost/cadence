defmodule Cadence.Management.Commanding.StageStoreWorkflowTest do
  use Cadence.DataCase, async: false
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    LifecyclePolicy,
    StagedCommandItem,
    StagedCommandItemRow,
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

  test "partial submission preserves remaining drafts and creates exact provenance", c do
    first = item!(c)
    second = item!(c, %{command_id: c.model.commands_by_name["COMMAND_2"], item_order: 1})
    actor = %{"actor_kind" => "user", "user_id" => c.user.user_id}

    assert {:ok, [request]} =
             StageStore.submit_items(
               c.org,
               c.mission,
               c.stage.command_stage_id,
               [first.staged_command_item_id],
               actor
             )

    assert request.lifecycle_state == :approval_pending
    assert request.source_staged_command_item_id == first.staged_command_item_id
    assert request.source_command_stage_id == c.stage.command_stage_id
    assert request.requested_by == actor
    assert request.resolved_argument_values == %{"amount" => 2, "delay_s" => 5}
    assert {:ok, stage} = StageStore.fetch_stage(c.org, c.mission, c.stage.command_stage_id)
    assert stage.lifecycle_state == :draft

    assert {:ok, [second_request]} =
             StageStore.submit_items(
               c.org,
               c.mission,
               c.stage.command_stage_id,
               [second.staged_command_item_id],
               actor
             )

    assert second_request.lifecycle_state == :validated
    assert {:ok, stage} = StageStore.fetch_stage(c.org, c.mission, c.stage.command_stage_id)
    assert stage.lifecycle_state == :submitted
    assert {:error, _} = StageStore.update_item(c.org, %{first | notes: "Too late"})

    assert {:error, _} =
             StageStore.persist_item(c.org, %{
               second
               | staged_command_item_id: Cadence.Ids.new("item")
             })
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

  test "an invalid later item rolls back the entire submission", c do
    first = item!(c)
    second = item!(c, %{argument_values: %{"amount" => 999}, item_order: 1})

    assert {:error, _} =
             StageStore.submit_items(
               c.org,
               c.mission,
               c.stage.command_stage_id,
               [first.staged_command_item_id, second.staged_command_item_id],
               %{"user_id" => c.user.user_id}
             )

    assert Repo.aggregate(from(r in CommandRequestRow, where: r.mission_id == ^c.mission), :count) ==
             0

    assert Enum.all?(
             StageStore.list_items(c.org, c.mission, command_stage_id: c.stage.command_stage_id),
             &(&1.lifecycle_state == :draft)
           )

    assert Repo.get!(CommandStageRow, c.stage.command_stage_id).lifecycle_state == "draft"
  end

  test "duplicate, empty, malformed and oversized selections cannot partially submit", c do
    first = item!(c)

    for selection <- [
          [],
          [first.staged_command_item_id, first.staged_command_item_id],
          [first.staged_command_item_id, 3],
          Enum.map(1..26, &"item_#{&1}")
        ] do
      assert {:error, :invalid_staged_command_selection} =
               StageStore.submit_items(c.org, c.mission, c.stage.command_stage_id, selection, %{
                 "user_id" => c.user.user_id
               })
    end

    assert Repo.get!(StagedCommandItemRow, first.staged_command_item_id).lifecycle_state ==
             "draft"
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

  test "one bounded native command document serves a whole batch submission", c do
    first = item!(c)
    second = item!(c, %{item_order: 1})
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, [:cadence, :repo, :query], &capture_plan_query/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, [_, _]} =
             StageStore.submit_items(
               c.org,
               c.mission,
               c.stage.command_stage_id,
               [first.staged_command_item_id, second.staged_command_item_id],
               %{"user_id" => c.user.user_id}
             )

    assert_receive {:command_plan_query, sql, params}
    assert sql =~ "octet_length"
    assert 8_388_608 in params
    refute_received {:command_plan_query, _, _}
  end

  defp capture_plan_query(_, _, meta, recipient) do
    if String.contains?(meta.query, "mission_model_runtime_plans") and
         String.contains?(meta.query, "plan_document") do
      send(recipient, {:command_plan_query, meta.query, meta.params})
    end
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
