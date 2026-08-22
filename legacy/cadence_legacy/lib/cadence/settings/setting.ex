defmodule Cadence.Settings.Setting do
  @moduledoc """
  Schema for stored settings.

  Settings are stored with a flexible structure that allows org-level defaults
  and mission-level overrides. The actual setting definitions (types, defaults,
  validation) are defined in code via `Cadence.Settings.Definition`.

  ## Scoping

  - `scope_type: "organization"` - Setting applies to all missions in the org
  - `scope_type: "mission"` - Setting overrides the org default for a specific mission

  ## Value Storage

  Values are stored as maps with type information:

      %{"type" => "integer", "value" => 2}
      %{"type" => "boolean", "value" => true}
      %{"type" => "string", "value" => "some text"}
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @scope_types ["organization", "mission"]
  @value_types ["integer", "boolean", "string"]

  schema "settings" do
    field :scope_type, :string
    field :scope_id, :binary_id
    field :namespace, :string
    field :key, :string
    field :value, :map

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a setting.
  """
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:scope_type, :scope_id, :namespace, :key, :value])
    |> validate_required([:scope_type, :scope_id, :namespace, :key, :value])
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_value_structure()
    |> unique_constraint([:scope_type, :scope_id, :namespace, :key],
      name: :settings_scope_type_scope_id_namespace_key_index,
      message: "setting already exists for this scope"
    )
  end

  @doc """
  Extracts the actual value from the stored value map.
  """
  @spec extract_value(map()) :: any()
  def extract_value(%{"value" => value}), do: value
  def extract_value(_), do: nil

  @doc """
  Wraps a value in the storage format with type information.
  """
  @spec wrap_value(any(), atom()) :: map()
  def wrap_value(value, type) do
    %{"type" => to_string(type), "value" => value}
  end

  @doc """
  Returns the list of valid scope types.
  """
  def valid_scope_types, do: @scope_types

  # Private functions

  defp validate_value_structure(changeset) do
    case get_change(changeset, :value) do
      nil ->
        changeset

      value when is_map(value) ->
        cond do
          not Map.has_key?(value, "type") ->
            add_error(changeset, :value, "must have a 'type' key")

          not Map.has_key?(value, "value") ->
            add_error(changeset, :value, "must have a 'value' key")

          value["type"] not in @value_types ->
            add_error(changeset, :value, "type must be one of: #{Enum.join(@value_types, ", ")}")

          true ->
            changeset
        end

      _ ->
        add_error(changeset, :value, "must be a map")
    end
  end
end
