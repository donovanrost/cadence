defmodule Cadence.Application.Targeting.TargetQueries do
  @moduledoc """
  Use case module for querying targets.

  This module provides read-only operations for listing and finding
  targets. It works with domain entities and uses repository ports
  for data access.

  ## Usage

      # List targets for a mission
      targets = TargetQueries.list(mission_id)

      # Find a specific target
      {:ok, target} = TargetQueries.find(target_id, mission_id)

      # Find by identifier
      {:ok, target} = TargetQueries.find_by_identifier(mission_id, "SAT_001")
  """

  alias Cadence.Domain.Targeting.Entities.Target

  @type id :: String.t()
  @type mission_id :: String.t()
  @type target_identifier :: String.t()
  @type opts :: keyword()

  # Get configured repository (allows for DI in tests)
  defp repo do
    Application.get_env(
      :cadence,
      :target_repository,
      Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository
    )
  end

  # ===========================================================================
  # Find Operations
  # ===========================================================================

  @doc """
  Finds a target by ID, scoped to a mission.

  Returns `{:ok, target}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(id(), mission_id()) :: {:ok, Target.t()} | {:error, :not_found}
  def find(id, mission_id), do: repo().find(id, mission_id)

  @doc """
  Finds a target by ID and mission, raising if not found.
  """
  @spec find!(id(), mission_id()) :: Target.t()
  def find!(id, mission_id) do
    case find(id, mission_id) do
      {:ok, target} -> target
      {:error, :not_found} -> raise "Target not found: #{id}"
    end
  end

  @doc """
  Finds a target by ID without mission scoping.

  WARNING: Only use for internal operations where mission context
  is verified elsewhere.
  """
  @spec find_unscoped(id()) :: {:ok, Target.t()} | {:error, :not_found}
  def find_unscoped(id), do: repo().find_unscoped(id)

  @doc """
  Finds a target by ID without scoping, raising if not found.
  """
  @spec find_unscoped!(id()) :: Target.t()
  def find_unscoped!(id) do
    case find_unscoped(id) do
      {:ok, target} -> target
      {:error, :not_found} -> raise "Target not found: #{id}"
    end
  end

  @doc """
  Finds a target by its identifier within a mission.

  The identifier is a unique string like "SAT_001" or "GROUND_01".
  """
  @spec find_by_identifier(mission_id(), target_identifier()) :: {:ok, Target.t()} | {:error, :not_found}
  def find_by_identifier(mission_id, identifier) do
    repo().find_by_identifier(mission_id, identifier)
  end

  @doc """
  Finds a target with its definition set preloaded.
  """
  @spec find_with_definition_set(id()) :: {:ok, Target.t()} | {:error, :not_found}
  def find_with_definition_set(id) do
    repo().find_with_definition_set(id)
  end

  @doc """
  Finds a target with definition set, raising if not found.
  """
  @spec find_with_definition_set!(id()) :: Target.t()
  def find_with_definition_set!(id) do
    case find_with_definition_set(id) do
      {:ok, target} -> target
      {:error, :not_found} -> raise "Target not found: #{id}"
    end
  end

  # ===========================================================================
  # List Operations
  # ===========================================================================

  @doc """
  Lists targets for a mission.

  ## Options

  - `:status` - Filter by status (atom or list of atoms)
  - `:type` - Filter by type (atom or list of atoms)
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)
  - `:preload` - List of associations to preload

  ## Examples

      # All targets
      TargetQueries.list(mission_id)

      # Only online targets
      TargetQueries.list(mission_id, status: :online)

      # Spacecraft only
      TargetQueries.list(mission_id, type: :spacecraft)
  """
  @spec list(mission_id(), opts()) :: [Target.t()]
  def list(mission_id, opts \\ []) do
    repo().list(mission_id, opts)
  end

  @doc """
  Lists targets using a specific definition set.
  """
  @spec list_by_definition_set(id()) :: [Target.t()]
  def list_by_definition_set(definition_set_id) do
    repo().list_by_definition_set(definition_set_id)
  end

  @doc """
  Lists online targets for a mission.
  """
  @spec list_online(mission_id(), opts()) :: [Target.t()]
  def list_online(mission_id, opts \\ []) do
    list(mission_id, Keyword.put(opts, :status, :online))
  end

  # ===========================================================================
  # Definition Set Queries
  # ===========================================================================

  @doc """
  Gets the definition set ID for a target by mission and identifier.
  """
  @spec get_definition_set_id(mission_id(), target_identifier()) :: {:ok, id()} | {:error, :not_found}
  def get_definition_set_id(mission_id, identifier) do
    repo().get_definition_set_id(mission_id, identifier)
  end

  @doc """
  Gets the definition set ID for a target by target ID.
  """
  @spec get_definition_set_id_by_target_id(id()) :: {:ok, id()} | {:error, :not_found}
  def get_definition_set_id_by_target_id(id) do
    repo().get_definition_set_id_by_target_id(id)
  end
end
