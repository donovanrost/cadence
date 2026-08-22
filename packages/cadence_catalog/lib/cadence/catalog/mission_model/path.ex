defmodule Cadence.Catalog.MissionModel.Path do
  @moduledoc "Canonical Mission Model qualified-path handling."

  @spec normalize(binary()) :: binary()
  def normalize(path) when is_binary(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.reject(&(&1 in ["", "."]))

    case segments do
      [] -> "/"
      _segments -> "/" <> Enum.join(segments, "/")
    end
  end

  @spec join(binary(), binary()) :: binary()
  def join(parent, name) when is_binary(parent) and is_binary(name) do
    normalize(normalize(parent) <> "/" <> name)
  end

  @spec parent(binary()) :: binary() | nil
  def parent("/"), do: nil

  def parent(path) when is_binary(path) do
    path
    |> normalize()
    |> String.split("/", trim: true)
    |> Enum.drop(-1)
    |> case do
      [] -> "/"
      segments -> "/" <> Enum.join(segments, "/")
    end
  end

  @spec resolve(binary(), binary()) :: binary()
  def resolve(_owner_path, "/" <> _rest = absolute), do: normalize(absolute)

  def resolve(owner_path, source_ref) when is_binary(owner_path) and is_binary(source_ref) do
    owner_segments = split(parent(normalize(owner_path)) || "/")

    source_ref
    |> String.split("/", trim: true)
    |> Enum.reduce(owner_segments, fn
      ".", acc -> acc
      "..", [] -> []
      "..", acc -> Enum.drop(acc, -1)
      segment, acc -> acc ++ [segment]
    end)
    |> from_segments()
  end

  defp split("/"), do: []
  defp split(path), do: String.split(path, "/", trim: true)

  defp from_segments([]), do: "/"
  defp from_segments(segments), do: "/" <> Enum.join(segments, "/")
end
