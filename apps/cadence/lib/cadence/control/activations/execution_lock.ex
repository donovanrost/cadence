defmodule Cadence.Control.Activations.ExecutionLock do
  @moduledoc """
  One executor per activation request at a time (director, 2026-11-13): an execution or a resume
  holds a session advisory lock keyed by the request for its whole run, so two resumes, or a
  resume racing a live execute, can't interleave.

  The lock lives on its own connection, linked to the executor, not on one checked out from the
  pool: the execution itself uses the pool as usual (and the runtime processes it calls need
  connections of their own). If the executor dies, its linked connection closes, and if the
  database drops, the session ends; either way the database releases the lock, which is what lets
  a stalled execution be resumed.
  """

  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  # Repo settings that aren't the database session's.
  @pool_keys [:name, :pool, :pool_size, :queue_target, :queue_interval, :telemetry_prefix]

  @doc """
  Runs `fun` holding the request's lock, or returns `{:error, :activation_execution_in_progress}`
  when another executor holds it. Raises `DBConnection.ConnectionError` when the database can't be
  reached.
  """
  @spec run(binary(), (-> result)) :: result | {:error, :activation_execution_in_progress}
        when result: term()
  def run(activation_request_id, fun) when is_binary(activation_request_id) do
    key = key(activation_request_id)
    conn = connect!()

    try do
      if acquire?(conn, key) do
        try do
          fun.()
        after
          release(conn, key)
        end
      else
        {:error, :activation_execution_in_progress}
      end
    after
      GenServer.stop(conn)
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

  defp connect! do
    opts =
      Repo.config()
      |> Keyword.drop(@pool_keys)
      |> Keyword.merge(pool_size: 1, backoff_type: :stop, sync_connect: true)

    case Postgrex.start_link(opts) do
      {:ok, conn} -> conn
      {:error, %DBConnection.ConnectionError{} = error} -> raise error
      {:error, reason} -> raise DBConnection.ConnectionError, inspect(reason)
    end
  end

  @doc false
  def key(activation_request_id) do
    <<key::signed-64, _rest::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, activation_request_id}))

    key
  end
end
