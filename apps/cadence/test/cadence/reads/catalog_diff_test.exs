defmodule Cadence.Reads.CatalogDiffTest do
  @moduledoc "Catalog C3 revision diff (DECISIONS #9 v1)."
  use ExUnit.Case, async: true

  alias Cadence.Reads.CatalogDiff

  defp decl(kind, name, definition, refs \\ []) do
    {{kind, name},
     %{
       "kind" => kind,
       "qualified_name" => name,
       "semantic_id" => "semantic:#{kind}:#{:erlang.phash2({name, definition})}",
       "provenance" => %{"import_run_id" => "run-#{:erlang.unique_integer()}"},
       "definition" => definition,
       "references" =>
         Enum.map(refs, fn {k, n} ->
           %{"expected_kind" => k, "resolved_qualified_name" => n, "resolved_id" => "x"}
         end)
     }}
  end

  defp catalog(decls), do: Map.new(decls)

  defp command(name, arg_bits, description \\ "Set it") do
    [
      decl("command", name, %{"description" => description}, [
        {"command_argument", name <> "/arguments/duration"}
      ]),
      decl("command_argument", name <> "/arguments/duration", %{}, [
        {"command_argument_type", name <> "/arguments/duration/type"}
      ]),
      decl("command_argument_type", name <> "/arguments/duration/type", %{
        "size_in_bits" => arg_bits
      })
    ]
  end

  defp parameter(name, bits, unit \\ "degC") do
    [
      decl("parameter", name, %{"units" => unit}, [{"parameter_type", name <> "/type"}]),
      decl("parameter_type", name <> "/type", %{"size_in_bits" => bits})
    ]
  end

  test "rolls changes up to commands and telemetry, with breaking rules" do
    before =
      catalog(
        command("/commands/SET_MODE", 8) ++
          command("/commands/NOOP", 8) ++
          command("/commands/OLD", 8) ++
          parameter("/tm/temp", 16) ++
          parameter("/tm/volts", 16) ++
          [decl("unit", "/units/degC", %{"symbol" => "degC"})]
      )

    after_decls =
      catalog(
        command("/commands/SET_MODE", 16) ++
          command("/commands/NOOP", 8, "Does nothing") ++
          command("/commands/NEW", 8) ++
          parameter("/tm/temp", 32) ++
          parameter("/tm/volts", 16, "V") ++
          [decl("unit", "/units/degC", %{"symbol" => "°C"})]
      )

    %{summary: summary, changes: changes} = CatalogDiff.compare(before, after_decls)

    assert summary.commands == %{before: 3, after: 3, added: 1, changed: 2, removed: 1}
    assert summary.telemetry == %{before: 2, after: 2, added: 0, changed: 2, removed: 0}
    assert summary.total_before == 5
    assert summary.unchanged == 0
    assert summary.breaking == 3

    by_name = Map.new(changes, &{&1.name, &1})

    assert %{op: "changed", kind: "command", breaking: true, change: change} =
             by_name["/commands/SET_MODE"]

    assert change =~ "arguments/duration/type: size_in_bits 8 → 16"
    assert %{op: "changed", breaking: false} = by_name["/commands/NOOP"]
    assert %{op: "removed", breaking: true} = by_name["/commands/OLD"]
    assert %{op: "added", breaking: false} = by_name["/commands/NEW"]
    assert %{kind: "telemetry", breaking: true} = by_name["/tm/temp"]
    assert %{kind: "telemetry", breaking: false, change: "units degC → V"} = by_name["/tm/volts"]
    assert %{kind: "other", op: "changed", breaking: false} = by_name["/units/degC"]

    # Breaking first.
    assert Enum.all?(Enum.take(changes, 3), & &1.breaking)
  end

  test "identical revisions differ in nothing, even when provenance and ids differ" do
    before = catalog(command("/commands/NOOP", 8) ++ parameter("/tm/temp", 16))
    after_decls = catalog(command("/commands/NOOP", 8) ++ parameter("/tm/temp", 16))

    assert %{summary: %{unchanged: 2, breaking: 0}, changes: []} =
             CatalogDiff.compare(before, after_decls)
  end
end
