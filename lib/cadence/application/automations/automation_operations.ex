defmodule Cadence.Application.Automations.AutomationOperations do
  @moduledoc """
  Use case module for automation CRUD and state operations.

  This module provides operations for creating, updating, deleting,
  enabling/disabling automations, and recording trigger events.

  All operations:
  1. Validate using domain entity logic
  2. Persist via repository
  3. Optionally broadcast for cache updates

  ## Usage

      # Create an automation
      {:ok, automation} = AutomationOperations.create(attrs)

      # Enable an automation
      {:ok, automation} = AutomationOperations.enable(automation)

      # Record a trigger
      {:ok, automation} = AutomationOperations.record_trigger(automation)
  """

  alias Cadence.Domain.Automations.Entities.Automation

  @type automation_id :: String.t()
  @type organization_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :automation_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository
    )
  end

  # Get configured event publisher
  defp event_publisher do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end

  @doc """
  Creates a new automation.

  ## Parameters

  - `attrs` - Map containing automation attributes:
    - `:name` (required)
    - `:organization_id` (required)
    - `:trigger_type` (required)
    - `:procedure_id` (required)
    - `:mission_id` (optional)
    - `:trigger_conditions` (optional)
    - `:enabled` (optional, default: true)
    - `:cooldown_seconds` (optional)
    - `:max_executions_per_hour` (optional)

  ## Returns

  - `{:ok, automation}` - Successfully created
  - `{:error, changeset}` - Validation failed
  """
  @spec create(map()) :: {:ok, Automation.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, automation} <- Automation.new(attrs),
         {:ok, saved} <- repo().save(automation) do
      broadcast_change(saved, :created)
      {:ok, saved}
    end
  end

  @doc """
  Updates an existing automation.

  ## Parameters

  - `automation` - The automation to update
  - `attrs` - Map of attributes to update

  ## Returns

  - `{:ok, automation}` - Successfully updated
  - `{:error, changeset}` - Validation failed
  """
  @spec update(Automation.t(), map()) :: {:ok, Automation.t()} | {:error, term()}
  def update(%Automation{} = automation, attrs) do
    with {:ok, updated} <- Automation.update(automation, attrs),
         {:ok, saved} <- repo().save(updated) do
      broadcast_change(saved, :updated)
      {:ok, saved}
    end
  end

  @doc """
  Deletes an automation.

  ## Returns

  - `{:ok, automation}` - Successfully deleted
  - `{:error, reason}` - Deletion failed
  """
  @spec delete(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def delete(%Automation{} = automation) do
    case repo().delete(automation) do
      {:ok, deleted} ->
        broadcast_change(deleted, :deleted)
        {:ok, deleted}

      error ->
        error
    end
  end

  @doc """
  Enables an automation.

  ## Returns

  - `{:ok, automation}` - Successfully enabled
  - `{:error, changeset}` - Update failed
  """
  @spec enable(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def enable(%Automation{} = automation) do
    case repo().enable(automation) do
      {:ok, enabled} ->
        broadcast_change(enabled, :enabled)
        {:ok, enabled}

      error ->
        error
    end
  end

  @doc """
  Disables an automation.

  ## Returns

  - `{:ok, automation}` - Successfully disabled
  - `{:error, changeset}` - Update failed
  """
  @spec disable(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def disable(%Automation{} = automation) do
    case repo().disable(automation) do
      {:ok, disabled} ->
        broadcast_change(disabled, :disabled)
        {:ok, disabled}

      error ->
        error
    end
  end

  @doc """
  Records that an automation was triggered.

  Updates last_triggered_at and increments trigger_count.

  ## Returns

  - `{:ok, automation}` - Successfully recorded
  - `{:error, changeset}` - Update failed
  """
  @spec record_trigger(Automation.t()) :: {:ok, Automation.t()} | {:error, term()}
  def record_trigger(%Automation{} = automation) do
    repo().record_trigger(automation)
  end

  @doc """
  Checks if an automation can be triggered based on its rate limits.

  Returns:
  - `{:ok, :allowed}` if the trigger is allowed
  - `{:error, :cooldown}` if still in cooldown period
  - `{:error, :rate_limited}` if max executions per hour exceeded
  """
  @spec check_rate_limits(Automation.t()) :: {:ok, :allowed} | {:error, :cooldown | :rate_limited}
  def check_rate_limits(%Automation{} = automation) do
    cond do
      Automation.in_cooldown?(automation) ->
        {:error, :cooldown}

      rate_limited?(automation) ->
        {:error, :rate_limited}

      true ->
        {:ok, :allowed}
    end
  end

  @doc """
  Checks if an event matches an automation's trigger conditions.

  Delegates to the domain entity's condition matching logic.
  """
  @spec matches_conditions?(Automation.t(), map()) :: boolean()
  def matches_conditions?(%Automation{} = automation, event) do
    Automation.matches_conditions?(automation, event)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp execution_repo do
    Application.get_env(
      :cadence,
      :automation_execution_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationExecutionRepository
    )
  end

  defp rate_limited?(%Automation{max_executions_per_hour: nil}), do: false

  defp rate_limited?(%Automation{id: id, max_executions_per_hour: max}) do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
    execution_repo().count_recent(id, one_hour_ago) >= max
  end

  defp broadcast_change(%Automation{organization_id: org_id} = automation, event_type) do
    topic = "organization:#{org_id}:automations"

    event_publisher().publish(topic, %{
      type: :automation_changed,
      event: event_type,
      automation_id: automation.id,
      name: automation.name,
      enabled: automation.enabled
    })
  rescue
    # Don't fail operations if broadcasting fails
    _ -> :ok
  end
end
