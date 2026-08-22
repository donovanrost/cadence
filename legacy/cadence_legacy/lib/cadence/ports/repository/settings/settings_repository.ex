defmodule Cadence.Ports.Repository.Settings.SettingsRepository do
  @moduledoc """
  Port (behavior) defining the contract for settings persistence operations.

  This behavior abstracts settings storage from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Settings.EctoSettingsRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemorySettingsRepository` - In-memory for tests

  ## Note on Business Logic

  This repository only handles raw storage. Business logic such as:
  - Hierarchical resolution (mission → org → default fallback)
  - Restrictiveness validation (mission values must be more restrictive than org)
  - Definition lookups and type validation

  All remain in the `Cadence.Settings` context.
  """

  alias Cadence.Settings.Setting

  @type id :: String.t()
  @type scope_id :: String.t()
  @type scope_type :: String.t()
  @type namespace :: String.t()
  @type key :: String.t()
  @type error :: :not_found | {:validation, map()} | term()

  # ===========================================================================
  # Setting Operations
  # ===========================================================================

  @doc """
  Finds a specific setting by scope and key.

  Returns `{:ok, setting}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(scope_id(), scope_type(), namespace(), key()) ::
              {:ok, Setting.t()} | {:error, :not_found}

  @doc """
  Gets only the value map for a setting.

  More efficient than `find/4` when you only need the value.
  Returns `nil` if not found.
  """
  @callback get_value(scope_id(), scope_type(), namespace(), key()) :: map() | nil

  @doc """
  Lists all settings for a specific scope.

  ## Options

  - `:namespace` - Filter by namespace
  """
  @callback list_by_scope(scope_id(), scope_type(), opts :: keyword()) :: [Setting.t()]

  @doc """
  Persists a setting (insert if new, update if exists).

  The attrs map should contain:
  - `scope_type` - "organization" or "mission"
  - `scope_id` - The org or mission ID
  - `namespace` - Setting namespace (e.g., "procedures")
  - `key` - Setting key (e.g., "required_approvals")
  - `value` - Value map with type info (e.g., `%{"type" => "integer", "value" => 2}`)

  Returns `{:ok, setting}` on success, `{:error, reason}` on failure.
  """
  @callback upsert(attrs :: map()) :: {:ok, Setting.t()} | {:error, error()}

  @doc """
  Deletes a setting by scope and key.

  Returns `{:ok, count}` where count is the number of deleted records.
  """
  @callback delete(scope_id(), scope_type(), namespace(), key()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Deletes all settings for a scope.

  Useful for cleanup when an org or mission is deleted.
  Returns `{:ok, count}` where count is the number of deleted records.
  """
  @callback delete_all_for_scope(scope_id(), scope_type()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Returns the configured settings repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :settings_repository,
      Cadence.Adapters.Persistence.Ecto.Settings.EctoSettingsRepository
    )
  end
end
