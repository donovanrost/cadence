defmodule Cadence.Domain.Settings.ValueObjects.SettingRestrictiveness do
  @moduledoc """
  Value object representing how mission overrides relate to org values.

  When a setting has `:both` scope, the restrictiveness rule determines
  what values are allowed at the mission level relative to the org default.

  ## Restrictiveness Values

  - `:none` - No restriction, mission can set any valid value
  - `:higher` - Mission value must be >= org value (e.g., more approvals required)
  - `:lower` - Mission value must be <= org value
  - `:false_is_stricter` - false is more restrictive than true (e.g., disabling self-approval)
  """

  @type t :: :none | :higher | :lower | :false_is_stricter

  @values [:none, :higher, :lower, :false_is_stricter]

  @doc """
  Returns all valid restrictiveness values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid restrictiveness.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a restrictiveness value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_restrictiveness}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_restrictiveness}

  @doc """
  Parses a string or atom into a restrictiveness.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_restrictiveness}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "none" -> {:ok, :none}
      "higher" -> {:ok, :higher}
      "lower" -> {:ok, :lower}
      "false_is_stricter" -> {:ok, :false_is_stricter}
      _ -> {:error, :invalid_restrictiveness}
    end
  end

  def parse(_), do: {:error, :invalid_restrictiveness}

  @doc """
  Checks if a mission value is more restrictive than (or equal to) the org value.

  Returns `:ok` if the mission value is valid, or `{:error, details}` with
  information about why the value is invalid.
  """
  @spec check(t(), any(), any()) :: :ok | {:error, map()}
  def check(:none, _org_value, _mission_value), do: :ok

  def check(:higher, org_value, mission_value)
      when is_number(org_value) and is_number(mission_value) do
    if mission_value >= org_value do
      :ok
    else
      {:error, %{org_value: org_value, mission_value: mission_value, min_allowed: org_value}}
    end
  end

  def check(:lower, org_value, mission_value)
      when is_number(org_value) and is_number(mission_value) do
    if mission_value <= org_value do
      :ok
    else
      {:error, %{org_value: org_value, mission_value: mission_value, max_allowed: org_value}}
    end
  end

  def check(:false_is_stricter, org_value, mission_value)
      when is_boolean(org_value) and is_boolean(mission_value) do
    # Mission can set false if org is true, but not true if org is false
    if not mission_value or org_value do
      :ok
    else
      {:error,
       %{
         org_value: org_value,
         mission_value: mission_value,
         reason: "cannot enable when disabled at org level"
       }}
    end
  end

  def check(_restrictiveness, org_value, mission_value) do
    {:error, %{org_value: org_value, mission_value: mission_value, reason: "type mismatch"}}
  end

  @doc """
  Returns true if mission can override the org value.

  For :false_is_stricter, can only override if org is true.
  """
  @spec can_override?(t(), any()) :: boolean()
  def can_override?(:none, _org_value), do: true
  def can_override?(:higher, _org_value), do: true
  def can_override?(:lower, _org_value), do: true
  def can_override?(:false_is_stricter, true), do: true
  def can_override?(:false_is_stricter, false), do: false

  @doc """
  Computes the minimum allowed value for a mission override.
  """
  @spec min_value(t(), any(), any()) :: any() | nil
  def min_value(:higher, org_value, _validation_min) when is_number(org_value), do: org_value
  def min_value(_, _org_value, {:range, min, _max}), do: min
  def min_value(_, _org_value, {:min, min}), do: min
  def min_value(_, _, _), do: nil

  @doc """
  Computes the maximum allowed value for a mission override.
  """
  @spec max_value(t(), any(), any()) :: any() | nil
  def max_value(:lower, org_value, _validation_max) when is_number(org_value), do: org_value
  def max_value(_, _org_value, {:range, _min, max}), do: max
  def max_value(_, _org_value, {:max, max}), do: max
  def max_value(_, _, _), do: nil

  @doc """
  Returns the display name for a restrictiveness.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:none), do: "No Restriction"
  def display_name(:higher), do: "Higher is Stricter"
  def display_name(:lower), do: "Lower is Stricter"
  def display_name(:false_is_stricter), do: "False is Stricter"
end
