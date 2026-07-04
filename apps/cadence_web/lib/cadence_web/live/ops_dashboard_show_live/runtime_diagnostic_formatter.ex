defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter do
  @moduledoc false

  def row(label, value), do: %{label: label, value: value(value)}

  def count_summary(counts) when is_map(counts) do
    counts
    |> Enum.reject(fn {_key, count} -> count in [nil, 0] end)
    |> Enum.sort_by(fn {key, _count} -> value(key) end)
    |> Enum.map_join(" ", fn {key, count} -> "#{value(key)}:#{count}" end)
    |> case do
      "" -> nil
      summary -> summary
    end
  end

  def count_summary(_counts), do: nil

  def list(values) when is_list(values) do
    values
    |> Enum.map(&value/1)
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join(" ")
    |> case do
      "" -> "-"
      summary -> summary
    end
  end

  def list(value), do: value(value)

  def value(nil), do: "-"
  def value(""), do: "-"
  def value(value) when is_boolean(value), do: to_string(value)
  def value(value) when is_integer(value), do: Integer.to_string(value)
  def value(value) when is_float(value), do: Float.to_string(value)
  def value(value) when is_atom(value), do: Atom.to_string(value)
  def value(value) when is_binary(value), do: value
  def value(value), do: inspect(value)
end
