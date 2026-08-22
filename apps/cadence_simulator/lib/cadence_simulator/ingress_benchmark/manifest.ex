defmodule CadenceSimulator.IngressBenchmark.Manifest do
  @moduledoc """
  Loaded ingress benchmark manifest with a stable content digest.
  """

  defstruct [:path, :data, :sha256]

  @type t :: %__MODULE__{
          path: binary(),
          data: map(),
          sha256: binary()
        }

  @spec load(binary()) :: {:ok, t()} | {:error, binary()}
  def load(path) when is_binary(path) and path != "" do
    with {:ok, contents} <- File.read(path),
         {:ok, data} <- parse(contents) do
      {:ok,
       %__MODULE__{
         path: Path.expand(path),
         data: data,
         sha256: sha256(contents)
       }}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "failed to load ingress benchmark manifest #{inspect(path)}: #{inspect(reason)}"}
    end
  end

  def load(_path), do: {:error, "manifest path must be a non-empty string"}

  @spec get(t(), [atom()], term()) :: term()
  def get(%__MODULE__{data: data}, path, default \\ nil) when is_list(path) do
    case value_at(data, path) do
      nil -> default
      value -> value
    end
  end

  defp parse(contents) do
    case YamlElixir.read_from_string(contents) do
      {:ok, %{} = data} -> {:ok, data}
      {:ok, _other} -> {:error, "ingress benchmark manifest must be a YAML map"}
      {:error, reason} -> {:error, "invalid ingress benchmark YAML: #{inspect(reason)}"}
    end
  end

  defp value_at(map, path) do
    Enum.reduce_while(path, map, fn key, value ->
      case field(value, key) do
        nil -> {:halt, nil}
        nested -> {:cont, nested}
      end
    end)
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_value, _key), do: nil

  defp sha256(contents) do
    :crypto.hash(:sha256, contents)
    |> Base.encode16(case: :lower)
  end
end
