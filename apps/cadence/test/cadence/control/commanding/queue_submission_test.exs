defmodule Cadence.Control.Commanding.QueueSubmissionTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandReleaseAttemptRow, CommandRequestRow}
  alias Cadence.Control.Commanding.QueueSubmission
  alias Cadence.Management.Commanding.RequestAuthoring

  setup do
    {:ok, CommandAuthoringFixtures.fixture!()}
  end

  test "native safe request admits one exact queue operation and recovers its immutable receipt",
       c do
    request = create_request(c, "COMMAND_2")
    assert {:ok, loaded} = QueueSubmission.load(c.scope, c.mission, request)
    assert loaded.model["availability"] == "available"
    held = loaded.held
    preview = QueueSubmission.public_preview(held)

    assert Jason.decode!(preview["request"]["resolved_argument_values_json"]) == %{
             "amount" => 2,
             "delay_s" => 5
           }

    if file = System.get_env("CADENCE_QUEUE_FIXTURE_PATH"),
      do:
        File.write!(file, Jason.encode!(%{model: loaded.model, preview: preview, operation: nil}))

    assert {:ok, receipt} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => held.token})

    assert receipt["operation_id"] == held.operation_id
    assert receipt["actor_id"] == c.user.user_id
    assert {:ok, ^receipt} = QueueSubmission.recover(c.scope, c.mission, held)

    assert {:error, _} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => held.token})

    assert 1 == queue_count(c)

    refute Repo.exists?(
             from(row in CommandReleaseAttemptRow, where: row.mission_id == ^c.mission)
           )

    assert {:ok, current} = QueueSubmission.load(c.scope, c.mission, request)
    assert current.model["availability"] == "queued"
    assert current.held == nil
    assert current.model["queue"]["id"] == receipt["queue_id"]
  end

  test "a hazardous request has no queue preview before human approval", c do
    request = create_request(c, "COMMAND_1")
    assert {:ok, loaded} = QueueSubmission.load(c.scope, c.mission, request)
    assert loaded.model["availability"] == "approval_required"
    assert loaded.held == nil
    assert {:error, _} = QueueSubmission.submit(c.scope, c.mission, nil, %{})
    assert queue_count(c) == 0
  end

  test "revoked membership rejects a retained queue preview and receipt reads", c do
    request = create_request(c, "COMMAND_2")
    {:ok, %{held: held}} = QueueSubmission.load(c.scope, c.mission, request)

    Repo.update_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    assert {:error, :unavailable} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => held.token})

    assert {:error, :unavailable} = QueueSubmission.load(c.scope, c.mission, request)
    assert {:error, :unconfirmed} = QueueSubmission.recover(c.scope, c.mission, held)
    assert queue_count(c) == 0
  end

  test "another operation's queue is not attributed to the retained submission", c do
    request = create_request(c, "COMMAND_2")
    {:ok, %{held: first}} = QueueSubmission.load(c.scope, c.mission, request)
    {:ok, %{held: second}} = QueueSubmission.load(c.scope, c.mission, request)
    assert first.operation_id != second.operation_id

    assert {:ok, receipt} =
             QueueSubmission.submit(c.scope, c.mission, second, %{
               "expected_queue" => second.token
             })

    assert {:error, :unconfirmed} = QueueSubmission.recover(c.scope, c.mission, first)
    assert {:ok, ^receipt} = QueueSubmission.recover(c.scope, c.mission, second)
    assert queue_count(c) == 1
  end

  test "changed approved content and malformed confirmation inputs cannot admit a request", c do
    request = create_request(c, "COMMAND_2")
    {:ok, %{held: held}} = QueueSubmission.load(c.scope, c.mission, request)

    assert {:error, _} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => "wrong"})

    assert {:error, _} =
             QueueSubmission.submit(c.scope, c.mission, held, %{
               "expected_queue" => held.token,
               "actor_id" => "other"
             })

    row = Repo.get!(CommandRequestRow, request)
    Repo.update!(Ecto.Changeset.change(row, priority: row.priority + 1))

    assert {:error, :approved_command_basis_changed} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => held.token})

    assert queue_count(c) == 0
  end

  defp create_request(c, command) do
    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    input = %{
      "expected_basis" => catalog["basis"]["token"],
      "source_endpoint_ref" => c.target.source_endpoint_id,
      "command_id" => c.model.commands_by_name[command],
      "argument_values_json" => Jason.encode!(%{"amount" => 2}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }

    {:ok, preview} = RequestAuthoring.preview(c.scope, c.mission, input)

    {:ok, receipt} =
      RequestAuthoring.create(c.scope, c.mission, preview, %{"expected_preview" => preview.token})

    receipt["request_id"]
  end

  defp queue_count(c),
    do:
      Repo.aggregate(
        from(row in CommandQueueEntryRow, where: row.mission_id == ^c.mission),
        :count
      )
end
