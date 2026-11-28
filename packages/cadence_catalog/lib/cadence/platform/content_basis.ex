defmodule Cadence.Platform.ContentBasis do
  @moduledoc """
  Canonical, versioned bytes for identities that are stored and later recomputed.

  The hashed bytes are `name:vN:` followed by compact JSON. Object keys are UTF-8
  strings sorted by their bytes. Values are nil, booleans, integers, UTF-8 strings,
  lists, and objects; atoms other than booleans and nil have a distinct tagged form.
  Floats have a distinct `$cadence_float` tag with the shortest decimal representation;
  negative zero is encoded as positive zero. Other Erlang terms have no implicit encoding.
  Call `raw_bytes/1` to explicitly
  tag a non-text binary as base64. User object keys beginning with `$` gain a
  second `$`, so they cannot collide with the unescaped scalar tags.
  """

  @name ~r/\A[a-z][a-z0-9_]*\z/

  @spec digest(binary(), pos_integer(), keyword()) :: binary()
  def digest(name, version, fields) do
    prefix = prefix!(name, version)

    hash =
      name
      |> encoded(version, fields)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    prefix <> hash
  end

  @doc "The exact bytes fed to SHA-256; pin these as well as the digest in a golden test."
  @spec encoded(binary(), pos_integer(), keyword()) :: binary()
  def encoded(name, version, fields) do
    prefix = prefix!(name, version)

    unless Keyword.keyword?(fields) do
      raise ArgumentError, "content basis fields must be a keyword list of named values"
    end

    prefix <> encode_object(fields)
  end

  @doc "Explicitly encode a non-UTF-8 binary without confusing it with text."
  @spec raw_bytes(binary()) :: map()
  def raw_bytes(bytes) when is_binary(bytes), do: %{:"$cadence_bytes" => bytes}

  @doc "Select named fields from a struct explicitly; nested structs still need projection."
  @spec project(struct(), [atom()]) :: map()
  def project(%_{} = value, fields) when is_list(fields) do
    available = Map.from_struct(value)

    if Enum.any?(fields, &(not is_atom(&1) or not Map.has_key?(available, &1))) or
         length(Enum.uniq(fields)) != length(fields) do
      raise ArgumentError, "content basis projection has missing or duplicate fields"
    end

    Map.take(available, fields)
  end

  defp prefix!(name, version)
       when is_binary(name) and is_integer(version) and version > 0 do
    if Regex.match?(@name, name) do
      "#{name}:v#{version}:"
    else
      raise ArgumentError, "content basis name must be a lower-case identifier"
    end
  end

  defp prefix!(_name, _version),
    do: raise(ArgumentError, "content basis requires a name and positive integer version")

  defp encode_object(entries) do
    fields =
      Enum.map(entries, fn {key, value} ->
        key = object_key!(key)

        {key, value}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    if fields |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() != length(fields) do
      raise ArgumentError, "duplicate content basis object key"
    end

    inner =
      Enum.map_join(fields, ",", fn {key, value} ->
        Jason.encode!(escape_key(key)) <> ":" <> encode(value)
      end)

    "{" <> inner <> "}"
  end

  defp object_key!(key) when is_atom(key), do: key |> Atom.to_string() |> object_key!()

  defp object_key!(key) when is_binary(key) do
    if String.valid?(key), do: key, else: raise(ArgumentError, "content basis key must be UTF-8")
  end

  defp object_key!(_key), do: raise(ArgumentError, "content basis object keys must be text")

  defp escape_key("$" <> _rest = key), do: "$" <> key
  defp escape_key(key), do: key

  defp encode(nil), do: "null"
  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(value) when is_integer(value), do: Integer.to_string(value)

  defp encode(value) when is_float(value) do
    value = if value == 0.0, do: 0.0, else: value

    "{\"$cadence_float\":" <>
      Jason.encode!(:erlang.float_to_binary(value, [:short])) <> "}"
  end

  defp encode(value) when is_binary(value) do
    if String.valid?(value),
      do: Jason.encode!(value),
      else: raise(ArgumentError, "content basis binary must be UTF-8; use raw_bytes/1")
  end

  defp encode(value) when is_atom(value),
    do: "{\"$cadence_atom\":" <> encode(Atom.to_string(value)) <> "}"

  defp encode(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &encode/1) <> "]"

  defp encode(%{:"$cadence_bytes" => bytes} = value)
       when map_size(value) == 1 and is_binary(bytes),
       do: "{\"$cadence_bytes\":" <> Jason.encode!(Base.encode64(bytes, padding: false)) <> "}"

  defp encode(%{} = value) when not is_struct(value), do: encode_object(Map.to_list(value))

  defp encode(value),
    do: raise(ArgumentError, "unsupported content basis value: #{inspect(value)}")
end
