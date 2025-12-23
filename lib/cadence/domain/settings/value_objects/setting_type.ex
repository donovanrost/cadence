defmodule Cadence.Domain.Settings.ValueObjects.SettingType do
  @moduledoc """
  Value object representing the data type of a setting value.

  ## Type Values

  - `:integer` - Whole number values
  - `:boolean` - true/false values
  - `:string` - Text values
  """

  @type t :: :integer | :boolean | :string

  @values [:integer, :boolean, :string]

  @doc """
  Returns all valid type values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid type.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a type value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_type}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_type}

  @doc """
  Parses a string or atom into a type.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_type}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "integer" -> {:ok, :integer}
      "boolean" -> {:ok, :boolean}
      "string" -> {:ok, :string}
      _ -> {:error, :invalid_type}
    end
  end

  def parse(_), do: {:error, :invalid_type}

  @doc """
  Checks if a value matches the expected type.
  """
  @spec matches?(t(), any()) :: boolean()
  def matches?(:integer, value), do: is_integer(value)
  def matches?(:boolean, value), do: is_boolean(value)
  def matches?(:string, value), do: is_binary(value)
  def matches?(_, _), do: false

  @doc """
  Validates that a value matches the expected type.
  """
  @spec validate_value(t(), any()) :: :ok | {:error, :type_mismatch}
  def validate_value(type, value) do
    if matches?(type, value) do
      :ok
    else
      {:error, :type_mismatch}
    end
  end

  @doc """
  Returns the display name for a type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:integer), do: "Integer"
  def display_name(:boolean), do: "Boolean"
  def display_name(:string), do: "String"

  @doc """
  Returns the database string representation of the type.
  """
  @spec to_db_string(t()) :: String.t()
  def to_db_string(:integer), do: "integer"
  def to_db_string(:boolean), do: "boolean"
  def to_db_string(:string), do: "string"

  @doc """
  Parses from database string representation.
  """
  @spec from_db_string(String.t()) :: {:ok, t()} | {:error, :invalid_type}
  def from_db_string("integer"), do: {:ok, :integer}
  def from_db_string("boolean"), do: {:ok, :boolean}
  def from_db_string("string"), do: {:ok, :string}
  def from_db_string(_), do: {:error, :invalid_type}
end
