defmodule Cadence.Application.Settings.SettingQueries do
  @moduledoc """
  Use case module for querying settings.

  Provides read-only operations for finding setting values with proper
  hierarchical resolution (mission → org → default fallback).

  ## Usage

      # Get effective value for a mission context
      value = SettingQueries.get(mission_id, org_id, :procedures, :required_approvals)

      # Get org-level value
      value = SettingQueries.get_org_value(org_id, :procedures, :required_approvals)

      # Get all settings for a namespace with UI metadata
      settings = SettingQueries.get_all_mission_settings(mission_id, org_id, :procedures)
  """

  alias Cadence.Domain.Settings.ValueObjects.SettingRestrictiveness
  alias Cadence.Ports.Repository.Settings.SettingsRepository
  alias Cadence.Settings.Setting, as: SettingSchema

  @type org_id :: String.t()
  @type mission_id :: String.t()
  @type namespace :: atom()
  @type key :: atom()

  # Get configured repository
  defp repo do
    SettingsRepository.impl()
  end

  # Registry of all definition modules
  @definition_modules [
    Cadence.Settings.Definitions.Procedures
  ]

  @doc """
  Gets the effective value for a setting in a mission context.

  This considers the org-level default and any mission-level override.
  If no setting is stored at either level, returns the definition default.
  """
  @spec get(mission_id(), org_id(), namespace(), key()) :: any()
  def get(mission_id, org_id, namespace, key) do
    definition = get_definition(namespace, key)

    if is_nil(definition) do
      nil
    else
      mission_value = get_stored_value(mission_id, "mission", namespace, key)
      org_value = get_stored_value(org_id, "organization", namespace, key)

      cond do
        not is_nil(mission_value) -> mission_value
        not is_nil(org_value) -> org_value
        true -> definition.default
      end
    end
  end

  @doc """
  Gets all effective settings for a namespace in a mission context.

  Returns a map of key => value for all settings in the namespace.
  """
  @spec all(mission_id(), org_id(), namespace()) :: map()
  def all(mission_id, org_id, namespace) do
    list_definitions(namespace)
    |> Enum.map(fn definition ->
      {definition.key, get(mission_id, org_id, namespace, definition.key)}
    end)
    |> Map.new()
  end

  @doc """
  Gets the org-level value for a setting.

  Returns the stored value or nil if not stored (use definition default separately).
  """
  @spec get_org_value(org_id(), namespace(), key()) :: any() | nil
  def get_org_value(org_id, namespace, key) do
    get_stored_value(org_id, "organization", namespace, key)
  end

  @doc """
  Gets the org-level value or definition default.
  """
  @spec get_org_value_or_default(org_id(), namespace(), key()) :: any()
  def get_org_value_or_default(org_id, namespace, key) do
    case get_org_value(org_id, namespace, key) do
      nil ->
        case get_definition(namespace, key) do
          nil -> nil
          definition -> definition.default
        end
      value -> value
    end
  end

  @doc """
  Gets the mission-level override for a setting (not the effective value).

  Returns nil if no mission-level override exists.
  """
  @spec get_mission_override(mission_id(), namespace(), key()) :: any() | nil
  def get_mission_override(mission_id, namespace, key) do
    get_stored_value(mission_id, "mission", namespace, key)
  end

  @doc """
  Gets all settings for an organization with their current values and metadata.
  Useful for rendering settings UI.
  """
  @spec get_all_org_settings(org_id(), namespace()) :: [map()]
  def get_all_org_settings(org_id, namespace) do
    list_definitions(namespace)
    |> Enum.filter(fn def -> def.scope in [:both, :org_only] end)
    |> Enum.map(fn definition ->
      value = get_org_value_or_default(org_id, namespace, definition.key)

      %{
        key: definition.key,
        label: definition.label,
        description: definition.description,
        type: definition.type,
        default: definition.default,
        value: value,
        restrictiveness: definition.restrictiveness,
        validate: definition.validate,
        scope: definition.scope
      }
    end)
  end

  @doc """
  Gets all settings for a mission with org defaults, overrides, and constraints.
  Useful for rendering mission settings UI with override support.
  """
  @spec get_all_mission_settings(mission_id(), org_id(), namespace()) :: [map()]
  def get_all_mission_settings(mission_id, org_id, namespace) do
    list_definitions(namespace)
    |> Enum.filter(fn def -> def.scope in [:both, :mission_only] end)
    |> Enum.map(fn definition ->
      org_value = get_org_value_or_default(org_id, namespace, definition.key)
      mission_override = get_mission_override(mission_id, namespace, definition.key)

      %{
        key: definition.key,
        label: definition.label,
        description: definition.description,
        type: definition.type,
        org_value: org_value,
        mission_override: mission_override,
        has_override: not is_nil(mission_override),
        effective_value: if(is_nil(mission_override), do: org_value, else: mission_override),
        restrictiveness: definition.restrictiveness,
        validate: definition.validate,
        scope: definition.scope,
        # Computed constraints for UI
        min_value: SettingRestrictiveness.min_value(definition.restrictiveness, org_value, definition.validate),
        max_value: SettingRestrictiveness.max_value(definition.restrictiveness, org_value, definition.validate),
        can_override: SettingRestrictiveness.can_override?(definition.restrictiveness, org_value)
      }
    end)
  end

  @doc """
  Gets a setting definition by namespace and key.
  """
  @spec get_definition(namespace(), key()) :: map() | nil
  def get_definition(namespace, key) do
    case find_definition_module(namespace) do
      nil -> nil
      module -> module.get_definition(key)
    end
  end

  @doc """
  Lists all setting definitions for a namespace.
  """
  @spec list_definitions(namespace()) :: [map()]
  def list_definitions(namespace) do
    case find_definition_module(namespace) do
      nil -> []
      module -> module.list_definitions()
    end
  end

  @doc """
  Lists all available namespaces.
  """
  @spec list_namespaces() :: [atom()]
  def list_namespaces do
    Enum.map(@definition_modules, & &1.__namespace__())
  end

  @doc """
  Gets display information for a settings namespace.
  Returns label, description, and icon for UI rendering.
  """
  @spec get_namespace_info(namespace()) :: map() | nil
  def get_namespace_info(namespace) do
    case namespace do
      :procedures ->
        %{
          key: :procedures,
          label: "Procedures",
          description: "Settings for procedure approval workflows",
          icon: "hero-document-text"
        }

      _ ->
        nil
    end
  end

  @doc """
  Lists all namespaces with their display information.
  """
  @spec list_namespaces_with_info() :: [map()]
  def list_namespaces_with_info do
    list_namespaces()
    |> Enum.map(&get_namespace_info/1)
    |> Enum.reject(&is_nil/1)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_definition_module(namespace) do
    Enum.find(@definition_modules, fn module ->
      module.__namespace__() == namespace
    end)
  end

  defp get_stored_value(scope_id, scope_type, namespace, key) do
    case repo().get_value(scope_id, scope_type, to_string(namespace), to_string(key)) do
      nil -> nil
      value_map -> SettingSchema.extract_value(value_map)
    end
  end
end
