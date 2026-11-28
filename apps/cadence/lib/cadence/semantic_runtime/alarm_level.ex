defmodule Cadence.SemanticRuntime.AlarmLevel do
  @moduledoc """
  The fixed mapping from a monitoring plan's severity to the alarm level (DECISIONS #17, #451 T2).

  Evaluation owns it: the plan keeps the severity names the catalog or the operator declared
  (`watch`, `warning`, `distress`, `critical`, `severe`), and everything downstream (alarm
  episodes, the live alarm table, Fleet, the point conditions) reads the level through this
  module, not through a copy of the table:

  | severity | level |
  |---|---|
  | `watch`, `warning` | `:caution` |
  | `distress`, `critical`, `severe` | `:critical` |
  | `normal` | `:normal` (clears an alarm) |
  | `unknown`, `disabled`, anything else | `:ignore` (changes nothing) |
  """

  @caution [:watch, :warning]
  @critical [:distress, :critical, :severe]

  @type level :: :normal | :caution | :critical | :ignore

  @doc "The alarm level of a severity or effective state, as an atom or its text."
  @spec level(atom() | binary() | nil) :: level()
  def level(:normal), do: :normal
  def level(state) when state in @caution, do: :caution
  def level(state) when state in @critical, do: :critical
  def level(state) when is_binary(state), do: state |> known_atom() |> level_of_atom()
  def level(_state), do: :ignore

  defp level_of_atom(nil), do: :ignore
  defp level_of_atom(atom), do: level(atom)

  # The text of the states the maps name, never `String.to_existing_atom` of stored text.
  defp known_atom("normal"), do: :normal
  defp known_atom("watch"), do: :watch
  defp known_atom("warning"), do: :warning
  defp known_atom("distress"), do: :distress
  defp known_atom("critical"), do: :critical
  defp known_atom("severe"), do: :severe
  defp known_atom(_other), do: nil

  @doc "The severities that raise an alarm, weakest first."
  @spec alarm_states() :: [atom()]
  def alarm_states, do: @caution ++ @critical

  @doc "Whether a severity or effective state raises an alarm (caution or critical)."
  @spec alarming?(atom() | binary() | nil) :: boolean()
  def alarming?(state), do: level(state) in [:caution, :critical]

  @doc "The severities of a level, as text (for SQL `IN` lists over the stored states)."
  @spec states_of(:caution | :critical) :: [binary()]
  def states_of(:caution), do: Enum.map(@caution, &Atom.to_string/1)
  def states_of(:critical), do: Enum.map(@critical, &Atom.to_string/1)

  @doc "A SQL `IN` list literal of the severities of the given levels (compile-time constants only)."
  @spec sql_in([:caution | :critical]) :: binary()
  def sql_in(levels) do
    levels
    |> Enum.flat_map(&states_of/1)
    |> Enum.map_join(", ", &"'#{&1}'")
  end
end
