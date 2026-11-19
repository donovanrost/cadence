defmodule Cadence.Comms.StationCode do
  @moduledoc """
  A suggested short code for a ground station that has none (U25).

  Codes are display only, so Cadence never stores one it invented: a station without a
  confirmed code reads `code: nil` with a `suggested_code` the UI can offer for confirmation.
  The suggestion is the first three letters of the name, upper-cased, de-duplicated against the
  mission's confirmed codes with a numeric suffix (`"SVA"`, then `"SVA2"`). Identity uses
  (routing rules, Gantt rows, the palette) never use a suggestion; they show the name.
  """

  @doc "The suggestion for `name` given the mission's confirmed codes; nil when the name has no letters."
  @spec suggest(String.t() | nil, Enumerable.t()) :: String.t() | nil
  def suggest(name, taken) when is_binary(name) do
    taken = MapSet.new(taken)

    case name |> String.replace(~r/[^A-Za-z]/, "") |> String.slice(0, 3) |> String.upcase() do
      "" ->
        nil

      stem ->
        Enum.find([stem | Enum.map(2..99, &"#{stem}#{&1}")], &(not MapSet.member?(taken, &1)))
    end
  end

  def suggest(_name, _taken), do: nil
end
