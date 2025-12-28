defmodule Cadence.Application.Settings.SettingOperations do
  @moduledoc """
  Use case module for setting write operations.

  Provides operations for setting and clearing configuration values at
  the organization and mission levels. Handles validation of values against
  setting definitions and enforces restrictiveness rules for mission overrides.

  ## Usage

      # Set org-level setting
      {:ok, setting} = SettingOperations.set_org(org_id, :procedures, :required_approvals, 2)

      # Set mission-level override (validates restrictiveness)
      {:ok, setting} = SettingOperations.set_mission(mission_id, org_id, :procedures, :required_approvals, 3)

      # Clear mission override
      :ok = SettingOperations.clear_mission_override(mission_id, :procedures, :required_approvals)
  """

  alias Cadence.Application.Settings.SettingQueries
  alias Cadence.Domain.Settings.Entities.Setting
  alias Cadence.Domain.Settings.ValueObjects.SettingRestrictiveness
  alias Cadence.Ports.Repository.Settings.SettingsRepository

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
  Sets an org-level setting value.

  Validates the value against the setting definition. Returns an error if:
  - The setting is not defined
  - The setting is mission-only
  - The value doesn't match the expected type
  - The value fails validation rules

  ## Examples

      {:ok, setting} = SettingOperations.set_org(org_id, :procedures, :required_approvals, 2)
  """
  @spec set_org(org_id(), namespace(), key(), any()) ::
          {:ok, Setting.t()} | {:error, term()}
  def set_org(org_id, namespace, key, value) do
    with {:ok, definition} <- get_definition(namespace, key),
         :ok <- validate_org_scope(definition),
         :ok <- validate_value(definition, value) do
      upsert_setting(:organization, org_id, namespace, key, value, definition.type)
    end
  end

  @doc """
  Sets a mission-level override for a setting.

  Validates that the value is more restrictive than the org default.
  Returns an error if:
  - The setting is not defined
  - The setting is org-only
  - The value doesn't match the expected type
  - The value fails validation rules
  - The value is less restrictive than the org default

  ## Examples

      {:ok, setting} = SettingOperations.set_mission(mission_id, org_id, :procedures, :required_approvals, 3)
  """
  @spec set_mission(mission_id(), org_id(), namespace(), key(), any()) ::
          {:ok, Setting.t()}
          | {:error, :less_restrictive_than_org, map()}
          | {:error, term()}
  def set_mission(mission_id, org_id, namespace, key, value) do
    with {:ok, definition} <- get_definition(namespace, key),
         :ok <- validate_mission_scope(definition),
         :ok <- validate_value(definition, value),
         org_value <- get_org_value(org_id, namespace, key, definition),
         :ok <- check_restrictiveness(definition, org_value, value) do
      upsert_setting(:mission, mission_id, namespace, key, value, definition.type)
    end
  end

  @doc """
  Clears a mission-level override, reverting to the org default.

  ## Examples

      :ok = SettingOperations.clear_mission_override(mission_id, :procedures, :required_approvals)
  """
  @spec clear_mission_override(mission_id(), namespace(), key()) ::
          :ok | {:error, :not_found} | {:error, term()}
  def clear_mission_override(mission_id, namespace, key) do
    case repo().delete(mission_id, "mission", to_string(namespace), to_string(key)) do
      {:ok, 0} -> {:error, :not_found}
      {:ok, _count} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Checks if a mission can set a specific value for a setting.

  Validates against restrictiveness rules without actually saving.
  """
  @spec can_set_mission_value?(mission_id(), org_id(), namespace(), key(), any()) ::
          :ok | {:error, :less_restrictive_than_org, map()} | {:error, term()}
  def can_set_mission_value?(_mission_id, org_id, namespace, key, value) do
    with {:ok, definition} <- get_definition(namespace, key),
         :ok <- validate_mission_scope(definition),
         :ok <- validate_value(definition, value),
         org_value <- get_org_value(org_id, namespace, key, definition) do
      check_restrictiveness(definition, org_value, value)
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_definition(namespace, key) do
    case find_definition_module(namespace) do
      nil ->
        {:error, :unknown_setting}

      module ->
        case module.get_definition(key) do
          nil -> {:error, :unknown_setting}
          definition -> {:ok, definition}
        end
    end
  end

  defp find_definition_module(namespace) do
    Enum.find(@definition_modules, fn module ->
      module.__namespace__() == namespace
    end)
  end

  defp validate_org_scope(definition) do
    if definition.scope == :mission_only do
      {:error, :mission_only_setting}
    else
      :ok
    end
  end

  defp validate_mission_scope(definition) do
    if definition.scope == :org_only do
      {:error, :org_only_setting}
    else
      :ok
    end
  end

  defp validate_value(definition, value) do
    type_valid =
      case definition.type do
        :integer -> is_integer(value)
        :boolean -> is_boolean(value)
        :string -> is_binary(value)
        _ -> false
      end

    if type_valid do
      validate_rule(value, definition.validate)
    else
      {:error, :invalid_value}
    end
  end

  defp validate_rule(_value, nil), do: :ok
  defp validate_rule(_value, :any), do: :ok

  defp validate_rule(value, {:range, min, max}) when is_number(value) do
    if value >= min and value <= max, do: :ok, else: {:error, :invalid_value}
  end

  defp validate_rule(value, {:min, min}) when is_number(value) do
    if value >= min, do: :ok, else: {:error, :invalid_value}
  end

  defp validate_rule(value, {:max, max}) when is_number(value) do
    if value <= max, do: :ok, else: {:error, :invalid_value}
  end

  defp validate_rule(value, {:one_of, list}) do
    if value in list, do: :ok, else: {:error, :invalid_value}
  end

  defp validate_rule(_value, _rule), do: {:error, :invalid_value}

  defp get_org_value(org_id, namespace, key, definition) do
    case SettingQueries.get_org_value(org_id, namespace, key) do
      nil -> definition.default
      value -> value
    end
  end

  defp check_restrictiveness(definition, org_value, mission_value) do
    case SettingRestrictiveness.check(definition.restrictiveness, org_value, mission_value) do
      :ok -> :ok
      {:error, details} -> {:error, :less_restrictive_than_org, details}
    end
  end

  defp upsert_setting(scope_type, scope_id, namespace, key, value, value_type) do
    attrs = %{
      scope_type: scope_type,
      scope_id: scope_id,
      namespace: namespace,
      key: key,
      value: value,
      value_type: value_type
    }

    with {:ok, setting} <- Setting.new(attrs) do
      repo().upsert(Setting.to_storage(setting))
      |> case do
        {:ok, schema} -> Setting.from_storage(schema_to_map(schema))
        {:error, _} = error -> error
      end
    end
  end

  # Convert Ecto schema to map for domain entity creation
  defp schema_to_map(%{__struct__: _} = schema) do
    %{
      id: schema.id,
      scope_type: schema.scope_type,
      scope_id: schema.scope_id,
      namespace: schema.namespace,
      key: schema.key,
      value: schema.value,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end
end
