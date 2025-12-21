defmodule Cadence.Application.Procedures.ProcedureQueries do
  @moduledoc """
  Use case module for querying procedures and versions.

  Provides read-only operations for listing, finding, and
  filtering procedures and their versions.

  ## Usage

      # Find approved version
      {:ok, version} = ProcedureQueries.find_approved_version(procedure_id)

      # List all versions
      versions = ProcedureQueries.list_versions(procedure_id)

      # Get next version number
      next = ProcedureQueries.next_version_number(procedure_id)
  """

  alias Cadence.Domain.Procedures.Entities.ProcedureVersion

  @type procedure_id :: String.t()
  @type version_id :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :procedure_repository,
      Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository
    )
  end

  @doc """
  Finds a procedure version by ID.

  Returns `{:ok, version}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find_version(version_id()) :: {:ok, ProcedureVersion.t()} | {:error, :not_found}
  def find_version(id), do: repo().find_version(id)

  @doc """
  Finds a procedure version by ID, raising if not found.
  """
  @spec find_version!(version_id()) :: ProcedureVersion.t()
  def find_version!(id) do
    case find_version(id) do
      {:ok, version} -> version
      {:error, :not_found} -> raise "Procedure version not found: #{id}"
    end
  end

  @doc """
  Finds the current approved version for a procedure.

  Returns the most recently approved version, or `{:error, :not_found}`
  if no version has been approved.
  """
  @spec find_approved_version(procedure_id()) ::
          {:ok, ProcedureVersion.t()} | {:error, :not_found}
  def find_approved_version(procedure_id) do
    repo().find_approved_version(procedure_id)
  end

  @doc """
  Lists all versions for a procedure.

  ## Options

  - `:status` - Filter by status
  - `:limit` - Maximum number of results (default: 50)

  ## Examples

      # All versions
      ProcedureQueries.list_versions(procedure_id)

      # Only drafts
      ProcedureQueries.list_versions(procedure_id, status: :draft)
  """
  @spec list_versions(procedure_id(), opts()) :: [ProcedureVersion.t()]
  def list_versions(procedure_id, opts \\ []) do
    repo().list_versions(procedure_id, opts)
  end

  @doc """
  Gets the next version number for a procedure.

  Returns 1 if no versions exist, otherwise max(version_number) + 1.
  """
  @spec next_version_number(procedure_id()) :: pos_integer()
  def next_version_number(procedure_id) do
    repo().get_next_version_number(procedure_id)
  end

  @doc """
  Checks if a procedure has an approved version.
  """
  @spec has_approved_version?(procedure_id()) :: boolean()
  def has_approved_version?(procedure_id) do
    case find_approved_version(procedure_id) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Checks if a specific version can be executed.

  A version is executable if it has `:approved` status.
  """
  @spec executable?(version_id()) :: boolean()
  def executable?(version_id) do
    case find_version(version_id) do
      {:ok, version} -> ProcedureVersion.executable?(version)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Checks if a specific version can be edited.

  A version is editable if it has `:draft` status.
  """
  @spec editable?(version_id()) :: boolean()
  def editable?(version_id) do
    case find_version(version_id) do
      {:ok, version} -> ProcedureVersion.editable?(version)
      {:error, :not_found} -> false
    end
  end
end
