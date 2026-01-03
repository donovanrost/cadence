defmodule Cadence.Application.Alerting.AlarmQueries do
  @moduledoc """
  Use case module for querying alarms.

  This module provides read-only operations for listing, counting,
  and finding alarms. It works with domain entities and uses
  repository ports for data access.

  ## Usage

      # List active alarms for a mission
      alarms = AlarmQueries.list_active(mission_id)

      # Count by status
      counts = AlarmQueries.count_by_status(mission_id)

      # Find specific alarm
      {:ok, alarm} = AlarmQueries.find(alarm_id)
  """

  alias Cadence.Domain.Alerting.Entities.Alarm

  @type mission_id :: String.t()
  @type alarm_id :: String.t()
  @type opts :: keyword()

  # Get configured repository (allows for DI in tests)
  defp repo do
    Application.get_env(
      :cadence,
      :alarm_repository,
      Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository
    )
  end

  @doc """
  Finds an alarm by ID.

  Returns `{:ok, alarm}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(alarm_id()) :: {:ok, Alarm.t()} | {:error, :not_found}
  def find(id), do: repo().find(id)

  @doc """
  Finds an alarm by ID, raising if not found.
  """
  @spec find!(alarm_id()) :: Alarm.t()
  def find!(id) do
    case find(id) do
      {:ok, alarm} -> alarm
      {:error, :not_found} -> raise "Alarm not found: #{id}"
    end
  end

  @doc """
  Finds an active alarm for a specific source.

  Used for deduplication - only one active alarm per source.

  ## Parameters

  - `mission_id` - Mission UUID
  - `target_id` - Target UUID (or nil for mission-level alarms)
  - `source_type` - Type of source (e.g., "telemetry_item")
  - `source_id` - Source identifier (e.g., "HEALTH.cpu_temp")
  """
  @spec find_active_by_source(mission_id(), String.t() | nil, String.t(), String.t()) ::
          {:ok, Alarm.t()} | {:error, :not_found}
  def find_active_by_source(mission_id, target_id, source_type, source_id) do
    repo().find_active_by_source(mission_id, target_id, source_type, source_id)
  end

  @doc """
  Lists alarms for a mission.

  ## Options

  - `:status` - Filter by status (atom or list of atoms)
  - `:severity` - Filter by severity (atom or list of atoms)
  - `:target_id` - Filter by target UUID
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)

  ## Examples

      # All alarms
      AlarmQueries.list(mission_id)

      # Only critical alarms
      AlarmQueries.list(mission_id, severity: :critical)

      # Active alarms for a specific target
      AlarmQueries.list(mission_id, status: :active, target_id: target_id)
  """
  @spec list(mission_id(), opts()) :: [Alarm.t()]
  def list(mission_id, opts \\ []) do
    repo().list(mission_id, opts)
  end

  @doc """
  Lists active alarms for a mission.

  Active alarms are those with status `:active`, `:acknowledged`, or `:shelved`.
  """
  @spec list_active(mission_id(), opts()) :: [Alarm.t()]
  def list_active(mission_id, opts \\ []) do
    repo().list_active(mission_id, opts)
  end

  @doc """
  Lists historical (cleared) alarms for a mission.

  ## Options

  - `:time_range` - Filter by time range: `:1h`, `:6h`, `:24h`, `:7d`, `:all` (default: `:all`)
  - `:target_id` - Filter by target UUID
  - `:severity` - Filter by severity (atom or list of atoms)
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)

  ## Examples

      # All historical alarms
      AlarmQueries.list_historical(mission_id)

      # Historical alarms from last 24 hours
      AlarmQueries.list_historical(mission_id, time_range: :"24h")
  """
  @spec list_historical(mission_id(), opts()) :: [Alarm.t()]
  def list_historical(mission_id, opts \\ []) do
    time_range = Keyword.get(opts, :time_range, :all)
    since = time_range_to_datetime(time_range)

    opts =
      opts
      |> Keyword.put(:status, :cleared)
      |> Keyword.put(:cleared_since, since)
      |> Keyword.delete(:time_range)

    repo().list(mission_id, opts)
  end

  defp time_range_to_datetime(:all), do: nil
  defp time_range_to_datetime(:"1h"), do: DateTime.add(DateTime.utc_now(), -1, :hour)
  defp time_range_to_datetime(:"6h"), do: DateTime.add(DateTime.utc_now(), -6, :hour)
  defp time_range_to_datetime(:"24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp time_range_to_datetime(:"7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp time_range_to_datetime(_), do: nil

  @doc """
  Counts alarms by status for a mission.

  Returns a map of status to count.

  ## Example

      %{
        active: 5,
        acknowledged: 2,
        shelved: 1,
        cleared: 42
      }
  """
  @spec count_by_status(mission_id()) :: map()
  def count_by_status(mission_id) do
    repo().count_by_status(mission_id)
  end

  @doc """
  Counts total active alarms for a mission.

  Active alarms are those not in `:cleared` status.
  """
  @spec count_active(mission_id()) :: non_neg_integer()
  def count_active(mission_id) do
    counts = count_by_status(mission_id)

    (counts[:active] || 0) +
      (counts[:acknowledged] || 0) +
      (counts[:shelved] || 0)
  end

  @doc """
  Groups active alarms by severity.

  Returns a map of severity to list of alarms.

  ## Example

      %{
        critical: [alarm1, alarm2],
        warning: [alarm3],
        info: []
      }
  """
  @spec group_by_severity(mission_id()) :: map()
  def group_by_severity(mission_id) do
    list_active(mission_id)
    |> Enum.group_by(& &1.severity)
    |> Map.put_new(:critical, [])
    |> Map.put_new(:warning, [])
    |> Map.put_new(:info, [])
  end

  @doc """
  Returns the highest severity among active alarms.

  Returns `nil` if no active alarms.
  """
  @spec highest_active_severity(mission_id()) :: :critical | :warning | :info | nil
  def highest_active_severity(mission_id) do
    groups = group_by_severity(mission_id)

    cond do
      length(groups[:critical]) > 0 -> :critical
      length(groups[:warning]) > 0 -> :warning
      length(groups[:info]) > 0 -> :info
      true -> nil
    end
  end
end
