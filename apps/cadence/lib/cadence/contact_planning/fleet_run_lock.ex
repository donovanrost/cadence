defmodule Cadence.ContactPlanning.FleetRunLock do
  @moduledoc "Fleet orchestration exclusion on a dedicated PostgreSQL session, independent of worker transactions."
  alias Cadence.Repo

  @connection_keys ~w(hostname endpoints socket_dir socket port database username password parameters ssl socket_options types prepare connect_timeout timeout handshake_timeout ping_timeout after_connect)a

  def with_run(organization_id, mission_id, run_id, callback) when is_function(callback, 0) do
    with_key(["cadence.fleet.run", organization_id, mission_id, run_id], callback)
  end

  @doc "Runs `callback` holding a session advisory lock named by `parts` (cluster-wide)."
  def with_key(parts, callback) when is_list(parts) and is_function(callback, 0) do
    key = key(parts)
    owned_key = {__MODULE__, key}

    if Process.get(owned_key) do
      callback.()
    else
      connect(key, owned_key, callback)
    end
  end

  @doc """
  True while some session (on any node) holds the run's lock, i.e. the run is
  being executed right now. A `running` run whose lock is free was interrupted.
  """
  def held?(organization_id, mission_id, run_id),
    do: key_held?(["cadence.fleet.run", organization_id, mission_id, run_id])

  @doc "True while any session holds the advisory lock named by `parts`."
  def key_held?(parts) when is_list(parts) do
    <<high::unsigned-32, low::unsigned-32>> = <<key(parts)::signed-64>>

    case Repo.query(
           "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE locktype = 'advisory' AND granted " <>
             "AND database = (SELECT oid FROM pg_database WHERE datname = current_database()) " <>
             "AND classid = $1::bigint::oid AND objid = $2::bigint::oid AND objsubid = 1)",
           [high, low]
         ) do
      {:ok, %{rows: [[held?]]}} -> held?
      {:error, _reason} -> false
    end
  end

  defp key(parts) do
    <<key::signed-64, _::binary>> = :crypto.hash(:sha256, Jason.encode!(parts))
    key
  end

  defp connect(key, owned_key, callback) do
    options =
      Repo.config()
      |> Keyword.take(@connection_keys)
      |> Keyword.merge(pool_size: 1, max_restarts: 0, backoff_type: :stop)

    with {:ok, connection} <- Postgrex.start_link(options) do
      try do
        case Postgrex.query(connection, "SELECT pg_try_advisory_lock($1::bigint)", [key]) do
          {:ok, %{rows: [[true]]}} ->
            Process.put(owned_key, connection)
            callback.()

          {:ok, %{rows: [[false]]}} ->
            {:error, :fleet_planning_run_busy}

          {:error, reason} ->
            {:error, reason}
        end
      after
        Process.delete(owned_key)
        if Process.alive?(connection), do: GenServer.stop(connection, :normal)
      end
    end
  end
end
