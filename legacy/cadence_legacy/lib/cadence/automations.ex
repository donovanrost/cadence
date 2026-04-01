defmodule Cadence.Automations do
  @moduledoc """
  The Automations context.

  Manages automation rules that trigger procedures in response to events
  like alarm state changes, telemetry limit violations, or procedure completions.

  This module serves as the public API facade, delegating to:
  - `Cadence.Application.Automations.AutomationQueries` for read operations
  - `Cadence.Application.Automations.AutomationOperations` for write operations
  """

  alias Cadence.Application.Automations.AutomationOperations
  alias Cadence.Application.Automations.AutomationQueries
  alias Cadence.Domain.Automations.Entities.Automation
  alias Cadence.Domain.Automations.Entities.AutomationExecution
  alias Cadence.Time, as: CadenceTime

  # ============================================================================
  # Automation Queries
  # ============================================================================

  @doc """
  Lists automations for an organization, optionally filtered by mission.
  """
  @spec list_automations(String.t(), keyword()) :: [Automation.t()]
  def list_automations(organization_id, opts \\ []) do
    AutomationQueries.list(organization_id, opts)
  end

  @doc """
  Gets a single automation scoped to an organization.

  Returns `nil` if not found or if the automation doesn't belong to the organization.
  """
  @spec get_automation(String.t(), String.t()) :: Automation.t() | nil
  def get_automation(id, organization_id) do
    case AutomationQueries.find(id, organization_id) do
      {:ok, automation} -> automation
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single automation scoped to an organization, raises if not found.
  """
  @spec get_automation!(String.t(), String.t()) :: Automation.t()
  def get_automation!(id, organization_id) do
    AutomationQueries.find!(id, organization_id)
  end

  @doc """
  Gets a single automation by ID without organization scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where organization context is verified elsewhere (e.g., automation engine).
  """
  @spec get_automation_unscoped(String.t()) :: Automation.t() | nil
  def get_automation_unscoped(id) do
    case AutomationQueries.find_unscoped(id) do
      {:ok, automation} -> automation
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Lists enabled automations for a specific mission.
  """
  @spec list_enabled_for_mission(String.t(), String.t()) :: [Automation.t()]
  def list_enabled_for_mission(organization_id, mission_id) do
    AutomationQueries.list_enabled_for_mission(organization_id, mission_id)
  end

  # ============================================================================
  # Automation Operations
  # ============================================================================

  @doc """
  Creates an automation.
  """
  @spec create_automation(map()) :: {:ok, Automation.t()} | {:error, term()}
  def create_automation(attrs) do
    AutomationOperations.create(attrs)
  end

  @doc """
  Updates an automation.
  """
  @spec update_automation(Automation.t(), map()) :: {:ok, Automation.t()} | {:error, term()}
  def update_automation(%Automation{} = automation, attrs) do
    AutomationOperations.update(automation, attrs)
  end

  @doc """
  Deletes an automation.
  """
  @spec delete_automation(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def delete_automation(%Automation{} = automation) do
    AutomationOperations.delete(automation)
  end

  @doc """
  Enables an automation.
  """
  @spec enable_automation(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def enable_automation(%Automation{} = automation) do
    AutomationOperations.enable(automation)
  end

  @doc """
  Disables an automation.
  """
  @spec disable_automation(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def disable_automation(%Automation{} = automation) do
    AutomationOperations.disable(automation)
  end

  @doc """
  Records that an automation was triggered.
  Updates the trigger tracking fields.
  """
  @spec record_trigger(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def record_trigger(%Automation{} = automation) do
    AutomationOperations.record_trigger(automation)
  end

  # ============================================================================
  # Executions
  # ============================================================================

  # Get configured execution repository
  defp execution_repo do
    Application.get_env(
      :cadence,
      :automation_execution_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationExecutionRepository
    )
  end

  @doc """
  Lists automation executions, optionally filtered.
  """
  @spec list_executions(keyword()) :: [AutomationExecution.t()]
  def list_executions(opts \\ []) do
    execution_repo().list(opts)
  end

  @doc """
  Gets an execution by ID.
  """
  @spec get_execution(String.t()) :: AutomationExecution.t() | nil
  def get_execution(id) do
    case execution_repo().find(id) do
      {:ok, execution} -> execution
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets an execution by ID with preloads.
  """
  @spec get_execution!(String.t()) :: AutomationExecution.t()
  def get_execution!(id) do
    case execution_repo().find_with_automation(id) do
      {:ok, execution} -> execution
      {:error, :not_found} -> raise "AutomationExecution not found: #{id}"
    end
  end

  @doc """
  Creates an execution record.

  If the execution has an idempotency_key that already exists, returns
  `{:error, :duplicate}` to signal that this is a duplicate event.
  """
  @spec create_execution(map()) :: {:ok, AutomationExecution.t()} | {:error, :duplicate | term()}
  def create_execution(attrs) do
    with {:ok, execution} <- AutomationExecution.new(attrs) do
      execution_repo().save(execution)
    end
  end

  @doc """
  Updates an execution's status.
  """
  @spec update_execution_status(AutomationExecution.t(), map()) ::
          {:ok, AutomationExecution.t()} | {:error, term()}
  def update_execution_status(%AutomationExecution{} = execution, attrs) do
    with {:ok, updated} <- AutomationExecution.update_status(execution, attrs) do
      execution_repo().save(updated)
    end
  end

  # ============================================================================
  # Rate Limiting
  # ============================================================================

  @doc """
  Checks if an automation can be triggered based on its rate limits.

  Returns:
  - `{:ok, :allowed}` if the trigger is allowed
  - `{:error, :cooldown}` if still in cooldown period
  - `{:error, :rate_limited}` if max executions per hour exceeded
  """
  @spec check_rate_limits(Automation.t()) ::
          {:ok, :allowed} | {:error, :cooldown | :rate_limited}
  def check_rate_limits(%Automation{} = automation) do
    AutomationOperations.check_rate_limits(automation)
  end

  @doc """
  Counts executions for an automation within the last hour.

  Used for rate limiting checks.
  """
  @spec count_recent_executions(String.t()) :: non_neg_integer()
  def count_recent_executions(automation_id) do
    one_hour_ago = DateTime.add(CadenceTime.now(), -1, :hour)
    execution_repo().count_recent(automation_id, one_hour_ago)
  end

  # ============================================================================
  # Condition Matching
  # ============================================================================

  @doc """
  Checks if an event matches an automation's trigger conditions.

  Returns `true` if all conditions match, `false` otherwise.
  """
  @spec matches_conditions?(Automation.t(), map()) :: boolean()
  def matches_conditions?(%Automation{} = automation, event) do
    Automation.matches_conditions?(automation, event)
  end
end
