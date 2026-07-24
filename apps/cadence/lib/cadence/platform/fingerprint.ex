defmodule Cadence.Platform.Fingerprint do
  @moduledoc "Plane-neutral stable fingerprints for cache and projection identities."

  @spec url_sha256(term()) :: binary()
  def url_sha256(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  @spec canonical_url_sha256(term()) :: binary()
  def canonical_url_sha256(value) do
    value
    |> canonicalize()
    |> url_sha256()
  end

  defp canonicalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp canonicalize(%_{} = value) do
    value
    |> Map.from_struct()
    |> canonicalize()
  end

  defp canonicalize(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {canonicalize_key(key), canonicalize(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonicalize(list) when is_list(list) do
    if Keyword.keyword?(list) do
      list
      |> Enum.map(fn {key, value} -> {canonicalize_key(key), canonicalize(value)} end)
      |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
    else
      Enum.map(list, &canonicalize/1)
    end
  end

  defp canonicalize(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&canonicalize/1)
    |> List.to_tuple()
  end

  defp canonicalize(value), do: value

  defp canonicalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp canonicalize_key(key), do: key
end
