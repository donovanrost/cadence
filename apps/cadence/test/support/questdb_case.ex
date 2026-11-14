defmodule Cadence.TestSupport.QuestDBCase do
  @moduledoc """
  Shared setup for the `:questdb` suite (P1, docs/ci/questdb-integration.md): tests that need a
  real QuestDB. They're excluded by default (test_helper.exs) and run with `mix test --only
  questdb` where `CADENCE_QUESTDB_HTTP_ENDPOINT` points at one (CI's questdb-integration job, or a
  throwaway local container; never a shared dev QuestDB).

      use Cadence.RuntimeCase, async: false
      import Cadence.TestSupport.QuestDBCase
      @moduletag :questdb
      setup :setup_questdb

  `setup_questdb/1` applies the QuestDB migrations once per run, points `telemetry_storage` and
  `telemetry_history_store` at the QuestDB modules (restored on exit; Postgres stays on the
  sandbox), and gives `questdb_since`: QuestDB has no transactions or sandbox, so a test isolates
  with its own unique ids and reads only rows written since it started (a local container keeps
  earlier runs' rows). The WAL makes writes visible asynchronously: read with `read_back/2`,
  bounded polling, never a fixed sleep.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SchemaMigrator, SQL}

  @endpoint_env "CADENCE_QUESTDB_HTTP_ENDPOINT"
  @migrated_key {__MODULE__, :migrated}

  @doc "ExUnit setup: a real QuestDB behind telemetry storage and the history store."
  def setup_questdb(_context) do
    unless System.get_env(@endpoint_env) do
      raise "the :questdb suite needs a real QuestDB: set #{@endpoint_env} (mix test --only questdb)"
    end

    migrate_once!()

    storage = Application.get_env(:cadence, :telemetry_storage)
    history = Application.get_env(:cadence, :telemetry_history_store)

    Application.put_env(
      :cadence,
      :telemetry_storage,
      Keyword.put(storage, :writer, Cadence.Telemetry.Storage.Writers.QuestDB)
    )

    Application.put_env(:cadence, :telemetry_history_store,
      module: Cadence.Telemetry.HistoryStore.QuestDB,
      realm: :flight,
      data_source_id: Keyword.get(storage, :data_source_id, "managed_questdb_primary")
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, storage)
      Application.put_env(:cadence, :telemetry_history_store, history)
    end)

    {:ok, questdb_since: DateTime.add(DateTime.utc_now(), -1, :second)}
  end

  @doc """
  The mission's telemetry_observations rows ingested since `since`, oldest receipt first, as maps
  of the named columns.
  """
  @spec rows(binary(), DateTime.t(), [binary()]) :: [map()]
  def rows(mission_id, %DateTime{} = since, columns \\ default_columns()) do
    sql = """
    SELECT #{Enum.join(columns, ", ")}
    FROM telemetry_observations
    WHERE mission_id = #{SQL.literal(mission_id)} AND ingested_at >= #{SQL.literal(since)}
    ORDER BY receipt_time
    """

    case RestClient.exec(sql, []) do
      {:ok, %{"columns" => cols, "dataset" => dataset}} ->
        names = Enum.map(cols, & &1["name"])
        Enum.map(dataset, &(names |> Enum.zip(&1) |> Map.new()))

      {:ok, %{"dataset" => []}} ->
        []

      {:error, reason} ->
        raise "QuestDB read failed: #{inspect(reason)}"
    end
  end

  @doc """
  Polls `fun` (every 100 ms, up to `timeout_ms`) until it returns `{:ok, value}`; returns the
  value, or the last result if it never did.
  """
  @spec read_back((-> {:ok, term()} | term()), pos_integer()) :: term()
  def read_back(fun, timeout_ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    case fun.() do
      {:ok, value} ->
        value

      other ->
        if System.monotonic_time(:millisecond) >= deadline do
          other
        else
          Process.sleep(100)
          poll(fun, deadline)
        end
    end
  end

  defp default_columns,
    do: ~w(sample_id point_id receipt_time observation_identity_id idempotency_key validity_state)

  defp migrate_once! do
    case :persistent_term.get(@migrated_key, false) do
      true ->
        :ok

      false ->
        case SchemaMigrator.apply_pending([]) do
          {:ok, _applied} -> :persistent_term.put(@migrated_key, true)
          {:error, reason} -> raise "QuestDB migrations failed: #{inspect(reason)}"
        end
    end
  end
end
