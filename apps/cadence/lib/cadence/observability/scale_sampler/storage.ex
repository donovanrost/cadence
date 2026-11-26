defmodule Cadence.Observability.ScaleSampler.Storage do
  @moduledoc """
  Storage probes for `Cadence.Observability.ScaleSampler` (#717, telemetry's #686 storage line):

  - Postgres WAL position (per second) and, for the watched tables, rows inserted and total
    relation size (at the start and end of a run; the summary holds the deltas).
  - QuestDB WAL lag across tables (per second), and for the watched tables the partitions' disk
    size and row count (start and end).

  Every probe answers `nil` when its database can't be asked, so a run without QuestDB still
  records the rest. QuestDB is asked through `exec`, a `sql -> {:ok, %{"dataset" => rows}}`
  function the caller passes (the telemetry context's REST client): platform code doesn't call
  into a domain context.
  """

  @doc "Telemetry's #686 Postgres tables on the ingest path."
  @spec default_postgres_tables() :: [binary()]
  def default_postgres_tables do
    ~w(telemetry_observation_identity_states semantic_runtime_commits protocol_archive_segments
       record_identities ingress_archive_evidence_entries data_source_watermark_events
       partition_stream_keys)
  end

  @doc "Telemetry's #686 QuestDB tables."
  @spec default_questdb_tables() :: [binary()]
  def default_questdb_tables, do: ["telemetry_observations"]

  @doc "Bytes of WAL written so far (`pg_wal_lsn_diff` from 0/0)."
  @spec wal_position() :: integer() | nil
  def wal_position do
    case pg("select pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::bigint", []) do
      [[position]] -> position
      _unavailable -> nil
    end
  end

  @doc "Per table: rows inserted (`n_tup_ins`) and total relation size in bytes."
  @spec postgres_tables([binary()]) :: %{
          binary() => %{rows_inserted: integer(), bytes: integer()}
        }
  def postgres_tables([]), do: %{}

  def postgres_tables(tables) do
    sql = """
    select relname, n_tup_ins, pg_total_relation_size(relid)
    from pg_stat_user_tables where relname = any($1)
    """

    case pg(sql, [tables]) do
      rows when is_list(rows) ->
        Map.new(rows, fn [name, inserted, bytes] ->
          {name, %{rows_inserted: inserted, bytes: bytes}}
        end)

      nil ->
        %{}
    end
  end

  @doc "QuestDB WAL lag: transactions sequenced but not yet applied, summed and max over tables."
  @spec questdb_wal_lag((binary() -> term())) ::
          %{sum: integer(), max: integer(), suspended: integer()} | nil
  def questdb_wal_lag(exec) do
    case questdb(exec, "select sequencerTxn - writerTxn, suspended from wal_tables()") do
      {:ok, rows} ->
        lags = Enum.map(rows, fn [lag, _suspended] -> lag || 0 end)

        %{
          sum: Enum.sum(lags),
          max: Enum.max(lags, fn -> 0 end),
          suspended: Enum.count(rows, fn [_lag, suspended] -> suspended == true end)
        }

      {:error, _unavailable} ->
        nil
    end
  end

  @doc "Per QuestDB table: the partitions' total disk size (bytes) and row count."
  @spec questdb_tables((binary() -> term()), [binary()]) :: %{
          binary() => %{bytes: integer(), rows: integer()} | nil
        }
  def questdb_tables(exec, tables) do
    Map.new(tables, fn table ->
      sql = "select sum(diskSize), sum(numRows) from table_partitions('#{table}')"

      case questdb(exec, sql) do
        {:ok, [[bytes, rows]]} -> {table, %{bytes: bytes || 0, rows: rows || 0}}
        _unavailable -> {table, nil}
      end
    end)
  end

  @doc "End minus start for each table's numeric fields (`nil` where either side is missing)."
  @spec deltas(map(), map()) :: map()
  def deltas(start, finish) do
    Map.new(finish, fn {table, values} -> {table, delta(Map.get(start, table), values)} end)
  end

  defp delta(before, values) when is_map(before) and is_map(values),
    do: Map.new(values, fn {key, value} -> {key, value - Map.get(before, key, 0)} end)

  defp delta(_before, _values), do: nil

  # The sampler's own queries stay out of the logs (it runs once a second).
  defp pg(sql, params) do
    case Cadence.Repo.query(sql, params, log: false) do
      {:ok, %{rows: rows}} -> rows
      {:error, _reason} -> nil
    end
  rescue
    _db_unavailable -> nil
  end

  defp questdb(exec, sql) do
    case exec.(sql) do
      {:ok, %{"dataset" => rows}} -> {:ok, rows}
      other -> {:error, other}
    end
  rescue
    _questdb_unavailable -> {:error, :unavailable}
  end
end
