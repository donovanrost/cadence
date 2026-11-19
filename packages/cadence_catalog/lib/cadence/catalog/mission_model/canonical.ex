defmodule Cadence.Catalog.MissionModel.Canonical do
  @moduledoc """
  Deterministic identities and content hashes for Mission Model artifacts.

  `sha256/1` and `content_id/2` hash an Erlang term (`term_to_binary([:deterministic])`), which is
  only stable within one OTP release. A hash that is STORED and later recomputed or compared uses
  a versioned basis instead (DECISIONS #108, amended by #112; the API is on #166):
  `basis_sha256/1` and `basis_content_id/2`.

  ## Basis

  A basis is `{shape, version, keys}`: `shape` an atom naming the type, `version` a positive
  integer, `keys` a map of named keys to values. A value is one of:

    * `nil`, `true`, `false`;
    * an integer, or a float (the BEAM has no NaN or infinity, so none can reach the encoder);
    * a UTF-8 binary;
    * any other atom, which hashes AS ITS STRING: `:a` and `"a"` are the same value, and the
      same key. Never rely on the difference; a map holding both `:a` and `"a"` raises;
    * a list of values (order is kept and matters; lists are never sorted);
    * a map with atom or binary keys (pairs are sorted by key; a key may not start with `$`);
    * a nested basis `{shape, version, keys}`.

  Anything else (structs such as `DateTime` or `Decimal`, other tuples, pids, references,
  functions, non-UTF-8 binaries) raises `ArgumentError`; convert it explicitly first.

  ## Encoding

  Canonical JSON (Jason), lowercase hex SHA-256 over
  `[shape_string, version, [[key, value], ...]]` with the pairs sorted by key. Inside it, a nested
  map encodes as a JSON object with its keys sorted, and a nested basis as
  `{"$basis": [shape_string, version, [[key, value], ...]]}`, so a map, a list and a nested basis
  never encode alike.
  """

  @type basis :: {atom(), pos_integer(), map()}

  @spec sha256(term()) :: binary()
  def sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec content_id(binary(), term()) :: binary()
  def content_id(prefix, term) when is_binary(prefix) do
    prefix <> ":" <> sha256(term)
  end

  @doc "Lowercase hex SHA-256 of a versioned basis's canonical JSON. Raises on a disallowed value."
  @spec basis_sha256(basis()) :: binary()
  def basis_sha256(basis) do
    basis
    |> basis_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "`prefix <> \":\" <> basis_sha256(basis)`. Ids carry no version prefix (it's in the hash)."
  @spec basis_content_id(binary(), basis()) :: binary()
  def basis_content_id(prefix, basis) when is_binary(prefix) do
    prefix <> ":" <> basis_sha256(basis)
  end

  @doc false
  @spec basis_json(basis()) :: binary()
  # `escape: :json` is Jason's default today; it is explicit because this encoding is part of
  # stored identities, so no dependency default may be load-bearing (domain, 11-19).
  def basis_json(basis), do: basis |> encode_basis() |> Jason.encode!(escape: :json)

  defp encode_basis({shape, version, keys})
       when is_atom(shape) and shape not in [nil, true, false] and is_integer(version) and
              version > 0 and is_map(keys) and not is_struct(keys) do
    [Atom.to_string(shape), version, Enum.map(sorted_pairs(keys), fn {k, v} -> [k, v] end)]
  end

  defp encode_basis(other),
    do: raise(ArgumentError, "not a {shape, version, keys} basis: #{inspect(other)}")

  defp sorted_pairs(map) do
    pairs = Enum.map(map, fn {key, value} -> {key_string(key), encode_value(value)} end)
    keys = Enum.map(pairs, &elem(&1, 0))

    if length(Enum.uniq(keys)) != length(keys) do
      raise ArgumentError, "basis map has keys that collide as strings: #{inspect(Map.keys(map))}"
    end

    Enum.sort_by(pairs, &elem(&1, 0))
  end

  defp key_string(key) when is_atom(key) and key not in [nil, true, false],
    do: key |> Atom.to_string() |> key_string()

  defp key_string("$" <> _ = key),
    do: raise(ArgumentError, "basis map key may not start with $: #{inspect(key)}")

  defp key_string(key) when is_binary(key), do: utf8!(key)

  defp key_string(key),
    do: raise(ArgumentError, "basis map key must be an atom or a string: #{inspect(key)}")

  defp encode_value(value) when value in [nil, true, false], do: value
  defp encode_value(value) when is_integer(value) or is_float(value), do: value
  defp encode_value(value) when is_binary(value), do: utf8!(value)
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)

  defp encode_value(value) when is_map(value) and not is_struct(value),
    do: value |> sorted_pairs() |> Jason.OrderedObject.new()

  defp encode_value({_shape, _version, _keys} = basis), do: %{"$basis" => encode_basis(basis)}

  defp encode_value(value),
    do: raise(ArgumentError, "value not allowed in a hash basis: #{inspect(value)}")

  defp utf8!(binary) do
    if String.valid?(binary),
      do: binary,
      else: raise(ArgumentError, "basis binaries must be UTF-8: #{inspect(binary)}")
  end

  @spec semantic_id(atom(), binary()) :: binary()
  def semantic_id(kind, qualified_name) when is_atom(kind) and is_binary(qualified_name) do
    "semantic:" <> Atom.to_string(kind) <> ":" <> sha256({kind, qualified_name})
  end
end
