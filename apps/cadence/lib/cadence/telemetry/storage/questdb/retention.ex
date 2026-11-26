defmodule Cadence.Telemetry.Storage.QuestDB.Retention do
  @moduledoc """
  Retention for `telemetry_observations` (#693): drops the day partitions that no mission still
  needs.

  QuestDB has no row delete, only whole-partition drops, and the table holds every mission's
  rows in the same day partitions, so retention is one platform setting. There is deliberately no
  per-mission retention here: on a shared table it could only lengthen every mission's retention,
  never shorten its own. If a mission ever needs its own, that is a storage-design question
  (per-mission tables, or another partitioning), not a config key.

  Settings (`config :cadence, :telemetry_observation_retention`):

    * `retention_days`: how long observations are kept (30);
    * `max_drops_per_run`: a bound on one run (31).

  Several nodes run the job, so two may drop the same partitions. A failed drop re-reads the
  partitions: if the ones it meant to drop are already gone (another node dropped them) that is
  success, and if some remain it retries those once.

  A run measures the table first (`table_partitions`), drops the expired partitions in one
  `ALTER TABLE ... DROP PARTITION LIST`, and emits
  `[:cadence, :telemetry, :questdb_retention, :measured]` with the partitions and disk bytes left,
  which is the storage line of #686's scorecard.

  **A drop on a WAL table is applied asynchronously** (the table is a WAL table, like its inserts):
  the statement is accepted at once, and the partition can still be listed for a while. So a run
  never drops a partition again while its earlier drop may still be pending. The caller passes the
  report's `pending` map (`name => runs seen`) back in as `:pending`; a pending partition that is
  still listed is skipped and left out of the `partitions` and `disk_bytes` it reports (they count
  what is left once the drop applies, so the gauge does not briefly include dropped data). A
  partition still listed after three runs is no longer assumed pending and is dropped again.
  Re-dropping a partition a WAL drop already covers is avoided rather than relied on to be
  harmless, since the statement is queued, not applied, when it is sent.
  """

  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @table "telemetry_observations"
  @default_days 30
  @default_max_drops 31
  @max_pending_runs 3

  @type partition :: %{
          name: binary(),
          max_timestamp: DateTime.t() | nil,
          rows: non_neg_integer(),
          disk_bytes: non_neg_integer(),
          active?: boolean()
        }

  @doc "How many days of observations the table keeps."
  @spec retention_days(keyword()) :: pos_integer()
  def retention_days(settings \\ settings()),
    do: Keyword.get(settings, :retention_days, @default_days)

  @doc "Whole days before `now`: the instant a partition must be wholly older than to be dropped."
  @spec cutoff(DateTime.t(), pos_integer()) :: DateTime.t()
  def cutoff(%DateTime{} = now, days) when is_integer(days) and days > 0,
    do: DateTime.add(now, -days * 86_400, :second)

  @doc "The partitions to drop at `cutoff`: not active, and holding nothing at or after it."
  @spec expired([partition()], DateTime.t()) :: [partition()]
  def expired(partitions, %DateTime{} = cutoff) do
    Enum.filter(partitions, fn partition ->
      not partition.active? and partition.max_timestamp != nil and
        DateTime.compare(partition.max_timestamp, cutoff) == :lt
    end)
  end

  @doc """
  One run: measure, drop what has expired, report. `{:ok, report}` or `{:error, reason}`; the
  report has `partitions` and `disk_bytes` (after the drop), `dropped` (their names) and
  `dropped_bytes`.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    pending = Keyword.get(opts, :pending, %{})
    settings = Keyword.get_lazy(opts, :settings, &settings/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    exec = Keyword.get(opts, :exec_fun, &RestClient.exec/2)
    exec_opts = Keyword.get(opts, :exec_opts, [])
    cutoff = cutoff(now, retention_days(settings))

    with {:ok, partitions} <- partitions(exec, exec_opts) do
      still_pending = still_pending(pending, partitions)

      # The newest partition is never a candidate: QuestDB refuses to drop it, and a refusal
      # would abort the whole list. Nor is one whose earlier drop may still be applying.
      doomed =
        partitions
        |> Enum.drop(-1)
        |> expired(cutoff)
        |> Enum.reject(&Map.has_key?(still_pending, &1.name))
        |> Enum.take(max_drops(settings))

      with :ok <- drop(doomed, exec, exec_opts) do
        report(partitions, doomed, still_pending, cutoff)
      end
    end
  end

  @doc "The settings, with the platform defaults."
  @spec settings() :: keyword()
  def settings, do: Application.get_env(:cadence, :telemetry_observation_retention, [])

  defp max_drops(settings), do: Keyword.get(settings, :max_drops_per_run, @default_max_drops)

  defp partitions(exec, exec_opts) do
    sql =
      "SELECT name, maxTimestamp, numRows, diskSize, active FROM table_partitions(#{SQL.quote_string(@table)}) ORDER BY name"

    with {:ok, %{"columns" => columns, "dataset" => dataset}} <- exec.(sql, exec_opts) do
      names = Enum.map(columns, & &1["name"])
      {:ok, Enum.map(dataset, &partition(Enum.zip(names, &1) |> Map.new()))}
    end
  end

  defp partition(row) do
    %{
      name: row["name"],
      max_timestamp: parse_time(row["maxTimestamp"]),
      rows: row["numRows"] || 0,
      disk_bytes: row["diskSize"] || 0,
      active?: row["active"] == true
    }
  end

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time
      {:error, _reason} -> nil
    end
  end

  # `maxTimestamp` is a TIMESTAMP (ISO text over /exec) or, depending on the version, microseconds.
  defp parse_time(micros) when is_integer(micros) do
    case DateTime.from_unix(micros, :microsecond) do
      {:ok, time} -> time
      {:error, _reason} -> nil
    end
  end

  defp parse_time(_value), do: nil

  defp drop(doomed, exec, exec_opts, retry? \\ true)
  defp drop([], _exec, _exec_opts, _retry?), do: :ok

  defp drop(doomed, exec, exec_opts, retry?) do
    names = doomed |> Enum.map_join(", ", &SQL.quote_string(&1.name))

    case exec.("ALTER TABLE #{@table} DROP PARTITION LIST #{names}", exec_opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> after_failed_drop(doomed, reason, exec, exec_opts, retry?)
    end
  end

  # Another node may have dropped some or all of them first: look again at what is left.
  defp after_failed_drop(doomed, reason, exec, exec_opts, retry?) do
    with true <- retry?,
         {:ok, now_there} <- partitions(exec, exec_opts) do
      names = MapSet.new(now_there, & &1.name)

      case Enum.filter(doomed, &MapSet.member?(names, &1.name)) do
        [] -> :ok
        remaining -> drop(remaining, exec, exec_opts, false)
      end
    else
      _no_retry_or_unreadable -> {:error, {:drop_partition_failed, reason}}
    end
  end

  # Earlier drops that are still listed and not yet old enough to be given up on: `name => runs`.
  defp still_pending(pending, partitions) do
    listed = MapSet.new(partitions, & &1.name)

    pending
    |> Enum.filter(fn {name, runs} ->
      MapSet.member?(listed, name) and runs < @max_pending_runs
    end)
    |> Map.new(fn {name, runs} -> {name, runs + 1} end)
  end

  defp report(partitions, doomed, still_pending, cutoff) do
    gone = MapSet.new(doomed, & &1.name) |> MapSet.union(MapSet.new(Map.keys(still_pending)))
    kept = Enum.reject(partitions, &MapSet.member?(gone, &1.name))
    pending = Enum.reduce(doomed, still_pending, &Map.put(&2, &1.name, 1))
    disk_bytes = kept |> Enum.map(& &1.disk_bytes) |> Enum.sum()
    dropped_bytes = doomed |> Enum.map(& &1.disk_bytes) |> Enum.sum()

    :telemetry.execute(
      [:cadence, :telemetry, :questdb_retention, :measured],
      %{
        partitions: length(kept),
        disk_bytes: disk_bytes,
        dropped_partitions: length(doomed),
        dropped_bytes: dropped_bytes,
        pending_partitions: map_size(pending)
      },
      %{}
    )

    {:ok,
     %{
       cutoff: cutoff,
       partitions: length(kept),
       disk_bytes: disk_bytes,
       dropped: Enum.map(doomed, & &1.name),
       dropped_bytes: dropped_bytes,
       pending: pending
     }}
  end
end
