defmodule Cadence.Configuration.Document do
  @moduledoc """
  Canonical configuration documents: JSON-safe maps with string keys, addressed by dotted paths
  (`"frame_parameters.frame_size"`). Lists and scalars are leaves; only maps nest.
  """

  alias Cadence.Persistence.JsonDocument

  @type t :: %{optional(String.t()) => term()}
  @type change :: %{path: String.t(), before: term(), after: term()}

  @doc "Normalizes a term to its JSON-safe canonical form."
  @spec normalize(term()) :: term()
  def normalize(nil), do: nil
  def normalize(value), do: JsonDocument.encode(value)

  @spec get(t() | nil, String.t()) :: term()
  def get(nil, _path), do: nil

  def get(document, path) do
    Enum.reduce_while(split(path), document, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  @doc "Sets `path` to `value`, creating intermediate maps."
  @spec put(t(), String.t(), term()) :: t()
  def put(document, path, value), do: put_keys(document || %{}, split(path), normalize(value))

  @doc ~s(Applies `[%{"path" => p, "value" => v}]` to a document.)
  @spec patch(t(), [map()]) :: t()
  def patch(document, changes) do
    Enum.reduce(changes, document, fn %{"path" => path, "value" => value}, acc ->
      put(acc, path, value)
    end)
  end

  @doc "Flattens a document to `%{path => leaf}`."
  @spec flatten(t() | nil) :: %{String.t() => term()}
  def flatten(nil), do: %{}
  def flatten(document) when is_map(document), do: flatten(document, nil, %{})

  @doc "Field-level difference between two documents, sorted by path."
  @spec diff(t() | nil, t() | nil) :: [change()]
  def diff(previous, proposed) do
    before_paths = flatten(previous)
    after_paths = flatten(proposed)

    before_paths
    |> Map.keys()
    |> Enum.concat(Map.keys(after_paths))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      old = Map.get(before_paths, path)
      new = Map.get(after_paths, path)
      if old == new, do: [], else: [%{path: path, before: old, after: new}]
    end)
  end

  @doc "Paths that differ between two documents."
  @spec changed_paths(t() | nil, t() | nil) :: [String.t()]
  def changed_paths(previous, proposed), do: Enum.map(diff(previous, proposed), & &1.path)

  @doc "Stable content hash of any JSON-safe term."
  @spec sha256(term()) :: String.t()
  def sha256(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(canonical(normalize(term))))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map),
    do: map |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> {k, canonical(v)} end)

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value

  defp flatten(map, prefix, acc) when map_size(map) == 0 and not is_nil(prefix),
    do: Map.put(acc, prefix, %{})

  defp flatten(map, prefix, acc) do
    Enum.reduce(map, acc, fn {key, value}, inner ->
      path = if prefix, do: prefix <> "." <> key, else: key

      case value do
        %{} -> flatten(value, path, inner)
        _ -> Map.put(inner, path, value)
      end
    end)
  end

  defp put_keys(map, [key], value), do: Map.put(map, key, value)

  defp put_keys(map, [key | rest], value) do
    child =
      case Map.get(map, key) do
        %{} = existing -> existing
        _ -> %{}
      end

    Map.put(map, key, put_keys(child, rest, value))
  end

  defp split(path), do: String.split(path, ".")
end
