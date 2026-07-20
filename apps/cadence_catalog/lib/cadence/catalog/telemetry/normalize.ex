defmodule Cadence.Catalog.Telemetry.Normalize do
  @moduledoc false

  @spec fetch!(map(), atom()) :: term()
  def fetch!(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get_lazy(attrs, key, fn -> Map.fetch!(attrs, Atom.to_string(key)) end)
  end

  @spec get(map(), atom(), term()) :: term()
  def get(attrs, key, default \\ nil) when is_map(attrs) and is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key), default)
    end
  end

  @spec list(map(), atom()) :: [term()]
  def list(attrs, key) when is_map(attrs) and is_atom(key) do
    case get(attrs, key, []) do
      value when is_list(value) -> value
      _other -> []
    end
  end

  @spec nested(map(), atom(), module()) :: struct() | nil
  def nested(attrs, key, module) when is_map(attrs) and is_atom(key) and is_atom(module) do
    case get(attrs, key) do
      nil -> nil
      value -> as_struct(value, module)
    end
  end

  @spec nested_list(map(), atom(), module()) :: [struct()]
  def nested_list(attrs, key, module)
      when is_map(attrs) and is_atom(key) and is_atom(module) do
    attrs
    |> list(key)
    |> Enum.map(&as_struct(&1, module))
  end

  @spec as_struct(term(), module()) :: struct()
  def as_struct(%{__struct__: module} = value, module), do: value
  def as_struct(value, module) when is_map(value), do: module.new(value)
end
