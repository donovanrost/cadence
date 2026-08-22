defmodule Cadence.Settings do
  @moduledoc """
  Context facade for managing hierarchical settings.

  Settings support a two-level hierarchy:
  - Organization-level defaults
  - Mission-level overrides (can only be more restrictive than org defaults)

  ## Restrictiveness Rules

  When a mission overrides an org setting, it must be "more restrictive":

  - `:higher` - Mission value must be >= org value (e.g., more approvals required)
  - `:lower` - Mission value must be <= org value
  - `:false_is_stricter` - false is more restrictive than true (e.g., disabling self-approval)
  - `:none` - No restriction, mission can set any valid value

  ## Usage

      # Get effective value for a mission (considers org default + mission override)
      Settings.get(mission, :procedures, :required_approvals)
      #=> 2

      # Set org-level setting
      Settings.set_org(org, :procedures, :required_approvals, 1)

      # Set mission-level override (validates restrictiveness)
      Settings.set_mission(mission, :procedures, :required_approvals, 2)
      #=> {:ok, setting}

      # Trying to set less restrictive value fails
      Settings.set_mission(mission, :procedures, :required_approvals, 0)
      #=> {:error, :less_restrictive_than_org, %{org_value: 1, min_allowed: 1}}

  This module is a thin facade that delegates to:
  - `Cadence.Application.Settings.SettingOperations` for write operations
  - `Cadence.Application.Settings.SettingQueries` for read operations
  """

  alias Cadence.Application.Settings.SettingOperations
  alias Cadence.Application.Settings.SettingQueries
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  ## Public API - Getting Settings

  @doc """
  Gets the effective value for a setting in a mission context.

  This considers the org-level default and any mission-level override.
  If no setting is stored at either level, returns the definition default.
  """
  @spec get(Mission.t() | MissionEntity.t(), atom(), atom()) :: any()
  def get(%MissionEntity{id: mission_id, organization_id: org_id}, namespace, key) do
    SettingQueries.get(mission_id, org_id, namespace, key)
  end

  def get(%Mission{} = mission, namespace, key) do
    mission = ensure_organization_loaded(mission)
    SettingQueries.get(mission.id, mission.organization_id, namespace, key)
  end

  @doc """
  Gets all effective settings for a namespace in a mission context.

  Returns a map of key => value for all settings in the namespace.
  """
  @spec all(Mission.t() | MissionEntity.t(), atom()) :: map()
  def all(%MissionEntity{id: mission_id, organization_id: org_id}, namespace) do
    SettingQueries.all(mission_id, org_id, namespace)
  end

  def all(%Mission{} = mission, namespace) do
    mission = ensure_organization_loaded(mission)
    SettingQueries.all(mission.id, mission.organization_id, namespace)
  end

  @doc """
  Gets the org-level value for a setting.

  Returns the stored value or the definition default if not stored.
  """
  @spec get_org(Organization.t(), atom(), atom()) :: any()
  def get_org(%Organization{id: org_id}, namespace, key) do
    SettingQueries.get_org_value_or_default(org_id, namespace, key)
  end

  @doc """
  Gets the mission-level override for a setting (not the effective value).

  Returns nil if no mission-level override exists.
  """
  @spec get_mission_override(Mission.t() | MissionEntity.t(), atom(), atom()) :: any() | nil
  def get_mission_override(%MissionEntity{id: mission_id}, namespace, key) do
    SettingQueries.get_mission_override(mission_id, namespace, key)
  end

  def get_mission_override(%Mission{id: mission_id}, namespace, key) do
    SettingQueries.get_mission_override(mission_id, namespace, key)
  end

  ## Public API - Setting Values

  @doc """
  Sets an org-level setting value.

  Validates the value against the setting definition.
  """
  @spec set_org(Organization.t(), atom(), atom(), any()) ::
          {:ok, any()} | {:error, term()}
  def set_org(%Organization{id: org_id}, namespace, key, value) do
    SettingOperations.set_org(org_id, namespace, key, value)
  end

  @doc """
  Sets a mission-level override for a setting.

  Validates that the value is more restrictive than the org default.
  """
  @spec set_mission(Mission.t() | MissionEntity.t(), atom(), atom(), any()) ::
          {:ok, any()}
          | {:error, :less_restrictive_than_org, map()}
          | {:error, term()}
  def set_mission(%MissionEntity{id: mission_id, organization_id: org_id}, namespace, key, value) do
    SettingOperations.set_mission(mission_id, org_id, namespace, key, value)
  end

  def set_mission(%Mission{} = mission, namespace, key, value) do
    mission = ensure_organization_loaded(mission)
    SettingOperations.set_mission(mission.id, mission.organization_id, namespace, key, value)
  end

  @doc """
  Clears a mission-level override, reverting to the org default.
  """
  @spec clear_mission_override(Mission.t() | MissionEntity.t(), atom(), atom()) ::
          :ok | {:error, :not_found}
  def clear_mission_override(%MissionEntity{id: mission_id}, namespace, key) do
    SettingOperations.clear_mission_override(mission_id, namespace, key)
  end

  def clear_mission_override(%Mission{id: mission_id}, namespace, key) do
    SettingOperations.clear_mission_override(mission_id, namespace, key)
  end

  ## Public API - Definitions

  @doc """
  Gets a setting definition by namespace and key.
  """
  @spec get_definition(atom(), atom()) :: map() | nil
  def get_definition(namespace, key) do
    SettingQueries.get_definition(namespace, key)
  end

  @doc """
  Lists all setting definitions for a namespace.
  """
  @spec list_definitions(atom()) :: [map()]
  def list_definitions(namespace) do
    SettingQueries.list_definitions(namespace)
  end

  @doc """
  Lists all available namespaces.
  """
  @spec list_namespaces() :: [atom()]
  def list_namespaces do
    SettingQueries.list_namespaces()
  end

  ## Public API - UI Helpers

  @doc """
  Gets all settings for an organization with their current values and metadata.
  Useful for rendering settings UI.
  """
  @spec get_all_org_settings(Organization.t(), atom()) :: [map()]
  def get_all_org_settings(%Organization{id: org_id}, namespace) do
    SettingQueries.get_all_org_settings(org_id, namespace)
  end

  @doc """
  Gets all settings for a mission with org defaults, overrides, and constraints.
  Useful for rendering mission settings UI with override support.
  """
  @spec get_all_mission_settings(Mission.t() | MissionEntity.t(), atom()) :: [map()]
  def get_all_mission_settings(%MissionEntity{id: mission_id, organization_id: org_id}, namespace) do
    SettingQueries.get_all_mission_settings(mission_id, org_id, namespace)
  end

  def get_all_mission_settings(%Mission{} = mission, namespace) do
    mission = ensure_organization_loaded(mission)
    SettingQueries.get_all_mission_settings(mission.id, mission.organization_id, namespace)
  end

  @doc """
  Gets display information for a settings namespace.
  Returns label, description, and icon for UI rendering.
  """
  @spec get_namespace_info(atom()) :: map() | nil
  def get_namespace_info(namespace) do
    SettingQueries.get_namespace_info(namespace)
  end

  @doc """
  Lists all namespaces with their display information.
  """
  @spec list_namespaces_with_info() :: [map()]
  def list_namespaces_with_info do
    SettingQueries.list_namespaces_with_info()
  end

  ## Public API - Validation Helpers

  @doc """
  Checks if a mission can set a specific value for a setting.

  Returns `:ok` or `{:error, :less_restrictive_than_org, details}`.
  """
  @spec can_mission_override?(Mission.t() | MissionEntity.t(), atom(), atom(), any()) ::
          :ok | {:error, :less_restrictive_than_org, map()} | {:error, :unknown_setting}
  def can_mission_override?(
        %MissionEntity{id: mission_id, organization_id: org_id},
        namespace,
        key,
        value
      ) do
    SettingOperations.can_set_mission_value?(mission_id, org_id, namespace, key, value)
  end

  def can_mission_override?(%Mission{} = mission, namespace, key, value) do
    mission = ensure_organization_loaded(mission)

    SettingOperations.can_set_mission_value?(
      mission.id,
      mission.organization_id,
      namespace,
      key,
      value
    )
  end

  ## Private Functions

  defp ensure_organization_loaded(%Mission{organization: %Organization{}} = mission) do
    mission
  end

  defp ensure_organization_loaded(%Mission{} = mission) do
    Repo.preload(mission, :organization)
  end
end
