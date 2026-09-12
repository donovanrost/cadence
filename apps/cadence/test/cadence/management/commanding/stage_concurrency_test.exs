defmodule Cadence.Management.Commanding.StageConcurrencyTest do
  use Cadence.DataCase, async: false
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Activations.{ActiveBindingSetRow, BindingSetActivationRow}
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Management.Commanding.{StageCatalog, StageDrafts, StageSubmission}

  alias Cadence.Commanding.{
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    StagedCommandItem,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Governance.BindingSetRow
  alias Cadence.MissionModels.{LayerRow, RevisionRow}
  alias Cadence.Missions.MissionRow
  alias Cadence.OperationalEvents.EventRow
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Projections.MissionEvents.Store.MissionEventRow
  alias Cadence.SourceEndpoints.SourceEndpointRow

  setup do
    c =
      independent(fn ->
        c = CommandAuthoringFixtures.fixture!()

        {:ok, stage} =
          StageStore.persist_stage(
            c.org,
            CommandStage.new(%{
              organization_id: c.org,
              mission_id: c.mission,
              stage_name: "Concurrent preparation",
              owner: %{"user_id" => c.user.user_id},
              visibility: :shared
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
              command_id: c.model.commands_by_name["COMMAND_1"],
              argument_values: %{"amount" => 2}
            })
          )

        Map.merge(c, %{stage: stage, item: item})
      end)
      |> Task.await(10_000)

    on_exit(fn -> independent(fn -> cleanup(c) end) |> Task.await(10_000) end)
    c
  end

  test "a stage read and draft write reauthorize after waiting behind the stage lock", c do
    {:ok, detail} =
      independent(fn ->
        StageCatalog.workbench(c.scope, c.mission, c.stage.command_stage_id, %{
          "item" => c.item.staged_command_item_id
        })
      end)
      |> Task.await()

    token = StageDrafts.new_write_token()

    input = %{
      "expected_write" => token,
      "expected_stage" => detail["stage"]["expected_stage"],
      "expected_item" => detail["selected_item"]["expected_item"],
      "notes" => "Revoked edit",
      "order" => 9
    }

    {blocker, release} = block_stage(c)
    parent = self()

    reader =
      contender(parent, fn ->
        StageCatalog.workbench(c.scope, c.mission, c.stage.command_stage_id, %{})
      end)

    writer =
      contender(parent, fn ->
        StageDrafts.edit_details(
          c.scope,
          c.mission,
          c.stage.command_stage_id,
          c.item.staged_command_item_id,
          token,
          input
        )
      end)

    try do
      await_contenders(2)

      independent(fn ->
        Repo.update_all(
          from(row in OrganizationMembershipRow,
            where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
          ),
          set: [lifecycle_state: "revoked"]
        )
      end)
      |> Task.await()

      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)
      assert {:error, :unavailable} = Task.await(reader)
      assert {:error, :unavailable} = Task.await(writer)
      assert %{request_count: 0, draft_count: 1} = persisted(c)

      actual =
        independent(fn -> Repo.get!(StagedCommandItemRow, c.item.staged_command_item_id) end)
        |> Task.await()

      assert actual.item_order == 0
      assert actual.notes == nil
    after
      send(release, :release)
      Enum.each([blocker, reader, writer], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "two independent submissions create exactly one request for a staged item", c do
    {blocker, release} = block_stage(c)
    parent = self()
    tasks = for _ <- 1..2, do: contender(parent, fn -> submit(c) end)

    try do
      await_contenders(2)
      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      assert length(Enum.filter(results, &match?({:ok, [_]}, &1))) == 1
      assert length(Enum.filter(results, &match?({:error, _}, &1))) == 1

      assert %{state: "submitted", request_count: 1, draft_count: 0, submitted_count: 1} =
               persisted(c)
    after
      send(release, :release)
      Enum.each([blocker | tasks], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "two exact reviewed submissions serialize to one durable batch", c do
    held = reviewed_batch(c)
    {blocker, release} = block_stage(c)
    parent = self()
    tasks = for _ <- 1..2, do: contender(parent, fn -> submit_reviewed(c, held) end)

    try do
      await_contenders(2)
      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert length(
               Enum.filter(results, &match?({:ok, %{"operation" => "requests_created"}}, &1))
             ) == 1

      assert length(Enum.filter(results, &match?({:error, _}, &1))) == 1
      assert %{state: "submitted", request_count: 1, draft_count: 0} = persisted(c)
    after
      send(release, :release)
      Enum.each([blocker | tasks], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "reviewed submission reauthorizes after waiting for its target identity lock", c do
    held = reviewed_batch(c)
    parent = self()

    blocker =
      independent(fn ->
        Repo.transaction(fn ->
          Repo.one!(
            from(row in SourceEndpointRow,
              where:
                row.organization_id == ^c.org and row.mission_id == ^c.mission and
                  row.source_endpoint_id == ^c.target.source_endpoint_id,
              lock: "FOR UPDATE"
            )
          )

          send(parent, {:target_locked, self()})
          await_release()
        end)
      end)

    assert_receive {:target_locked, release}, 5_000
    submitter = contender(parent, fn -> submit_reviewed(c, held) end)

    try do
      await_contenders(1)

      independent(fn ->
        Repo.update_all(
          from(row in OrganizationMembershipRow,
            where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
          ),
          set: [lifecycle_state: "revoked"]
        )
      end)
      |> Task.await()

      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)
      assert {:error, :unavailable} = Task.await(submitter)
      assert %{state: "draft", request_count: 0, draft_count: 1} = persisted(c)
    after
      send(release, :release)
      Enum.each([blocker, submitter], &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp reviewed_batch(c) do
    independent(fn ->
      {:ok, detail} = StageCatalog.workbench(c.scope, c.mission, c.stage.command_stage_id, %{})
      items = Enum.map(detail["items"]["entries"], &Map.take(&1, ["id", "expected_item"]))

      {:ok, held} =
        StageSubmission.preview(c.scope, c.mission, c.stage.command_stage_id, %{
          "expected_stage" => detail["stage"]["expected_stage"],
          "items" => items
        })

      held
    end)
    |> Task.await(10_000)
  end

  defp submit_reviewed(c, held) do
    token = StageDrafts.new_write_token()

    StageSubmission.submit(c.scope, c.mission, c.stage.command_stage_id, token, held, %{
      "expected_write" => token,
      "expected_preview" => held.token
    })
  end

  test "an editor waits while an uncommitted submission owns the stage", c do
    parent = self()
    token = make_ref()
    handler = {__MODULE__, token}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        &pause_after_insert/4,
        {parent, token}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    creator =
      independent(fn ->
        Process.put(:stage_submission_pause, token)
        submit(c)
      end)

    assert_receive {:inserted_uncommitted, creator_pid}, 5_000

    editor =
      contender(parent, fn ->
        StageStore.update_item(c.org, %{c.item | argument_values: %{"amount" => 3}})
      end)

    try do
      await_contenders(1)
      assert %{request_count: 0} = persisted(c)
      send(creator_pid, :release)
      assert {:ok, [request]} = Task.await(creator, 10_000)
      assert {:error, _} = Task.await(editor, 10_000)
      assert request.argument_values == %{"amount" => 2}
      assert %{request_count: 1, submitted_count: 1} = persisted(c)
    after
      send(creator_pid, :release)
      Enum.each([creator, editor], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "adding a draft and submitting the final item serialize without losing the new draft", c do
    {blocker, release} = block_stage(c)
    parent = self()

    extra = %{
      c.item
      | staged_command_item_id: Cadence.Ids.new("staged_command_item"),
        item_order: 1
    }

    adder = contender(parent, fn -> StageStore.persist_item(c.org, extra) end)
    submitter = contender(parent, fn -> submit(c) end)

    try do
      await_contenders(2)
      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)
      assert {:ok, [_]} = Task.await(submitter, 10_000)

      case Task.await(adder, 10_000) do
        {:ok, _} ->
          assert %{state: "draft", request_count: 1, draft_count: 1} = persisted(c)

        {:error, _} ->
          assert %{state: "submitted", request_count: 1, draft_count: 0} = persisted(c)
      end
    after
      send(release, :release)
      Enum.each([blocker, adder, submitter], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "stage cancellation and submission cannot both succeed", c do
    {blocker, release} = block_stage(c)
    parent = self()

    canceler =
      contender(parent, fn ->
        StageStore.update_stage(c.org, %{c.stage | lifecycle_state: :canceled})
      end)

    submitter = contender(parent, fn -> submit(c) end)

    try do
      await_contenders(2)
      send(release, :release)
      assert {:ok, :released} = Task.await(blocker)

      case {Task.await(canceler, 10_000), Task.await(submitter, 10_000)} do
        {{:ok, _}, {:error, _}} -> assert %{state: "canceled", request_count: 0} = persisted(c)
        {{:error, _}, {:ok, [_]}} -> assert %{state: "submitted", request_count: 1} = persisted(c)
        other -> flunk("Unexpected concurrent outcomes: #{inspect(other)}")
      end
    after
      send(release, :release)
      Enum.each([blocker, canceler, submitter], &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp submit(c),
    do:
      StageStore.submit_items(
        c.org,
        c.mission,
        c.stage.command_stage_id,
        [c.item.staged_command_item_id],
        %{"user_id" => c.user.user_id}
      )

  defp pause_after_insert(_, _, metadata, {parent, token}) do
    if Process.get(:stage_submission_pause) == token and
         String.starts_with?(metadata.query, "INSERT INTO \"command_requests\"") do
      Process.delete(:stage_submission_pause)
      send(parent, {:inserted_uncommitted, self()})
      await_release()
    end
  end

  defp contender(parent, operation) do
    independent(fn ->
      %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
      send(parent, {:contender, pid})
      operation.()
    end)
  end

  defp await_contenders(count) do
    for _ <- 1..count do
      assert_receive {:contender, pid}, 5_000
      assert wait_for_lock(pid, 300)
    end
  end

  defp block_stage(c) do
    parent = self()

    task =
      independent(fn ->
        Repo.transaction(fn ->
          Repo.one!(
            from(r in CommandStageRow,
              where:
                r.organization_id == ^c.org and r.command_stage_id == ^c.stage.command_stage_id,
              lock: "FOR UPDATE"
            )
          )

          send(parent, {:stage_locked, self()})
          await_release()
        end)
      end)

    assert_receive {:stage_locked, pid}, 5_000
    {task, pid}
  end

  defp await_release do
    receive do
      :release -> :released
    after
      10_000 -> raise "stage test release not delivered"
    end
  end

  defp wait_for_lock(_, 0), do: false

  defp wait_for_lock(pid, remaining) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM pg_locks WHERE pid = $1 AND NOT granted", [pid])

    if count > 0 do
      true
    else
      Process.sleep(10)
      wait_for_lock(pid, remaining - 1)
    end
  end

  defp persisted(c) do
    independent(fn ->
      stage = Repo.get!(CommandStageRow, c.stage.command_stage_id)

      %{
        state: stage.lifecycle_state,
        request_count:
          Repo.aggregate(
            from(r in CommandRequestRow,
              where: r.organization_id == ^c.org and r.mission_id == ^c.mission
            ),
            :count
          ),
        draft_count:
          Repo.aggregate(
            from(r in StagedCommandItemRow,
              where:
                r.organization_id == ^c.org and r.mission_id == ^c.mission and
                  r.lifecycle_state == "draft"
            ),
            :count
          ),
        submitted_count:
          Repo.aggregate(
            from(r in StagedCommandItemRow,
              where:
                r.organization_id == ^c.org and r.mission_id == ^c.mission and
                  r.lifecycle_state == "submitted"
            ),
            :count
          )
      }
    end)
    |> Task.await()
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp cleanup(c) do
    for schema <- [
          StagedCommandItemRow,
          CommandRequestRow,
          CommandStageRow,
          EventRow,
          MissionEventRow,
          ActiveBindingSetRow,
          BindingSetActivationRow,
          BindingSetRow,
          SourceEndpointRow,
          RevisionRow,
          LayerRow,
          MissionRow
        ] do
      Repo.delete_all(
        from(r in schema, where: r.organization_id == ^c.org and r.mission_id == ^c.mission)
      )
    end

    Repo.delete_all(
      from(r in OrganizationMembershipRow,
        where: r.organization_id == ^c.org and r.user_id == ^c.user.user_id
      )
    )

    Repo.delete_all(from(r in UserRow, where: r.user_id == ^c.user.user_id))
    Repo.delete_all(from(r in OrganizationRow, where: r.organization_id == ^c.org))
  end
end
