defmodule Cadence.Management.Commanding.StageSubmissionTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    StagedCommandItem,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Management.Commanding.{StageCatalog, StageDrafts, StageSubmission}
  alias Cadence.SourceEndpoints.SourceEndpointRow

  setup do
    c = CommandAuthoringFixtures.fixture!()

    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Reviewed batch",
          owner: %{"user_id" => c.user.user_id},
          visibility: :private
        })
      )

    Map.put(c, :stage, stage)
  end

  test "preview creates no request; the exact selected batch persists with real actor and defaults",
       c do
    first = item!(c, %{})
    second = item!(c, %{item_order: 1, command_id: c.model.commands_by_name["COMMAND_2"]})
    unselected = item!(c, %{item_order: 2})
    held = preview!(c, [first, second])
    assert request_count(c) == 0
    assert {:ok, public} = StageSubmission.public_preview(held)
    assert length(public["requests"]) == 2
    assert Enum.all?(public["requests"], &(&1["actor_id"] == c.user.user_id))

    assert Enum.all?(
             public["requests"],
             &(Jason.decode!(&1["resolved_argument_values_json"]) == %{
                 "amount" => 2,
                 "delay_s" => 5
               })
           )

    refute Jason.encode!(public) =~ "target-secret"
    refute Jason.encode!(public) =~ "item-secret"
    assert {:ok, receipt} = submit(c, held)

    assert Enum.map(receipt["requests"], & &1["request_id"]) ==
             Enum.map(held.batch.requests, & &1.command_request_id)

    assert request_count(c) == 2
    assert Repo.get!(CommandStageRow, c.stage.command_stage_id).lifecycle_state == "draft"

    assert Repo.get!(StagedCommandItemRow, unselected.staged_command_item_id).lifecycle_state ==
             "draft"

    for request <- held.batch.requests do
      persisted =
        Repo.get!(CommandRequestRow, request.command_request_id) |> CommandRequestRow.to_domain()

      assert persisted == request
      assert persisted.source_command_stage_id == c.stage.command_stage_id
    end

    assert {:error, _} = submit(c, held)
    assert request_count(c) == 2

    assert {:ok, ^receipt} =
             StageSubmission.recover(c.scope, c.mission, c.stage.command_stage_id, held)
  end

  test "stale selected item evidence is rejected both before and after preview", c do
    item = item!(c, %{})
    input = selection(c, [item])
    {:ok, held} = StageSubmission.preview(c.scope, c.mission, c.stage.command_stage_id, input)
    {:ok, _} = StageStore.update_item(c.org, %{item | argument_values: %{"amount" => 3}})

    assert {:error, :command_stage_changed} =
             StageSubmission.preview(c.scope, c.mission, c.stage.command_stage_id, input)

    assert {:error, :command_stage_changed} = submit(c, held)
    assert request_count(c) == 0
  end

  test "container edits invalidate retained batch evidence", c do
    item = item!(c, %{})
    held = preview!(c, [item])
    {:ok, _} = StageStore.update_stage(c.org, %{c.stage | stage_name: "Changed preparation"})
    assert {:error, :command_stage_changed} = submit(c, held)
    assert request_count(c) == 0
  end

  test "target identity changes invalidate a preview without inserting a request", c do
    item = item!(c, %{})
    held = preview!(c, [item])
    row = Repo.get!(SourceEndpointRow, c.target.source_endpoint_id)
    Repo.update!(Ecto.Changeset.change(row, display_name: "New target identity"))
    assert {:error, _} = submit(c, held)
    assert request_count(c) == 0
  end

  test "a newly activated command model cannot replace the reviewed model silently", c do
    item = item!(c, %{})
    held = preview!(c, [item])
    CommandAuthoringFixtures.activate!(c.org, c.mission, 3)
    assert {:error, :command_authoring_basis_changed} = submit(c, held)
    assert request_count(c) == 0
  end

  test "a later invalid command cannot yield a partial batch preview or insertion", c do
    first = item!(c, %{})
    second = item!(c, %{item_order: 1, argument_values: %{"amount" => 999}})

    assert {:error, _} =
             StageSubmission.preview(
               c.scope,
               c.mission,
               c.stage.command_stage_id,
               selection(c, [first, second])
             )

    assert request_count(c) == 0

    assert Repo.get!(StagedCommandItemRow, first.staged_command_item_id).lifecycle_state ==
             "draft"
  end

  test "revocation rejects retained previews and read recovery", c do
    item = item!(c, %{})
    held = preview!(c, [item])

    Repo.update_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    assert {:error, :unavailable} = submit(c, held)

    assert {:error, :unavailable} =
             StageSubmission.recover(c.scope, c.mission, c.stage.command_stage_id, held)

    assert request_count(c) == 0
  end

  test "recovery requires exact reserved requests and item pointers while allowing lifecycle advancement",
       c do
    item = item!(c, %{})
    held = preview!(c, [item])

    assert {:error, :unconfirmed} =
             StageSubmission.recover(c.scope, c.mission, c.stage.command_stage_id, held)

    assert {:ok, _} = submit(c, held)
    request = hd(held.batch.requests)
    row = Repo.get!(CommandRequestRow, request.command_request_id)
    Repo.update!(Ecto.Changeset.change(row, lifecycle_state: "validated"))

    assert {:ok, %{"requests" => [%{"state" => "validated"}]}} =
             StageSubmission.recover(c.scope, c.mission, c.stage.command_stage_id, held)

    row = Repo.get!(CommandRequestRow, request.command_request_id)

    Repo.update!(
      Ecto.Changeset.change(row,
        resolved_argument_values_document: %{"value" => %{"amount" => 3, "delay_s" => 5}}
      )
    )

    assert {:error, :unconfirmed} =
             StageSubmission.recover(c.scope, c.mission, c.stage.command_stage_id, held)
  end

  defp submit(c, held) do
    token = StageDrafts.new_write_token()

    StageSubmission.submit(c.scope, c.mission, c.stage.command_stage_id, token, held, %{
      "expected_write" => token,
      "expected_preview" => held.token
    })
  end

  defp preview!(c, items) do
    {:ok, held} =
      StageSubmission.preview(c.scope, c.mission, c.stage.command_stage_id, selection(c, items))

    held
  end

  defp selection(c, items) do
    {:ok, detail} = StageCatalog.workbench(c.scope, c.mission, c.stage.command_stage_id, %{})
    ids = Enum.map(items, & &1.staged_command_item_id)

    selected =
      detail["items"]["entries"]
      |> Enum.filter(&(&1["id"] in ids))
      |> Enum.map(&Map.take(&1, ["id", "expected_item"]))

    %{"expected_stage" => detail["stage"]["expected_stage"], "items" => selected}
  end

  defp request_count(c),
    do:
      Repo.aggregate(from(row in CommandRequestRow, where: row.mission_id == ^c.mission), :count)

  defp item!(c, attrs) do
    {:ok, item} =
      StageStore.persist_item(
        c.org,
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
              metadata: %{"secret" => "item-secret"}
            },
            attrs
          )
        )
      )

    item
  end
end
