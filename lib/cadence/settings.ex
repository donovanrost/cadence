defmodule Cadence.Settings do
  @moduledoc """
  Context for managing hierarchical settings.

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
  """

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Repo
  alias Cadence.Settings.Setting
  alias Cadence.Ports.Repository.Settings.SettingsRepository

  # Repository accessor
  defp settings_repo, do: SettingsRepository.impl()

  # Registry of all definition modules
  @definition_modules [
    Cadence.Settings.Definitions.Procedures
  ]

  ## Public API - Getting Settings

  @doc """
  Gets the effective value for a setting in a mission context.

  This considers the org-level default and any mission-level override.
  If no setting is stored at either level, returns the definition default.
  """
  @spec get(Mission.t(), atom(), atom()) :: any()
  def get(%Mission{} = mission, namespace, key) do
    mission = ensure_organization_loaded(mission)
    definition = get_definition(namespace, key)

    if is_nil(definition) do
      nil
    else
      mission_value = get_stored_value(mission.id, "mission", namespace, key)
      org_value = get_stored_value(mission.organization_id, "organization", namespace, key)

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
  @spec all(Mission.t(), atom()) :: map()
  def all(%Mission{} = mission, namespace) do
    definitions = list_definitions(namespace)

    definitions
    |> Enum.map(fn definition ->
      {definition.key, get(mission, namespace, definition.key)}
    end)
    |> Map.new()
  end

  @doc """
  Gets the org-level value for a setting.

  Returns the stored value or the definition default if not stored.
  """
  @spec get_org(Organization.t(), atom(), atom()) :: any()
  def get_org(%Organization{id: org_id}, namespace, key) do
    definition = get_definition(namespace, key)

    if is_nil(definition) do
      nil
    else
      case get_stored_value(org_id, "organization", namespace, key) do
        nil -> definition.default
        value -> value
      end
    end
  end

  @doc """
  Gets the mission-level override for a setting (not the effective value).

  Returns nil if no mission-level override exists.
  """
  @spec get_mission_override(Mission.t(), atom(), atom()) :: any() | nil
  def get_mission_override(%Mission{id: mission_id}, namespace, key) do
    get_stored_value(mission_id, "mission", namespace, key)
  end

  ## Public API - Setting Values

  @doc """
  Sets an org-level setting value.

  Validates the value against the setting definition.
  """
  @spec set_org(Organization.t(), atom(), atom(), any()) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t()} | {:error, :invalid_value}
  def set_org(%Organization{id: org_id}, namespace, key, value) do
    definition = get_definition(namespace, key)

    cond do
      is_nil(definition) ->
        {:error, :unknown_setting}

      definition.scope == :mission_only ->
        {:error, :mission_only_setting}

      not valid_value?(definition, value) ->
        {:error, :invalid_value}

      true ->
        upsert_setting(org_id, "organization", namespace, key, value, definition.type)
    end
  end

  @doc """
  Sets a mission-level override for a setting.

  Validates that the value is more restrictive than the org default.
  """
  @spec set_mission(Mission.t(), atom(), atom(), any()) ::
          {:ok, Setting.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :less_restrictive_than_org, map()}
          | {:error, :org_only_setting}
          | {:error, :invalid_value}
  def set_mission(%Mission{} = mission, namespace, key, value) do
    mission = ensure_organization_loaded(mission)
    definition = get_definition(namespace, key)

    cond do
      is_nil(definition) ->
        {:error, :unknown_setting}

      definition.scope == :org_only ->
        {:error, :org_only_setting}

      not valid_value?(definition, value) ->
        {:error, :invalid_value}

      true ->
        org_value = get_org(mission.organization, namespace, key)

        case check_restrictiveness(definition, org_value, value) do
          :ok ->
            upsert_setting(mission.id, "mission", namespace, key, value, definition.type)

          {:error, reason} ->
            {:error, :less_restrictive_than_org, reason}
        end
    end
  end

  @doc """
  Clears a mission-level override, reverting to the org default.
  """
  @spec clear_mission_override(Mission.t(), atom(), atom()) ::
          {:ok, Setting.t()} | {:error, :not_found}
  def clear_mission_override(%Mission{id: mission_id}, namespace, key) do
    case settings_repo().delete(mission_id, "mission", to_string(namespace), to_string(key)) do
      {:ok, 0} -> {:error, :not_found}
      {:ok, _count} -> :ok
      {:error, _} = error -> error
    end
  end

  ## Public API - Definitions

  @doc """
  Gets a setting definition by namespace and key.
  """
  @spec get_definition(atom(), atom()) :: map() | nil
  def get_definition(namespace, key) do
    case find_definition_module(namespace) do
      nil -> nil
      module -> module.get_definition(key)
    end
  end

  @doc """
  Lists all setting definitions for a namespace.
  """
  @spec list_definitions(atom()) :: [map()]
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

  ## Public API - UI Helpers

  @doc """
  Gets all settings for an organization with their current values and metadata.
  Useful for rendering settings UI.
  """
  @spec get_all_org_settings(Organization.t(), atom()) :: [map()]
  def get_all_org_settings(%Organization{} = org, namespace) do
    list_definitions(namespace)
    |> Enum.filter(fn def -> def.scope in [:both, :org_only] end)
    |> Enum.map(fn definition ->
      %{
        key: definition.key,
        label: definition.label,
        description: definition.description,
        type: definition.type,
        default: definition.default,
        value: get_org(org, namespace, definition.key),
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
  @spec get_all_mission_settings(Mission.t(), atom()) :: [map()]
  def get_all_mission_settings(%Mission{} = mission, namespace) do
    mission = ensure_organization_loaded(mission)

    list_definitions(namespace)
    |> Enum.filter(fn def -> def.scope in [:both, :mission_only] end)
    |> Enum.map(fn definition ->
      org_value = get_org(mission.organization, namespace, definition.key)
      mission_override = get_mission_override(mission, namespace, definition.key)

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
        min_value: compute_min_value(definition, org_value),
        max_value: compute_max_value(definition, org_value),
        can_override: can_override?(definition, org_value)
      }
    end)
  end

  @doc """
  Gets display information for a settings namespace.
  Returns label, description, and icon for UI rendering.
  """
  @spec get_namespace_info(atom()) :: map() | nil
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

  ## Public API - Validation Helpers

  @doc """
  Checks if a mission can set a specific value for a setting.

  Returns `:ok` or `{:error, :less_restrictive_than_org, details}`.
  """
  @spec can_mission_override?(Mission.t(), atom(), atom(), any()) ::
          :ok | {:error, :less_restrictive_than_org, map()} | {:error, :unknown_setting}
  def can_mission_override?(%Mission{} = mission, namespace, key, value) do
    mission = ensure_organization_loaded(mission)
    definition = get_definition(namespace, key)

    if is_nil(definition) do
      {:error, :unknown_setting}
    else
      org_value = get_org(mission.organization, namespace, key)

      case check_restrictiveness(definition, org_value, value) do
        :ok -> :ok
        {:error, reason} -> {:error, :less_restrictive_than_org, reason}
      end
    end
  end

  ## Private Functions

  defp find_definition_module(namespace) do
    Enum.find(@definition_modules, fn module ->
      module.__namespace__() == namespace
    end)
  end

  defp get_stored_value(scope_id, scope_type, namespace, key) do
    case settings_repo().get_value(scope_id, scope_type, to_string(namespace), to_string(key)) do
      nil -> nil
      value_map -> Setting.extract_value(value_map)
    end
  end

  defp upsert_setting(scope_id, scope_type, namespace, key, value, type) do
    attrs = %{
      scope_type: scope_type,
      scope_id: scope_id,
      namespace: to_string(namespace),
      key: to_string(key),
      value: Setting.wrap_value(value, type)
    }

    settings_repo().upsert(attrs)
  end

  defp valid_value?(definition, value) do
    type_valid =
      case definition.type do
        :integer -> is_integer(value)
        :boolean -> is_boolean(value)
        :string -> is_binary(value)
        _ -> false
      end

    alias Cadence.Settings.Definition

    type_valid && Definition.valid?(value, definition.validate)
  end

  defp check_restrictiveness(definition, org_value, mission_value) do
    if more_restrictive?(definition.restrictiveness, org_value, mission_value) do
      :ok
    else
      {:error, build_restrictiveness_error(definition, org_value, mission_value)}
    end
  end

  defp more_restrictive?(restrictiveness, org_value, mission_value) do
    case restrictiveness do
      :none ->
        true

      :higher ->
        mission_value >= org_value

      :lower ->
        mission_value <= org_value

      :false_is_stricter ->
        # false is more restrictive than true
        # mission can set false if org is true, but not true if org is false
        not mission_value or org_value
    end
  end

  defp build_restrictiveness_error(definition, org_value, mission_value) do
    base = %{org_value: org_value, mission_value: mission_value}

    case definition.restrictiveness do
      :higher ->
        Map.put(base, :min_allowed, org_value)

      :lower ->
        Map.put(base, :max_allowed, org_value)

      :false_is_stricter ->
        Map.put(base, :reason, "cannot enable when disabled at org level")

      _ ->
        base
    end
  end

  defp ensure_organization_loaded(%Mission{organization: %Organization{}} = mission) do
    mission
  end

  defp ensure_organization_loaded(%Mission{} = mission) do
    Repo.preload(mission, :organization)
  end

  defp compute_min_value(definition, org_value) do
    case {definition.type, definition.restrictiveness, definition.validate} do
      {:integer, :higher, {:range, _, _}} -> org_value
      {:integer, _, {:range, min, _}} -> min
      _ -> nil
    end
  end

  defp compute_max_value(definition, org_value) do
    case {definition.type, definition.restrictiveness, definition.validate} do
      {:integer, :lower, {:range, _, _}} -> org_value
      {:integer, _, {:range, _, max}} -> max
      _ -> nil
    end
  end

  defp can_override?(definition, org_value) do
    # For false_is_stricter booleans, can only override if org is true
    case {definition.type, definition.restrictiveness} do
      {:boolean, :false_is_stricter} -> org_value == true
      _ -> true
    end
  end
end
