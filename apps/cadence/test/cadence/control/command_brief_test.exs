defmodule Cadence.Control.CommandBriefTest do
  @moduledoc "A1: an argument's current value comes only from a 'set' state effect (domain)."
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.ArgumentSpec
  alias Cadence.Catalog.Command.StateEffect
  alias Cadence.Control.CommandBrief

  defp definition(effects),
    do: %{
      argument_specs: [
        %ArgumentSpec{argument_id: "arg:mode", name: "mode"},
        %ArgumentSpec{argument_id: "arg:delay", name: "delay"}
      ],
      state_effects: effects
    }

  test "the set effect's point gives the current value; others have none" do
    effects = [
      %StateEffect{
        effect_id: "e1",
        target_ref: "semantic:parameter:mode",
        operation: "set",
        argument_id: "arg:mode"
      },
      %StateEffect{
        effect_id: "e2",
        target_ref: "semantic:parameter:count",
        operation: "increment",
        argument_id: "arg:delay"
      }
    ]

    current = fn point -> %{point: point, value_json: "1"} end

    assert [
             %{
               name: "mode",
               value_json: "3",
               current: %{point: "semantic:parameter:mode"},
               current_basis: "state_effect"
             },
             %{name: "delay", value_json: "10", current: nil, current_basis: "none"}
           ] = CommandBrief.describe(definition(effects), %{"mode" => 3, "delay" => 10}, current)
  end

  test "64-bit values keep their precision as JSON text" do
    assert [%{value_json: "9007199254740993"} | _] =
             CommandBrief.describe(definition([]), %{"mode" => 9_007_199_254_740_993}, fn _ ->
               nil
             end)
  end
end
