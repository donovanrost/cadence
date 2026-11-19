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

  `setup_questdb/1` applies the QuestDB migrations once per run, points telemetry writes (through
  the test writer's delegate: the runtime's storage policy is fixed at boot) and
  `telemetry_history_store` at the QuestDB modules (restored on exit; Postgres stays on the
  sandbox), and gives `questdb_since`: QuestDB has no transactions or sandbox, so a test isolates
  with its own unique ids and reads only rows written since it started (a local container keeps
  earlier runs' rows). The WAL makes writes visible asynchronously: read with `read_back/2`,
  bounded polling, never a fixed sleep.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Cadence.OutageTelemetryWriter
  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SchemaMigrator, SQL}
  alias Cadence.Telemetry.Storage.Writers
  alias Cadence.TestSupport.TCPContactFixture

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
    writer = OutageTelemetryWriter.delegate()

    # The runtime took its storage policy at boot (the test writer), so writes are switched
    # through that writer's delegate; the history store is read per call, from the env.
    OutageTelemetryWriter.delegate(Cadence.Telemetry.Storage.Writers.QuestDB)

    Application.put_env(:cadence, :telemetry_history_store,
      module: Cadence.Telemetry.HistoryStore.QuestDB,
      realm: :flight,
      data_source_id: Keyword.get(storage, :data_source_id, "managed_questdb_primary")
    )

    on_exit(fn ->
      OutageTelemetryWriter.delegate(writer)
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
  Sends one fixture frame per sequence count to a `TCPContactFixture` contact and waits until
  QuestDB holds that many of the mission's rows since `since`; returns them (`rows/3`). Raises if
  they don't all arrive.
  """
  @spec ingest_frames!(map(), Enumerable.t(), DateTime.t()) :: [map()]
  def ingest_frames!(%{mission_id: mission_id, port: port}, counts, %DateTime{} = since) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    expected =
      Enum.reduce(counts, 0, fn count, sent ->
        :ok = :gen_tcp.send(socket, TCPContactFixture.frame(count))
        Process.sleep(50)
        sent + 1
      end)

    case read_back(fn -> enough_rows(rows(mission_id, since), expected) end) do
      rows when is_list(rows) and length(rows) >= expected -> rows
      rows -> raise "expected #{expected} rows in QuestDB, got #{length(List.wrap(rows))}"
    end
  end

  defp enough_rows(rows, expected) when length(rows) >= expected, do: {:ok, rows}
  defp enough_rows(rows, _expected), do: rows

  @doc """
  Writes telemetry envelopes straight through the QuestDB writer (no ingest), for tests that need
  exact rows: duplicates, retries, out-of-order, NULLs. Raises on a write error.
  """
  @spec write_observations!([map()], keyword()) :: :ok
  def write_observations!(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    case Writers.QuestDB.persist_envelopes(envelopes, opts) do
      :ok -> :ok
      {:error, reason} -> raise "QuestDB write failed: #{inspect(reason)}"
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
