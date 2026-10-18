defmodule Cadence.Management.Commanding.AuthoringConcurrencyTest do
  use Cadence.DataCase, async: false
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Activations
  alias Cadence.Activations.{ActiveBindingSetRow, BindingSetActivationRow}
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandRequestRow, RequestStore}
  alias Cadence.Governance.BindingSetRow
  alias Cadence.Management.Commanding.RequestAuthoring
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
        {:ok, model} = RequestAuthoring.load(c.scope, c.mission, %{})

        {:ok, held} =
          RequestAuthoring.preview(c.scope, c.mission, %{
            "expected_basis" => model["basis"]["token"],
            "source_endpoint_ref" => c.target.source_endpoint_id,
            "command_id" => c.model.commands_by_name["COMMAND_1"],
            "argument_values_json" => Jason.encode!(%{"amount" => 2}),
            "priority" => 3,
            "not_before" => nil,
            "expires_at" => nil
          })

        Map.put(c, :held, held)
      end)
      |> Task.await(10_000)

    on_exit(fn -> independent(fn -> cleanup(c) end) |> Task.await(10_000) end)
    {:ok, c}
  end

  test "a real activation cannot replace the reviewed basis before request insertion commits",
       c do
    parent = self()

    creator =
      independent(fn ->
        RequestStore.persist_reviewed_request(
          c.org,
          c.held.request,
          c.held.expected_basis,
          c.held.expected_target,
          fn ->
            send(parent, {:ready_to_insert, self()})

            receive do
              :insert -> :ok
            after
              10_000 -> {:error, :test_release_timeout}
            end
          end
        )
      end)

    assert_receive {:ready_to_insert, creator_pid}, 5_000

    activation =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:activation_backend, pid})
        {:ok, current} = Activations.fetch_active_activation(c.org, c.mission)

        Activations.record_binding_set_activation(
          c.org,
          c.mission,
          current.binding_set_id,
          current.binding_set_version,
          binding_set_content_sha256: current.binding_set_content_sha256,
          metadata: current.metadata
        )
      end)

    try do
      assert_receive {:activation_backend, pid}, 5_000
      assert wait_for_lock(pid, 300)

      refute independent(fn -> Repo.get(CommandRequestRow, c.held.request.command_request_id) end)
             |> Task.await()

      send(creator_pid, :insert)
      assert {:ok, request} = Task.await(creator, 10_000)
      assert request == c.held.request
      assert {:ok, next} = Task.await(activation, 10_000)
      assert next.generation == 2

      assert {:ok, receipt} =
               independent(fn -> RequestAuthoring.recover(c.scope, c.mission, c.held) end)
               |> Task.await()

      assert receipt["request_id"] == request.command_request_id
    after
      send(creator_pid, :insert)
      Task.shutdown(creator, :brutal_kill)
      Task.shutdown(activation, :brutal_kill)
    end
  end

  test "a creation waiting on the active pointer rejects a changed generation", c do
    {blocker, blocker_pid} = block_active_pointer(c, true)
    parent = self()

    creator =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:creator_backend, pid})
        RequestAuthoring.create(c.scope, c.mission, c.held, %{"expected_preview" => c.held.token})
      end)

    try do
      assert_receive {:creator_backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(blocker_pid, :release)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      assert {:error, :command_authoring_basis_changed} = Task.await(creator, 10_000)

      refute independent(fn -> Repo.get(CommandRequestRow, c.held.request.command_request_id) end)
             |> Task.await()
    after
      send(blocker_pid, :release)
      Task.shutdown(blocker, :brutal_kill)
      Task.shutdown(creator, :brutal_kill)
    end
  end

  test "access revoked while creation waits is rechecked immediately before the insert", c do
    {blocker, blocker_pid} = block_active_pointer(c, false)
    parent = self()

    creator =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:creator_backend, pid})
        RequestAuthoring.create(c.scope, c.mission, c.held, %{"expected_preview" => c.held.token})
      end)

    try do
      assert_receive {:creator_backend, pid}, 5_000
      assert wait_for_lock(pid, 300)

      independent(fn ->
        Repo.get!(UserRow, c.user.user_id)
        |> Ecto.Changeset.change(lifecycle_state: "disabled")
        |> Repo.update!()
      end)
      |> Task.await()

      send(blocker_pid, :release)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      assert {:error, :unavailable} = Task.await(creator, 10_000)

      refute independent(fn -> Repo.get(CommandRequestRow, c.held.request.command_request_id) end)
             |> Task.await()
    after
      send(blocker_pid, :release)
      Task.shutdown(blocker, :brutal_kill)
      Task.shutdown(creator, :brutal_kill)
    end
  end

  defp block_active_pointer(c, change?) do
    parent = self()

    task =
      independent(fn ->
        Repo.transaction(fn -> hold_active_pointer(c, change?, parent) end)
      end)

    assert_receive {:pointer_locked, pid}, 5_000
    {task, pid}
  end

  defp hold_active_pointer(c, change?, parent) do
    row =
      Repo.one!(
        from(row in ActiveBindingSetRow,
          where: row.organization_id == ^c.org and row.mission_id == ^c.mission,
          lock: "FOR UPDATE"
        )
      )

    if change?, do: Repo.update!(Ecto.Changeset.change(row, generation: row.generation + 1))
    send(parent, {:pointer_locked, self()})
    await_pointer_release()
  end

  defp await_pointer_release do
    receive do
      :release -> :released
    after
      10_000 -> raise "pointer release not delivered"
    end
  end

  defp wait_for_lock(_, 0), do: false

  defp wait_for_lock(pid, remaining) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM pg_locks WHERE pid = $1 AND NOT granted", [pid])

    if count > 0,
      do: true,
      else:
        (
          Process.sleep(10)
          wait_for_lock(pid, remaining - 1)
        )
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
          CommandRequestRow,
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
        from(row in schema, where: row.organization_id == ^c.org and row.mission_id == ^c.mission)
      )
    end

    Repo.delete_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      )
    )

    Repo.delete_all(from(row in UserRow, where: row.user_id == ^c.user.user_id))
    Repo.delete_all(from(row in OrganizationRow, where: row.organization_id == ^c.org))
  end
end
