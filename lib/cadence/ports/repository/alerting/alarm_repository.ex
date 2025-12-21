defmodule Cadence.Ports.Repository.Alerting.AlarmRepository do
  @moduledoc """
  Port (behavior) defining the contract for alarm persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryAlarmRepository` - In-memory for tests
  """

  alias Cadence.Domain.Alerting.Entities.Alarm

  @type id :: String.t()
  @type mission_id :: String.t()
  @type target_id :: String.t() | nil
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds an alarm by its ID.

  Returns `{:ok, alarm}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, Alarm.t()} | {:error, :not_found}

  @doc """
  Finds an active (non-cleared) alarm by source.

  Used for deduplication - only one active alarm per source should exist.
  """
  @callback find_active_by_source(
              mission_id(),
              target_id(),
              source_type :: String.t(),
              source_id :: String.t()
            ) :: {:ok, Alarm.t()} | {:error, :not_found}

  @doc """
  Persists an alarm (insert or update).

  Returns `{:ok, alarm}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Alarm.t()) :: {:ok, Alarm.t()} | {:error, error()}

  @doc """
  Lists alarms for a mission with optional filtering.

  ## Options

  - `:status` - Filter by status(es): `:active`, `:acknowledged`, `:shelved`, `:cleared`
  - `:severity` - Filter by severity(ies): `:info`, `:warning`, `:critical`
  - `:target_id` - Filter by specific target
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(mission_id(), opts()) :: [Alarm.t()]

  @doc """
  Lists all active (non-cleared) alarms for a mission.

  Convenience function equivalent to `list(mission_id, status: [:active, :acknowledged, :shelved])`.
  """
  @callback list_active(mission_id(), opts()) :: [Alarm.t()]

  @doc """
  Counts alarms by status for a mission.

  Returns a map like `%{active: 5, acknowledged: 2, shelved: 1, cleared: 100}`.
  """
  @callback count_by_status(mission_id()) :: %{
              active: non_neg_integer(),
              acknowledged: non_neg_integer(),
              shelved: non_neg_integer(),
              cleared: non_neg_integer()
            }

  @doc """
  Lists alarms that have expired shelve periods.

  Used by the background job that unshelves alarms when their shelve duration ends.
  """
  @callback list_expired_shelved() :: [Alarm.t()]

  @doc """
  Deletes an alarm by ID.

  Returns `{:ok, alarm}` with the deleted entity, or `{:error, :not_found}`.
  """
  @callback delete(id()) :: {:ok, Alarm.t()} | {:error, :not_found}

  # Convenience function to get the configured implementation
  @doc """
  Returns the configured alarm repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:cadence, :alarm_repository, Cadence.Adapters.Persistence.Ecto.Alerting.EctoAlarmRepository)
  end
end
