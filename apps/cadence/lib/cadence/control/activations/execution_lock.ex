defmodule Cadence.Control.Activations.ExecutionLock do
  @moduledoc """
  One executor per activation request at a time (director, 2026-11-13): an execution or a resume
  holds a session advisory lock keyed by the request for its whole run, so two resumes, or a
  resume racing a live execute, can't interleave.

  The lock lives on its own Postgres session, held by a small process that monitors the executor,
  not on a connection checked out from the pool: the execution itself uses the pool as usual (and
  the runtime processes it calls need connections of their own). If the executor dies, the holder
  ends its session; if the database drops, the session ends; either way Postgres releases the
  lock, which is what lets a stalled execution be resumed. A session that can't start (the
  database at max connections, say) raises `DBConnection.ConnectionError` in the executor, never
  an exit signal.
  """

  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  # Repo settings that aren't the database session's.
  @pool_keys [:name, :pool, :pool_size, :queue_target, :queue_interval, :telemetry_prefix]
  @connect_ms 30_000

  @doc """
  Runs `fun` holding the request's lock, or returns `{:error, :activation_execution_in_progress}`
  when another executor holds it. Raises `DBConnection.ConnectionError` when the database can't be
  reached.
  """
  @spec run(binary(), (-> result)) :: result | {:error, :activation_execution_in_progress}
        when result: term()
  def run(activation_request_id, fun) when is_binary(activation_request_id) do
    key = key(activation_request_id)
    caller = self()
    {holder, ref} = spawn_monitor(fn -> hold(caller, key) end)

    receive do
      {^holder, :locked} ->
        try do
          fun.()
        after
          send(holder, :release)
          await_down(ref)
        end

      {^holder, :busy} ->
        await_down(ref)
        {:error, :activation_execution_in_progress}

      {:DOWN, ^ref, :process, _holder, reason} ->
        raise DBConnection.ConnectionError, "activation lock session failed: #{inspect(reason)}"
    after
      @connect_ms ->
        Process.exit(holder, :kill)
        raise DBConnection.ConnectionError, "activation lock session timed out"
    end
  end

  # The holder owns the lock's session: unlinked from the executor (so a session that can't
  # start is an error for the executor, not an exit signal), monitoring it (so the session, and
  # the lock, end when the executor does).
  defp hold(caller, key) do
    Process.flag(:trap_exit, true)
    watched = Process.monitor(caller)
    {:ok, conn} = Postgrex.start_link(session_opts())

    if acquire?(conn, key) do
      send(caller, {self(), :locked})
      held(watched, conn, key)
    else
      send(caller, {self(), :busy})
    end
  end

  defp held(watched, conn, key) do
    receive do
      :release ->
        release(conn, key)
        GenServer.stop(conn)

      # The executor died: ending this process ends the linked session, and Postgres frees the lock.
      {:DOWN, ^watched, :process, _caller, _reason} ->
        exit(:executor_down)

      {:EXIT, ^conn, reason} ->
        exit({:lock_session_closed, reason})
    end
  end

  defp await_down(ref) do
    receive do
      {:DOWN, ^ref, :process, _holder, _reason} -> :ok
    after
      5_000 -> :ok
    end
  end

  @doc "Whether no executor holds the request's lock right now (a stalled execution's test)."
  @spec free?(binary()) :: boolean()
  def free?(activation_request_id) when is_binary(activation_request_id) do
    # pg_locks splits a bigint advisory key into two 32-bit words (classid high, objid low);
    # shifted back together as a bigint they're the signed key again.
    %{rows: [[held]]} =
      SQL.query!(
        Repo,
        """
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND objsubid = 1 AND granted
          AND ((classid::bigint << 32) | objid::bigint) = $1::bigint
        """,
        [key(activation_request_id)]
      )

    held == 0
  end

  defp acquire?(conn, key) do
    %{rows: [[locked?]]} = Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1::bigint)", [key])
    locked?
  end

  # A dropped connection already released it; nothing to undo then.
  defp release(conn, key) do
    Postgrex.query!(conn, "SELECT pg_advisory_unlock($1::bigint)", [key])
    :ok
  rescue
    _exception in [DBConnection.ConnectionError, Postgrex.Error] -> :ok
  end

  defp session_opts do
    Repo.config()
    |> Keyword.drop(@pool_keys)
    |> Keyword.merge(pool_size: 1, backoff_type: :stop, sync_connect: true)
  end

  @doc false
  def key(activation_request_id) do
    <<key::signed-64, _rest::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, activation_request_id}))

    key
  end
end
