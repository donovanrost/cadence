defmodule Cadence.Telemetry.Storage.QuestDB.Retention do
  @moduledoc """
  Retention for `telemetry_observations` (#693): drops the day partitions that no mission still
  needs.

  QuestDB has no row delete, only whole-partition drops, and the table holds every mission's
  rows in the same day partitions. A partition is therefore dropped only when it is wholly older
  than the **longest** retention in force: the platform default, or the largest per-mission
  override. A mission configured for a shorter retention than another's keeps its data as long as
  the longest, because the space cannot be freed any other way.

  Settings (`config :cadence, :telemetry_observation_retention`):

    * `default_days`: the platform default (30);
    * `mission_days`: `%{mission_id => days}` overrides;
    * `max_drops_per_run`: a bound on one run (31).

  A run measures the table first (`table_partitions`), drops the expired partitions in one
  `ALTER TABLE ... DROP PARTITION LIST`, and emits
  `[:cadence, :telemetry, :questdb_retention, :measured]` with the partitions and disk bytes left,
  which is the storage line of #686's scorecard.
  """

  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @table "telemetry_observations"
  @default_days 30
  @default_max_drops 31

  @type partition :: %{
          name: binary(),
          max_timestamp: DateTime.t() | nil,
          rows: non_neg_integer(),
          disk_bytes: non_neg_integer(),
          active?: boolean()
        }

  @doc "The retention in force for the whole table: the longest of the default and the overrides."
  @spec retention_days(keyword()) :: pos_integer()
  def retention_days(settings \\ settings()) do
    overrides = settings |> Keyword.get(:mission_days, %{}) |> Map.values()
    Enum.max([Keyword.get(settings, :default_days, @default_days) | overrides])
  end

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
    settings = Keyword.get_lazy(opts, :settings, &settings/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    exec = Keyword.get(opts, :exec_fun, &RestClient.exec/2)
    exec_opts = Keyword.get(opts, :exec_opts, [])
    cutoff = cutoff(now, retention_days(settings))

    with {:ok, partitions} <- partitions(exec, exec_opts) do
      # The newest partition is never a candidate: QuestDB refuses to drop it, and a refusal
      # would abort the whole list.
      doomed =
        partitions |> Enum.drop(-1) |> expired(cutoff) |> Enum.take(max_drops(settings))

      with :ok <- drop(doomed, exec, exec_opts) do
        report(partitions, doomed, cutoff)
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

  defp drop([], _exec, _exec_opts), do: :ok

  defp drop(doomed, exec, exec_opts) do
    names = doomed |> Enum.map_join(", ", &SQL.quote_string(&1.name))

    case exec.("ALTER TABLE #{@table} DROP PARTITION LIST #{names}", exec_opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, {:drop_partition_failed, reason}}
    end
  end

  defp report(partitions, doomed, cutoff) do
    dropped_names = MapSet.new(doomed, & &1.name)
    kept = Enum.reject(partitions, &MapSet.member?(dropped_names, &1.name))
    disk_bytes = kept |> Enum.map(& &1.disk_bytes) |> Enum.sum()
    dropped_bytes = doomed |> Enum.map(& &1.disk_bytes) |> Enum.sum()

    :telemetry.execute(
      [:cadence, :telemetry, :questdb_retention, :measured],
      %{
        partitions: length(kept),
        disk_bytes: disk_bytes,
        dropped_partitions: length(doomed),
        dropped_bytes: dropped_bytes
      },
      %{}
    )

    {:ok,
     %{
       cutoff: cutoff,
       partitions: length(kept),
       disk_bytes: disk_bytes,
       dropped: Enum.map(doomed, & &1.name),
       dropped_bytes: dropped_bytes
     }}
  end
end
