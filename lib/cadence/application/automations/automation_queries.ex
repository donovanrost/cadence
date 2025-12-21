defmodule Cadence.Application.Automations.AutomationQueries do
  @moduledoc """
  Use case module for querying automations.

  This module provides read-only operations for listing, counting,
  and finding automations. It works with domain entities and uses
  repository ports for data access.

  ## Usage

      # List automations for an organization
      automations = AutomationQueries.list(organization_id)

      # List with filters
      automations = AutomationQueries.list(organization_id, mission_id: mission_id, enabled_only: true)

      # Find specific automation
      {:ok, automation} = AutomationQueries.find(id, organization_id)
  """

  alias Cadence.Automations.Automation

  @type id :: String.t()
  @type organization_id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()

  # Get configured repository (allows for DI in tests)
  defp repo do
    Application.get_env(
      :cadence,
      :automation_repository,
      Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository
    )
  end

  @doc """
  Finds an automation by ID scoped to an organization.

  Returns `{:ok, automation}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(id(), organization_id()) :: {:ok, Automation.t()} | {:error, :not_found}
  def find(id, organization_id), do: repo().find(id, organization_id)

  @doc """
  Finds an automation by ID scoped to an organization, raising if not found.
  """
  @spec find!(id(), organization_id()) :: Automation.t()
  def find!(id, organization_id) do
    case find(id, organization_id) do
      {:ok, automation} -> automation
      {:error, :not_found} -> raise "Automation not found: #{id}"
    end
  end

  @doc """
  Finds an automation by ID without organization scoping.

  WARNING: Only use for internal operations where organization context is verified elsewhere.
  """
  @spec find_unscoped(id()) :: {:ok, Automation.t()} | {:error, :not_found}
  def find_unscoped(id), do: repo().find_unscoped(id)

  @doc """
  Lists automations for an organization.

  ## Options

  - `:mission_id` - Filter by mission
  - `:enabled_only` - Only return enabled automations
  - `:trigger_type` - Filter by trigger type (e.g., :alarm_triggered)
  - `:limit` - Maximum number of results
  - `:offset` - Offset for pagination

  ## Examples

      # All automations
      AutomationQueries.list(org_id)

      # Only enabled automations for a mission
      AutomationQueries.list(org_id, mission_id: mission_id, enabled_only: true)

      # Alarm-triggered automations only
      AutomationQueries.list(org_id, trigger_type: :alarm_triggered)
  """
  @spec list(organization_id(), opts()) :: [Automation.t()]
  def list(organization_id, opts \\ []) do
    repo().list(organization_id, opts)
  end

  @doc """
  Lists enabled automations for a specific mission.

  Includes both mission-specific automations and organization-wide automations
  (those without a mission_id) that are enabled.

  Used by the automation engine to load automations into the ETS cache.
  """
  @spec list_enabled_for_mission(organization_id(), mission_id()) :: [Automation.t()]
  def list_enabled_for_mission(organization_id, mission_id) do
    repo().list_enabled_for_mission(organization_id, mission_id)
  end

  @doc """
  Counts automations by trigger type for an organization.

  Returns a map of trigger_type to count.

  ## Example

      %{
        alarm_triggered: 5,
        limit_violation: 3,
        procedure_completed: 2
      }
  """
  @spec count_by_trigger_type(organization_id()) :: map()
  def count_by_trigger_type(organization_id) do
    list(organization_id)
    |> Enum.group_by(& &1.trigger_type)
    |> Enum.into(%{}, fn {type, automations} -> {type, length(automations)} end)
  end

  @doc """
  Counts enabled automations for a mission.
  """
  @spec count_enabled(organization_id(), mission_id()) :: non_neg_integer()
  def count_enabled(organization_id, mission_id) do
    list_enabled_for_mission(organization_id, mission_id)
    |> length()
  end
end
