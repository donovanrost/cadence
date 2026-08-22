defmodule Cadence.Domain.Settings.ValueObjects.SettingScope do
  @moduledoc """
  Value object representing where a setting can be configured.

  ## Scope Values

  - `:org_only` - Setting can only be set at organization level
  - `:mission_only` - Setting can only be set at mission level
  - `:both` - Setting can be set at both levels (mission overrides org)
  """

  @type t :: :org_only | :mission_only | :both

  @values [:org_only, :mission_only, :both]

  @doc """
  Returns all valid scope values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid scope.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a scope value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_scope}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_scope}

  @doc """
  Parses a string or atom into a scope.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_scope}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "org_only" -> {:ok, :org_only}
      "mission_only" -> {:ok, :mission_only}
      "both" -> {:ok, :both}
      _ -> {:error, :invalid_scope}
    end
  end

  def parse(_), do: {:error, :invalid_scope}

  @doc """
  Returns true if the scope allows organization-level settings.
  """
  @spec allows_org?(t()) :: boolean()
  def allows_org?(:org_only), do: true
  def allows_org?(:both), do: true
  def allows_org?(_), do: false

  @doc """
  Returns true if the scope allows mission-level settings.
  """
  @spec allows_mission?(t()) :: boolean()
  def allows_mission?(:mission_only), do: true
  def allows_mission?(:both), do: true
  def allows_mission?(_), do: false

  @doc """
  Returns the display name for a scope.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:org_only), do: "Organization Only"
  def display_name(:mission_only), do: "Mission Only"
  def display_name(:both), do: "Both Levels"
end
