defmodule Cadence.Platform.ConfigFields do
  @moduledoc """
  Small field checks for `Cadence.Platform.ConfigKind` documents. Each check returns a list of
  `%{path, message}` errors (empty when valid), so a kind can concatenate them.
  """

  @type errors :: [%{path: String.t(), message: String.t()}]

  @spec text(map(), String.t(), Range.t(), keyword()) :: errors()
  def text(document, key, range, opts \\ []) do
    label = Keyword.get(opts, :label, "This field")

    case Map.get(document, key) do
      nil ->
        if Keyword.get(opts, :required, false), do: [error(key, "#{label} is required")], else: []

      value when is_binary(value) ->
        length = value |> String.trim() |> String.length()

        if String.valid?(value) and length >= max(range.first, 1) and length <= range.last,
          do: [],
          else: [error(key, "#{label} must be #{max(range.first, 1)}–#{range.last} characters")]

      _other ->
        [error(key, "#{label} must be text")]
    end
  end

  @spec integer(map(), String.t(), Range.t(), keyword()) :: errors()
  def integer(document, key, range, opts \\ []) do
    label = Keyword.get(opts, :label, "This field")

    case Map.get(document, key) do
      nil ->
        if Keyword.get(opts, :required, false), do: [error(key, "#{label} is required")], else: []

      value when is_integer(value) ->
        if value in range,
          do: [],
          else: [error(key, "#{label} must be #{range.first}–#{range.last}")]

      _other ->
        [error(key, "#{label} must be a whole number")]
    end
  end

  @spec one_of(map(), String.t(), [term()], keyword()) :: errors()
  def one_of(document, key, allowed, opts \\ []) do
    label = Keyword.get(opts, :label, "This field")

    case Map.get(document, key) do
      nil ->
        if Keyword.get(opts, :required, false), do: [error(key, "#{label} is required")], else: []

      value ->
        if value in allowed,
          do: [],
          else: [
            error(key, "#{label} must be one of #{Enum.map_join(allowed, ", ", &to_string/1)}")
          ]
    end
  end

  @spec map(map(), String.t()) :: errors()
  def map(document, key) do
    case Map.get(document, key) do
      nil -> []
      %{} -> []
      _other -> [error(key, "Must be an object")]
    end
  end

  @doc "Errors for keys outside `allowed`."
  @spec only(map(), [String.t()]) :: errors()
  def only(document, allowed) do
    for key <- Map.keys(document), key not in allowed, do: error(key, "Unknown field")
  end

  @spec result(map() | nil, errors()) :: {:ok, map() | nil} | {:error, errors()}
  def result(document, []), do: {:ok, document}
  def result(_document, errors), do: {:error, errors}

  @spec error(String.t(), String.t()) :: %{path: String.t(), message: String.t()}
  def error(path, message), do: %{path: path, message: message}
end
