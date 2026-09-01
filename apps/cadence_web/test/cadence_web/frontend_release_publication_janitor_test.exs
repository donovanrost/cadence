defmodule CadenceWeb.FrontendReleasePublicationJanitorTest do
  use Cadence.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias CadenceWeb.FrontendReleasePublication.Janitor

  test "the web supervisor starts the fixed production janitor" do
    assert {Janitor, janitor, :worker, _modules} =
             Enum.find(Supervisor.which_children(CadenceWeb.Supervisor), fn
               {Janitor, _pid, _type, _modules} -> true
               _child -> false
             end)

    assert janitor == Process.whereis(Janitor)
  end

  test "supervised janitor invokes cleanup and reschedules after success" do
    name = unique_name(:success)
    janitor = start_supervised!({Janitor, name: name, interval_ms: 10})
    :ok = Sandbox.allow(Repo, self(), janitor)

    first_digest = insert_expired_stage!("janitor-success-first")
    send(janitor, :cleanup)
    assert eventually(fn -> staged_count(first_digest) end)

    second_digest = insert_expired_stage!("janitor-success-second")
    assert eventually(fn -> staged_count(second_digest) end)
    assert Process.alive?(janitor)
  end

  test "expected database failure does not stop janitor, Repo, or PubSub and reschedules" do
    name = unique_name(:failure)
    janitor = start_supervised!({Janitor, name: name, interval_ms: 60_000})
    initial_timer = timer_ref(janitor)
    owner = self()

    sandbox_owner =
      Task.async(fn ->
        try do
          :ok = Sandbox.checkout(Repo)
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()", []).rows
          send(owner, {:janitor_backend, backend_pid})

          receive do
            :release -> :ok
          after
            10_000 -> :timeout
          end
        after
          try do
            Sandbox.checkin(Repo)
          catch
            _kind, _reason -> :ok
          end
        end
      end)

    assert_receive {:janitor_backend, backend_pid}, 5_000
    :ok = Sandbox.allow(Repo, sandbox_owner.pid, janitor)

    handler_id = {__MODULE__, :janitor_db_failure, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, %{query: query}, {owner, backend_pid} ->
          if String.contains?(query, "DELETE FROM frontend_release_staged_objects") do
            terminate_backend!(backend_pid)
            send(owner, :janitor_cleanup_failed)
          end
        end,
        {owner, backend_pid}
      )

    try do
      send(janitor, :cleanup)
      assert_receive :janitor_cleanup_failed, 5_000
      assert Process.alive?(janitor)
      assert Process.alive?(Process.whereis(Cadence.Repo))
      assert Process.alive?(Process.whereis(CadenceWeb.PubSub))
      assert timer_ref(janitor) != initial_timer
    after
      :telemetry.detach(handler_id)
      send(sandbox_owner.pid, :release)
      assert :ok = Task.await(sandbox_owner, 5_000)
    end
  end

  defp timer_ref(janitor) do
    %{timer_ref: timer_ref} = :sys.get_state(janitor)
    timer_ref
  end

  defp insert_expired_stage!(seed) do
    digest = :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
    bytes = seed <> "-bytes"

    Repo.query!(
      """
      INSERT INTO frontend_release_staged_objects (sha256, size, expires_at, inserted_at)
      VALUES ($1, $2, now() - interval '1 hour', now())
      """,
      [digest, byte_size(bytes)]
    )

    Repo.query!(
      """
      INSERT INTO frontend_release_staged_object_chunks
        (sha256, chunk_index, bytes, size, inserted_at)
      VALUES ($1, 0, $2, $3, now())
      """,
      [digest, bytes, byte_size(bytes)]
    )

    digest
  end

  defp staged_count(digest) do
    Repo.query!(
      "SELECT COUNT(*) FROM frontend_release_staged_objects WHERE sha256 = $1",
      [digest]
    ).rows == [[0]]
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end

  defp unique_name(suffix),
    do:
      String.to_atom(
        "frontend_release_janitor_test_#{suffix}_#{System.unique_integer([:positive])}"
      )

  defp terminate_backend!(backend_pid) do
    repo_config = Application.fetch_env!(:cadence, Repo)

    connection_options =
      repo_config
      |> Keyword.take([:username, :password, :hostname, :database, :port, :socket_dir, :ssl])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {:ok, connection} = Postgrex.start_link(connection_options)

    try do
      %{rows: [[true]]} =
        Postgrex.query!(connection, "SELECT pg_terminate_backend($1)", [backend_pid])
    after
      GenServer.stop(connection)
    end
  end
end
