defmodule Cadence.Application.Alerting.ManageAlarmRules do
  @moduledoc """
  Use case module for managing alarm rules.

  Alarm rules define conditions that trigger alarms when telemetry
  or other events meet specified criteria.

  ## Rule Scope

  Rules can be scoped at different levels:
  - Organization-wide: Applies to all missions
  - Mission-specific: Applies to one mission
  - Target-specific: Applies to one spacecraft

  More specific rules take precedence over general rules.

  ## Usage

      # Create a new rule
      {:ok, rule} = ManageAlarmRules.create(%{
        organization_id: org_id,
        mission_id: mission_id,
        name: "High CPU Temperature",
        event_type: "telemetry_limit",
        severity: :warning,
        conditions: %{"source_id" => "HEALTH.cpu_temp"}
      })

      # Enable/disable
      {:ok, rule} = ManageAlarmRules.enable(rule)
      {:ok, rule} = ManageAlarmRules.disable(rule, user_id, "Maintenance")

      # Delete
      {:ok, rule} = ManageAlarmRules.delete(rule)
  """

  import Ecto.Query, warn: false
  alias Cadence.Alarms.AlarmRule
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type rule_id :: String.t()
  @type user_id :: String.t()
  @type attrs :: map()
  @type opts :: keyword()

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Lists all alarm rules for an organization.

  ## Options

  - `:mission_id` - Filter to rules for a specific mission (includes org-wide rules)
  - `:target_id` - Filter to rules for a specific target
  - `:event_type` - Filter by event type
  - `:enabled` - Filter by enabled status (default: all)

  ## Examples

      # All rules for organization
      ManageAlarmRules.list(org_id)

      # Rules applicable to a mission
      ManageAlarmRules.list(org_id, mission_id: mission_id)

      # Only enabled telemetry rules
      ManageAlarmRules.list(org_id, event_type: "telemetry_limit", enabled: true)
  """
  @spec list(organization_id(), opts()) :: [AlarmRule.t()]
  def list(organization_id, opts \\ []) do
    AlarmRule
    |> where([r], r.organization_id == ^organization_id)
    |> apply_rule_filters(opts)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single alarm rule by ID.

  Returns `nil` if not found.
  """
  @spec get(rule_id()) :: AlarmRule.t() | nil
  def get(id), do: Repo.get(AlarmRule, id)

  @doc """
  Gets a single alarm rule by ID, raising if not found.
  """
  @spec get!(rule_id()) :: AlarmRule.t()
  def get!(id), do: Repo.get!(AlarmRule, id)

  @doc """
  Finds matching rules for a given event.

  Returns rules in specificity order (most specific first).
  Only returns enabled rules.

  ## Parameters

  - `organization_id` - Organization UUID
  - `mission_id` - Mission UUID
  - `target_id` - Target UUID (or nil)
  - `event_type` - Type of event (e.g., "telemetry_limit")
  """
  @spec find_matching(organization_id(), String.t(), String.t() | nil, String.t()) ::
          [AlarmRule.t()]
  def find_matching(organization_id, mission_id, target_id, event_type) do
    AlarmRule
    |> where([r], r.organization_id == ^organization_id)
    |> where([r], r.event_type == ^event_type)
    |> where([r], r.enabled == true)
    |> apply_scope_filter(mission_id, target_id)
    |> Repo.all()
    |> Enum.sort_by(&AlarmRule.specificity/1, :desc)
  end

  # ===========================================================================
  # Commands
  # ===========================================================================

  @doc """
  Creates a new alarm rule.

  ## Required Attributes

  - `:organization_id` - Organization UUID
  - `:name` - Rule name
  - `:event_type` - Type of event to match
  - `:severity` - Alarm severity when triggered

  ## Optional Attributes

  - `:mission_id` - Scope to specific mission
  - `:target_id` - Scope to specific target
  - `:conditions` - Matching conditions map
  - `:message_template` - Template for alarm message
  - `:notification_channels` - Where to send notifications
  - `:auto_acknowledge` - Auto-acknowledge on trigger
  - `:auto_shelve_duration_minutes` - Auto-shelve duration
  - `:cooldown_seconds` - Minimum time between triggers
  """
  @spec create(attrs()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    result =
      %AlarmRule{}
      |> AlarmRule.changeset(attrs)
      |> Repo.insert()

    with {:ok, rule} <- result do
      broadcast_rule_change(rule, :created)
      {:ok, rule}
    end
  end

  @doc """
  Updates an alarm rule.

  ## Updatable Attributes

  All attributes except `:organization_id` can be updated.
  """
  @spec update(AlarmRule.t(), attrs()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def update(%AlarmRule{} = rule, attrs) do
    result =
      rule
      |> AlarmRule.changeset(attrs)
      |> Repo.update()

    with {:ok, updated_rule} <- result do
      broadcast_rule_change(updated_rule, :updated)
      {:ok, updated_rule}
    end
  end

  @doc """
  Enables an alarm rule.

  Clears any disabled_at, disabled_by, and disabled_reason fields.
  """
  @spec enable(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def enable(%AlarmRule{} = rule) do
    result =
      rule
      |> AlarmRule.enable_changeset(%{enabled: true})
      |> Repo.update()

    with {:ok, updated_rule} <- result do
      broadcast_rule_change(updated_rule, :enabled)
      {:ok, updated_rule}
    end
  end

  @doc """
  Disables an alarm rule.

  Records who disabled it and why.

  ## Parameters

  - `rule` - The rule to disable
  - `user_id` - UUID of user disabling (optional)
  - `reason` - Reason for disabling (optional)
  """
  @spec disable(AlarmRule.t(), user_id() | nil, String.t() | nil) ::
          {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def disable(%AlarmRule{} = rule, user_id \\ nil, reason \\ nil) do
    result =
      rule
      |> AlarmRule.enable_changeset(%{
        enabled: false,
        disabled_at: DateTime.utc_now(),
        disabled_by_id: user_id,
        disabled_reason: reason
      })
      |> Repo.update()

    with {:ok, updated_rule} <- result do
      broadcast_rule_change(updated_rule, :disabled)
      {:ok, updated_rule}
    end
  end

  @doc """
  Deletes an alarm rule.

  Note: This does not affect existing alarms that were created by this rule.
  """
  @spec delete(AlarmRule.t()) :: {:ok, AlarmRule.t()} | {:error, Ecto.Changeset.t()}
  def delete(%AlarmRule{} = rule) do
    result = Repo.delete(rule)

    with {:ok, deleted_rule} <- result do
      broadcast_rule_change(deleted_rule, :deleted)
      {:ok, deleted_rule}
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc """
  Checks if a rule would match the given event context.

  Useful for testing rule conditions before saving.
  """
  @spec would_match?(AlarmRule.t(), map()) :: boolean()
  def would_match?(%AlarmRule{conditions: conditions}, event_context)
      when is_map(conditions) do
    Enum.all?(conditions, fn {key, expected} ->
      actual = Map.get(event_context, key) || Map.get(event_context, String.to_atom(key))
      matches_condition?(actual, expected)
    end)
  end

  def would_match?(_, _), do: true

  defp matches_condition?(actual, expected) when is_list(expected) do
    actual in expected
  end

  defp matches_condition?(actual, expected) do
    actual == expected
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp event_publisher, do: EventPublisher.impl()

  # Broadcasts alarm rule changes for cache invalidation and UI updates
  defp broadcast_rule_change(%AlarmRule{} = rule, event_type) do
    # Global topic for cache invalidation
    event_publisher().publish(
      "alarm_rules:changed",
      {:alarm_rule_changed, event_type, rule}
    )

    # Mission-specific topic for UI updates
    if rule.mission_id do
      event_publisher().publish(
        "mission:#{rule.mission_id}:alarm_rules",
        {:alarm_rule_changed, event_type, rule}
      )
    end

    :ok
  end

  defp apply_rule_filters(query, opts) do
    query
    |> maybe_filter_by_mission(opts[:mission_id])
    |> maybe_filter_by_target(opts[:target_id])
    |> maybe_filter_by_event_type(opts[:event_type])
    |> maybe_filter_by_enabled(opts[:enabled])
  end

  defp apply_scope_filter(query, mission_id, nil) do
    # When no target specified, return org-wide and mission-wide rules only
    where(
      query,
      [r],
      (is_nil(r.mission_id) and is_nil(r.target_id)) or
        (r.mission_id == ^mission_id and is_nil(r.target_id))
    )
  end

  defp apply_scope_filter(query, mission_id, target_id) do
    # When target specified, return org-wide, mission-wide, and target-specific rules
    where(
      query,
      [r],
      (is_nil(r.mission_id) and is_nil(r.target_id)) or
        (r.mission_id == ^mission_id and is_nil(r.target_id)) or
        (r.mission_id == ^mission_id and r.target_id == ^target_id)
    )
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [r], is_nil(r.mission_id) or r.mission_id == ^mission_id)
  end

  defp maybe_filter_by_target(query, nil), do: query
  defp maybe_filter_by_target(query, target_id), do: where(query, [r], r.target_id == ^target_id)

  defp maybe_filter_by_event_type(query, nil), do: query

  defp maybe_filter_by_event_type(query, event_type),
    do: where(query, [r], r.event_type == ^event_type)

  defp maybe_filter_by_enabled(query, nil), do: query
  defp maybe_filter_by_enabled(query, enabled), do: where(query, [r], r.enabled == ^enabled)
end
