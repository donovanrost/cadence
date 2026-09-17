defmodule Cadence.Control.Commanding.WorkspaceSubmissionTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandRequestRow,
    CommandStageRow,
    StagedCommandItemRow
  }

  alias Cadence.Control.Commanding.WorkspaceSubmission
  alias Cadence.Management.Commanding.RequestAuthoring

  setup do
    c = CommandAuthoringFixtures.fixture!()
    second = CommandAuthoringFixtures.target!(c.org, c.mission, %{scid: 8})
    Map.put(c, :second, second)
  end

  test "previews without a stage and atomically queues exact per-endpoint requests once", c do
    assert {:ok, held} = WorkspaceSubmission.preview(c.scope, c.mission, commands(c))
    assert WorkspaceSubmission.current?(held)
    assert {:ok, public} = WorkspaceSubmission.public_preview(held)
    assert length(public["requests"]) == 2
    assert Repo.aggregate(CommandRequestRow, :count) == 0

    assert {:ok, receipt} = submit(c, held)
    assert Enum.all?(receipt["requests"], &(&1["state"] == "queued" && &1["queue_id"]))
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 2
    assert Repo.aggregate(CommandStageRow, :count) == 0
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0

    for {authoring, amount} <- Enum.zip(held.requests, [2, 7]) do
      row = Repo.get!(CommandRequestRow, authoring.request.command_request_id)
      assert row.source_command_stage_id == nil
      assert row.source_staged_command_item_id == nil
      assert row.argument_values_document == %{"value" => %{"amount" => amount}}
      assert row.lifecycle_state == "queued"
    end

    assert {:ok, ^receipt} = WorkspaceSubmission.recover(c.scope, c.mission, held)
    assert {:error, _} = submit(c, held)
    assert Repo.aggregate(CommandRequestRow, :count) == 2
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 2
  end

  test "approval-required commands become requests without admitting queue entries", c do
    assert {:ok, held} = WorkspaceSubmission.preview(c.scope, c.mission, commands(c, "COMMAND_1"))
    assert {:ok, receipt} = submit(c, held)

    assert Enum.all?(
             receipt["requests"],
             &(&1["state"] == "approval_pending" && is_nil(&1["queue_id"]))
           )

    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert {:ok, ^receipt} = WorkspaceSubmission.recover(c.scope, c.mission, held)
  end

  test "duplicate targets, oversized selections and invalid values cannot be previewed", c do
    [first, second] = commands(c)

    for input <- [
          [],
          [first, first],
          List.duplicate(first, 26),
          [first, Map.put(second, "argument_values_json", ~s({"amount":999}))]
        ] do
      assert {:error, _} = WorkspaceSubmission.preview(c.scope, c.mission, input)
    end

    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  test "a changed target rejects the whole batch", c do
    assert {:ok, held} = WorkspaceSubmission.preview(c.scope, c.mission, commands(c))

    row = Repo.get!(Cadence.SourceEndpoints.SourceEndpointRow, c.second.source_endpoint_id)
    Repo.update!(Ecto.Changeset.change(row, scid: 12))

    refute WorkspaceSubmission.current?(held)
    assert {:error, _} = submit(c, held)
    assert Repo.aggregate(CommandRequestRow, :count) == 0
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
  end

  test "a later insertion failure rolls back earlier requests and queue entries", c do
    assert {:ok, held} = WorkspaceSubmission.preview(c.scope, c.mission, commands(c))
    second = Enum.at(held.requests, 1)

    assert {:ok, _} =
             RequestAuthoring.create(c.scope, c.mission, second, %{
               "expected_preview" => second.token
             })

    assert {:error, _} = submit(c, held)
    assert Repo.aggregate(CommandRequestRow, :count) == 1
    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert {:error, :unconfirmed} = WorkspaceSubmission.recover(c.scope, c.mission, held)
  end

  test "consumption requires exact preview and write tokens and fresh authorization", c do
    assert {:ok, held} = WorkspaceSubmission.preview(c.scope, c.mission, commands(c))

    for input <- [
          %{"expected_write" => "wrong", "expected_preview" => held.token},
          %{"expected_write" => "write", "expected_preview" => "wrong"},
          %{
            "expected_write" => "write",
            "expected_preview" => held.token,
            "commands" => commands(c)
          }
        ] do
      assert {:error, _} = WorkspaceSubmission.submit(c.scope, c.mission, "write", held, input)
    end

    Repo.update_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    assert {:error, :unavailable} = submit(c, held)
    assert {:error, :unconfirmed} = WorkspaceSubmission.recover(c.scope, c.mission, held)
    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  defp submit(c, held),
    do:
      WorkspaceSubmission.submit(c.scope, c.mission, "write", held, %{
        "expected_write" => "write",
        "expected_preview" => held.token
      })

  defp commands(c, name \\ "COMMAND_2") do
    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    for {target, amount} <- [{c.target, 2}, {c.second, 7}] do
      %{
        "expected_basis" => catalog["basis"]["token"],
        "source_endpoint_ref" => target.source_endpoint_id,
        "command_id" => c.model.commands_by_name[name],
        "argument_values_json" => Jason.encode!(%{"amount" => amount}),
        "priority" => 3,
        "not_before" => nil,
        "expires_at" => nil
      }
    end
  end
end
