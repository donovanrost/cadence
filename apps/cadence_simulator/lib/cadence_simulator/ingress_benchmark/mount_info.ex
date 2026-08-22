defmodule CadenceSimulator.IngressBenchmark.MountInfo do
  @moduledoc false

  @type mount :: %{
          mount_point: binary(),
          filesystem: binary(),
          size_bytes: non_neg_integer() | nil
        }

  @spec parse(binary()) :: [mount()]
  def parse(contents) when is_binary(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_line/1)
  end

  @spec resolve(binary(), [mount()]) :: mount() | nil
  def resolve(path, mounts) when is_binary(path) and is_list(mounts) do
    normalized_path = normalize_path(path)

    mounts
    |> Enum.filter(&path_on_mount?(normalized_path, &1.mount_point))
    |> Enum.max_by(&String.length(&1.mount_point), fn -> nil end)
  end

  defp parse_line(line) do
    with [left, right] <- String.split(line, " - ", parts: 2),
         left_fields when length(left_fields) >= 6 <- String.split(left),
         right_fields when length(right_fields) >= 3 <- String.split(right) do
      mount_point = left_fields |> Enum.at(4) |> unescape_mount_path()
      options = Enum.at(left_fields, 5) <> "," <> Enum.at(right_fields, 2)

      [
        %{
          mount_point: normalize_path(mount_point),
          filesystem: Enum.at(right_fields, 0),
          size_bytes: parse_size_option(options)
        }
      ]
    else
      _invalid -> []
    end
  end

  defp path_on_mount?(_path, "/"), do: true

  defp path_on_mount?(path, mount_point) do
    path == mount_point or String.starts_with?(path, mount_point <> "/")
  end

  defp parse_size_option(options) do
    options
    |> String.split(",", trim: true)
    |> Enum.find_value(fn
      "size=" <> value -> parse_size(value)
      _option -> nil
    end)
  end

  defp parse_size(value) do
    case Regex.run(~r/^(\d+)([kKmMgG])?$/, value) do
      [_, number, unit] -> String.to_integer(number) * size_multiplier(unit)
      [_, number] -> String.to_integer(number)
      _invalid -> nil
    end
  end

  defp size_multiplier(unit) when unit in ["k", "K"], do: 1_024
  defp size_multiplier(unit) when unit in ["m", "M"], do: 1_048_576
  defp size_multiplier(unit) when unit in ["g", "G"], do: 1_073_741_824

  defp normalize_path("/"), do: "/"
  defp normalize_path(path), do: String.trim_trailing(path, "/")

  defp unescape_mount_path(path) do
    path
    |> String.replace("\\040", " ")
    |> String.replace("\\011", "\t")
    |> String.replace("\\012", "\n")
    |> String.replace("\\134", "\\")
  end
end
