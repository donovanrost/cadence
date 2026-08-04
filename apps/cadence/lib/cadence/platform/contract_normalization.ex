defmodule Cadence.Platform.ContractNormalization do
  @moduledoc false

  @spec attr(map(), atom(), term()) :: term()
  def attr(attrs, key, default \\ nil) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  @spec known_atom(term(), [atom()]) :: term()
  def known_atom(nil, _known_values), do: nil

  def known_atom(value, known_values) when is_atom(value) do
    if value in known_values, do: value, else: value
  end

  def known_atom(value, known_values) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(known_values, &(Atom.to_string(&1) == normalized)) || value
  end

  def known_atom(value, _known_values), do: value

  @spec existing_atom(term()) :: term()
  def existing_atom(value) when is_atom(value), do: value

  def existing_atom(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    String.to_existing_atom(normalized)
  rescue
    ArgumentError -> value
  end

  def existing_atom(value), do: value

  @spec normalize_context(term(), module()) :: term()
  def normalize_context(nil, module), do: module.from_map(nil)
  def normalize_context(value, module) when is_map(value), do: module.from_map(value)
  def normalize_context(value, _module), do: value

  @spec binary_list(term()) :: term()
  def binary_list(nil), do: []
  def binary_list(values) when is_list(values), do: values
  def binary_list(values), do: values

  @spec atom_list(term()) :: term()
  def atom_list(values) when is_list(values), do: Enum.map(values, &existing_atom/1)
  def atom_list(nil), do: []
  def atom_list(values), do: values

  @spec map_or_default(term()) :: term()
  def map_or_default(nil), do: %{}
  def map_or_default(map) when is_map(map), do: map
  def map_or_default(value), do: value

  @spec optional_map(term()) :: term()
  def optional_map(nil), do: nil
  def optional_map(map) when is_map(map), do: map
  def optional_map(value), do: value

  @spec list_or_default(term()) :: term()
  def list_or_default(nil), do: []
  def list_or_default(values) when is_list(values), do: values
  def list_or_default(values), do: values
end
