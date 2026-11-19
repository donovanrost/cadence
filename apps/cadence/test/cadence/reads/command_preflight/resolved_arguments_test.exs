defmodule Cadence.Reads.CommandPreflight.ResolvedArgumentsTest do
  @moduledoc "U68 R1: where the server's argument values differ from what was entered."
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Catalog.Command.Compiler.ArgumentSpec
  alias Cadence.Catalog.Command.TypeEncoding
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.{CommandGroups, CommandPreflight}
  alias Cadence.Reads.CommandPreflight.ResolvedArguments

  describe "one member's differences" do
    test "a blank argument takes the default or fixed value; an entered one is not a row" do
      definition =
        definition([
          spec("amount", :integer),
          spec("counter", :integer, default_value: 7),
          spec("mode", :integer, fixed_value: 2)
        ])

      rows =
        ResolvedArguments.differences(
          request(%{"amount" => 1}, %{"amount" => 1, "counter" => 7, "mode" => 2}),
          definition
        )

      assert [
               %{name: "counter", entered_value_json: nil, resolved_value_json: "7"} = counter,
               %{name: "mode", entered_value_json: nil, resolved_value_json: "2"} = mode
             ] = rows

      assert counter.source == "default"
      assert mode.source == "fixed"
      assert counter.sent_value_json == nil
      assert counter.unit == "s"
    end

    test "a 32-bit IEEE float says what it radiates when that differs, and only then" do
      definition = definition([spec("volts", :float, float32: true)])

      assert [
               %{
                 name: "volts",
                 source: "entered",
                 entered_value_json: "0.1",
                 resolved_value_json: "0.1",
                 sent_value_json: sent
               }
             ] =
               ResolvedArguments.differences(
                 request(%{"volts" => 0.1}, %{"volts" => 0.1}),
                 definition
               )

      assert sent == Jason.encode!(0.10000000149011612)

      assert [] ==
               ResolvedArguments.differences(
                 request(%{"volts" => 2.5}, %{"volts" => 2.5}),
                 definition
               )
    end

    test "a 64-bit float, or the same value, is not a row" do
      definition = definition([spec("volts", :float)])

      assert [] ==
               ResolvedArguments.differences(
                 request(%{"volts" => 0.1}, %{"volts" => 0.1}),
                 definition
               )
    end

    test "without the pinned definition, a filled value still shows, as source catalog" do
      assert [%{name: "counter", source: "catalog", unit: nil}] =
               ResolvedArguments.differences(request(%{}, %{"counter" => 7}), nil)
    end
  end

  describe "preflight and the group read" do
    setup do
      c = setup!(2)
      [one, two] = c.spacecraft

      # Every target leaves counter blank (default) except the second, which enters it.
      command =
        c
        |> command("SET_COUNTER", %{"amount" => 1})
        |> Map.put(:per_target, %{two => %{"amount" => 1, "counter" => 5}})

      draft = draft(c.spacecraft, [command], %{log_entry: "Counter reset"})
      Map.merge(c, %{one: one, draft: draft})
    end

    test "name the targets a default applied to, in Arm and in Approve", c do
      assert {:ok, preflight} = CommandPreflight.run(c.org, c.mission, actor(c), c.draft)
      assert [%{position: 0, resolved_arguments: rows}] = preflight.commands
      assert [%{name: "counter", source: "default", spacecraft_ids: [one]} = row] = rows
      assert one == c.one
      assert row.entered_value_json == nil

      assert {:ok, group} =
               GroupSubmission.submit(c.scope, c.mission, c.draft,
                 preflight_digest: digest(c, c.draft)
               )

      assert {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)
      assert %{0 => ^rows} = view.resolved_arguments
    end

    test "a default every target used names no targets", c do
      draft = %{c.draft | commands: [command(c, "SET_COUNTER", %{"amount" => 1})]}

      assert {:ok, preflight} = CommandPreflight.run(c.org, c.mission, actor(c), draft)

      assert [%{resolved_arguments: [%{name: "counter", spacecraft_ids: nil}]}] =
               preflight.commands
    end
  end

  defp definition(specs),
    do: %{
      specs: specs,
      units: Map.new(specs, &{&1.argument_id, if(&1.name == "counter", do: "s")})
    }

  defp spec(name, type, opts \\ []) do
    encoding =
      if opts[:float32],
        do: %TypeEncoding{size_bits: 32, float_encoding: :ieee754},
        else: %TypeEncoding{size_bits: 64, float_encoding: :ieee754}

    %ArgumentSpec{
      argument_id: "arg-" <> name,
      name: name,
      base_type: type,
      required: false,
      encoding: encoding,
      default_value: opts[:default_value],
      fixed_value: opts[:fixed_value],
      metadata: %{}
    }
  end

  defp request(entered, resolved),
    do: %{argument_values: entered, resolved_argument_values: resolved}
end
