defmodule Cadence.Ports.Repository.Procedures.ApprovalOperations do
  @moduledoc """
  Port (behavior) defining the contract for procedure approval persistence operations.

  This narrow interface follows the Interface Segregation Principle, allowing
  use cases to depend only on the approval operations they need.

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository` - Production
  - `Cadence.Test.Adapters.InMemoryProcedureRepository` - Testing
  """

  alias Cadence.Procedures.ProcedureApproval

  @type id :: String.t()
  @type version_id :: String.t()
  @type user_id :: String.t()
  @type decision :: :approved | :rejected
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds an approval record by ID.

  Returns `{:ok, approval}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find_approval(id()) :: {:ok, ProcedureApproval.t()} | {:error, :not_found}

  @doc """
  Finds a user's approval decision for a specific version.

  Returns `{:ok, approval}` if the user has already submitted a decision,
  `{:error, :not_found}` if no decision exists.
  """
  @callback find_user_approval(version_id(), user_id()) ::
              {:ok, ProcedureApproval.t()} | {:error, :not_found}

  @doc """
  Lists all approval records for a version.

  ## Options

  - `:preload` - Associations to preload (default: [:user])
  """
  @callback list_approvals(version_id(), opts :: keyword()) :: [ProcedureApproval.t()]

  @doc """
  Saves an approval record (insert or update).

  Returns `{:ok, approval}` on success, `{:error, reason}` on failure.
  """
  @callback save_approval(attrs :: map()) ::
              {:ok, ProcedureApproval.t()} | {:error, error()}

  @doc """
  Counts approvals for a version by decision type.

  Returns the count of approvals with the given decision.
  """
  @callback count_approvals(version_id(), decision()) :: non_neg_integer()

  @doc """
  Deletes all approvals for a version.

  Useful when resetting approval workflow.
  Returns `{:ok, count}` with the number of deleted records.
  """
  @callback delete_approvals(version_id()) :: {:ok, non_neg_integer()}

  @doc """
  Returns the configured approval operations implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :approval_operations,
      Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository
    )
  end
end
