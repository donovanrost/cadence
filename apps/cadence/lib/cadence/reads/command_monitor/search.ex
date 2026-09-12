defmodule Cadence.Reads.CommandMonitor.Search do
  @moduledoc false

  # The existing monitor uses String.downcase/1, whose Unicode mapping is
  # unconditional. Database lower/1 depends on the deployment's locale. Derive
  # translation parameters from the same Elixir Unicode implementation instead.
  @mappings for codepoint <- 1..0x10FFFF,
                codepoint not in 0xD800..0xDFFF,
                original = <<codepoint::utf8>>,
                mapped = String.downcase(original),
                original != mapped,
                do: {original, mapped}
  @single Enum.filter(@mappings, fn {_, mapped} -> length(String.codepoints(mapped)) == 1 end)
  @multiple @mappings -- @single
  @parameters [
                Enum.map_join(@single, &elem(&1, 0)),
                Enum.map_join(@single, &elem(&1, 1))
              ] ++ Enum.flat_map(@multiple, fn {original, mapped} -> [original, mapped] end)

  def parameters, do: @parameters

  # Only internal SQL expressions enter here. Values, including the mapping,
  # are bound parameters. Positions 1 through 7 belong to the scoped page query.
  def expression(sql, start \\ 8) do
    @multiple
    |> Enum.with_index()
    |> Enum.reduce("translate(#{sql}, $#{start}::text, $#{start + 1}::text)", fn {_, index},
                                                                                 expression ->
      position = start + 2 + index * 2
      "replace(#{expression}, $#{position}::text, $#{position + 1}::text)"
    end)
  end
end
