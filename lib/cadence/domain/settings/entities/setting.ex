defmodule Cadence.Domain.Settings.Entities.Setting do
  @moduledoc """
  Pure domain entity representing a stored setting value.

  Settings are configuration values that can be set at the organization level
  (as defaults) or at the mission level (as overrides). This entity represents
  a persisted setting value, separate from the setting definition metadata.

  ## Scoping

  - `scope_type: :organization` - Setting applies to all missions in the org
  - `scope_type: :mission` - Setting overrides the org default for a specific mission

  ## Usage

      # Create a new setting
      {:ok, setting} = Setting.new(%{
        scope_type: :organization,
        scope_id: org_id,
        namespace: :procedures,
        key: :required_approvals,
        value: 2,
        value_type: :integer
      })

      # Update the value
      {:ok, setting} = Setting.update_value(setting, 3)
  """

  alias Cadence.Domain.Settings.ValueObjects.SettingType
  alias Cadence.Time, as: CadenceTime

  @type scope_type :: :organization | :mission

  @type t :: %__MODULE__{
          id: String.t() | nil,
          scope_type: scope_type(),
          scope_id: String.t(),
          namespace: atom(),
          key: atom(),
          value: any(),
          value_type: SettingType.t(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :scope_type,
    :scope_id,
    :namespace,
    :key,
    :value,
    :value_type,
    :created_at,
    :updated_at
  ]

  @valid_scope_types [:organization, :mission]

  @doc """
  Creates a new Setting entity.

  ## Required Fields

  - `:scope_type` - :organization or :mission
  - `:scope_id` - The org or mission ID
  - `:namespace` - Setting namespace (e.g., :procedures)
  - `:key` - Setting key (e.g., :required_approvals)
  - `:value` - The setting value
  - `:value_type` - The value type (:integer, :boolean, :string)

  ## Optional Fields

  - `:id` - Pre-assigned ID
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <-
           validate_required(attrs, [
             :scope_type,
             :scope_id,
             :namespace,
             :key,
             :value,
             :value_type
           ]),
         {:ok, scope_type} <- parse_scope_type(attrs[:scope_type]),
         {:ok, value_type} <- parse_value_type(attrs[:value_type]),
         :ok <- SettingType.validate_value(value_type, attrs[:value]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         scope_type: scope_type,
         scope_id: attrs[:scope_id],
         namespace: normalize_atom(attrs[:namespace]),
         key: normalize_atom(attrs[:key]),
         value: attrs[:value],
         value_type: value_type,
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates the value of a setting.

  Validates that the new value matches the setting's type.
  """
  @spec update_value(t(), any()) :: {:ok, t()} | {:error, term()}
  def update_value(%__MODULE__{value_type: value_type} = setting, new_value) do
    with :ok <- SettingType.validate_value(value_type, new_value) do
      {:ok, %{setting | value: new_value, updated_at: CadenceTime.now()}}
    end
  end

  @doc """
  Creates a setting from database storage format.

  The database stores values as maps with type info:
  `%{"type" => "integer", "value" => 2}`
  """
  @spec from_storage(map()) :: {:ok, t()} | {:error, term()}
  def from_storage(attrs) when is_map(attrs) do
    value_map = attrs[:value] || attrs["value"]

    with {:ok, extracted_value, value_type} <- extract_stored_value(value_map) do
      new(%{
        id: attrs[:id] || attrs["id"],
        scope_type: attrs[:scope_type] || attrs["scope_type"],
        scope_id: attrs[:scope_id] || attrs["scope_id"],
        namespace: attrs[:namespace] || attrs["namespace"],
        key: attrs[:key] || attrs["key"],
        value: extracted_value,
        value_type: value_type,
        created_at: attrs[:created_at] || attrs["created_at"],
        updated_at: attrs[:updated_at] || attrs["updated_at"]
      })
    end
  end

  @doc """
  Converts the setting to database storage format.

  Returns a map suitable for persistence with the value wrapped
  in the storage format: `%{"type" => "integer", "value" => 2}`
  """
  @spec to_storage(t()) :: map()
  def to_storage(%__MODULE__{} = setting) do
    %{
      id: setting.id,
      scope_type: to_string(setting.scope_type),
      scope_id: setting.scope_id,
      namespace: to_string(setting.namespace),
      key: to_string(setting.key),
      value: wrap_value(setting.value, setting.value_type),
      created_at: setting.created_at,
      updated_at: setting.updated_at
    }
  end

  @doc """
  Returns true if this is an organization-level setting.
  """
  @spec org_setting?(t()) :: boolean()
  def org_setting?(%__MODULE__{scope_type: :organization}), do: true
  def org_setting?(_), do: false

  @doc """
  Returns true if this is a mission-level setting (override).
  """
  @spec mission_setting?(t()) :: boolean()
  def mission_setting?(%__MODULE__{scope_type: :mission}), do: true
  def mission_setting?(_), do: false

  @doc """
  Returns a composite key for uniqueness checking.
  """
  @spec composite_key(t()) :: {scope_type(), String.t(), atom(), atom()}
  def composite_key(%__MODULE__{} = setting) do
    {setting.scope_type, setting.scope_id, setting.namespace, setting.key}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, fields) do
    missing = Enum.filter(fields, fn field -> is_nil(attrs[field]) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp parse_scope_type(scope_type) when scope_type in @valid_scope_types, do: {:ok, scope_type}

  defp parse_scope_type(scope_type) when is_binary(scope_type) do
    case scope_type do
      "organization" -> {:ok, :organization}
      "mission" -> {:ok, :mission}
      _ -> {:error, :invalid_scope_type}
    end
  end

  defp parse_scope_type(_), do: {:error, :invalid_scope_type}

  defp parse_value_type(type), do: SettingType.parse(type)

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_atom(value)

  defp extract_stored_value(%{"type" => type_str, "value" => value}) do
    case SettingType.from_db_string(type_str) do
      {:ok, value_type} -> {:ok, value, value_type}
      {:error, _} = error -> error
    end
  end

  defp extract_stored_value(_), do: {:error, :invalid_value_format}

  defp wrap_value(value, value_type) do
    %{"type" => SettingType.to_db_string(value_type), "value" => value}
  end
end
