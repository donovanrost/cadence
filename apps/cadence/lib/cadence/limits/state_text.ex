defmodule Cadence.Limits.StateText do
  @moduledoc """
  The limit states as stored (text) and as the domain has them (atoms), through closed maps (#1025).

  A stored state was turned into an atom with `String.to_existing_atom`, which depends on the module
  that names the atom having been loaded: a dev node that had not loaded the evaluator raised on a
  `yellow_high` row and Fleet and Counts answered 500. The maps below are written here, so the atoms
  exist whenever this module is loaded, and an unknown stored value is decoded as `:unknown` and
  logged, never raised: a read path must not fall over on a value written by a newer or older
  version.

  The vocabularies are the threshold evaluation's (`SemanticRuntime.ThresholdLimits`): `limit_state` is the
  threshold crossed (`green`, `blue`, `yellow_low`, `yellow_high`, `red_low`, `red_high`),
  `normalized_state` its colour (`green`, `blue`, `yellow`, `red`).
  """

  require Logger

  @limit_states %{
    "green" => :green,
    "blue" => :blue,
    "yellow_low" => :yellow_low,
    "yellow_high" => :yellow_high,
    "red_low" => :red_low,
    "red_high" => :red_high
  }
  @normalized_states %{"green" => :green, "blue" => :blue, "yellow" => :yellow, "red" => :red}

  @type limit_state ::
          :green | :blue | :yellow_low | :yellow_high | :red_low | :red_high | :unknown
  @type normalized_state :: :green | :blue | :yellow | :red | :unknown

  @doc "The limit states a writer can store."
  @spec limit_states() :: [limit_state()]
  def limit_states, do: Map.values(@limit_states)

  @doc "The normalized states a writer can store."
  @spec normalized_states() :: [normalized_state()]
  def normalized_states, do: Map.values(@normalized_states)

  @spec limit_state(binary()) :: limit_state()
  def limit_state(text), do: decode(@limit_states, :limit_state, text)

  @spec normalized_state(binary()) :: normalized_state()
  def normalized_state(text), do: decode(@normalized_states, :normalized_state, text)

  defp decode(map, field, text) do
    case Map.fetch(map, text) do
      {:ok, atom} ->
        atom

      :error ->
        Logger.warning(
          "unknown stored #{field} #{inspect(String.slice(to_string(text), 0, 64))}, read as :unknown"
        )

        :unknown
    end
  end
end
