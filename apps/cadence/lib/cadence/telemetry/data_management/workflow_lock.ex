defmodule Cadence.Telemetry.DataManagement.WorkflowLock do
  @moduledoc "Serializes native historical-workflow decisions on a dedicated PostgreSQL session."
  alias Cadence.Repo

  @connection_keys ~w(hostname endpoints socket_dir socket port database username password parameters ssl socket_options types prepare connect_timeout timeout handshake_timeout ping_timeout after_connect)a

  def with_group(organization_id, mission_id, run_id, callback) when is_function(callback, 0) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(
        :sha256,
        Jason.encode!(["cadence.historical-workflow.group", organization_id, mission_id, run_id])
      )

    owned_key = {__MODULE__, key}

    if Process.get(owned_key) do
      callback.()
    else
      connect(key, owned_key, callback)
    end
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
            {:error, :historical_workflow_group_busy}

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
