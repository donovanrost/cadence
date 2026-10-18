defmodule Cadence.Applications.OpsConsole.Actions.FleetPlanningFormDuration do
  @moduledoc "Bounded whole-second duration syntax for fleet policy and grant forms."

  @units %{"d" => 86_400, "h" => 3_600, "m" => 60, "s" => 1}

  @spec parse(term()) :: {:ok, pos_integer()} | :error
  def parse(value) when is_binary(value) and byte_size(value) <= 64 do
    value = String.trim(value)

    if Regex.match?(~r/\A(?:[0-9]+d\s*)?(?:[0-9]+h\s*)?(?:[0-9]+m\s*)?(?:[0-9]+s)?\z/, value) do
      seconds =
        Enum.reduce(Regex.scan(~r/([0-9]+)([dhms])/, value), 0, fn [_, amount, unit], total ->
          total + String.to_integer(amount) * Map.fetch!(@units, unit)
        end)

      if seconds in 1..2_678_400, do: {:ok, seconds}, else: :error
    else
      :error
    end
  end

  def parse(_), do: :error
end
