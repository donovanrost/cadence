defmodule Cadence.DevSeedGuardTest do
  @moduledoc """
  #250 (the user's ruling, 2026-11-26): dev seeds may approve, execute and activate, but only
  through the public domain functions, acting as seeded dev accounts. They never write a decision
  or approval row themselves.

  Every `dev/**/*.exs` (the chaos lab included) is parsed, never run. A reference to a decision
  table's schema module, or a string naming a decision table (raw SQL), fails the test. The
  decision tables are `Governance.DecisionRecord.tables/0`, the same list the append-only
  triggers guard, so a new decision table is covered without editing this file. The triggers
  already refuse UPDATE and DELETE; this covers INSERT.

  A bypass inside `lib/` (an approval-skipping or system-actor path) is a product bug, not a seed
  rule: it belongs under #721 (#19 is the known one).
  """
  use ExUnit.Case, async: true

  alias Cadence.Governance.DecisionRecord

  @dev Path.expand("../../../../dev", __DIR__)

  test "no dev seed writes a decision or approval row directly" do
    names = decision_names()

    hits =
      for file <- seed_files(),
          hit <- scan(File.read!(Path.join(@dev, file)), names),
          do: Map.put(hit, :file, file)

    assert hits == [],
           "dev seeds decide only through public domain functions (#250): " <> inspect(hits)
  end

  test "the guard sees every decision table and the seed tree" do
    %{tables: tables, schemas: schemas} = decision_names()
    assert tables == MapSet.new(DecisionRecord.tables())
    # Every decision table has a schema module the scan knows by name.
    assert MapSet.size(schemas) >= length(DecisionRecord.tables())
    assert "seed/earendil.exs" in seed_files()
  end

  test "the scanner flags a decision schema and raw SQL, not a public call" do
    names = %{
      tables: MapSet.new(["command_approvals"]),
      schemas: MapSet.new(["CommandApprovalRow"])
    }

    assert [%{kind: :schema, name: "CommandApprovalRow"}] =
             scan("Repo.insert(%Cadence.Commanding.CommandApprovalRow{})", names)

    assert [%{kind: :table, name: "command_approvals"}] =
             scan(~s|Repo.query!("INSERT INTO command_approvals VALUES (1)")|, names)

    assert scan("MissionModels.approve(scope, mission, revision, reason)", names) == []
  end

  defp decision_names do
    tables = MapSet.new(DecisionRecord.tables())
    {:ok, modules} = :application.get_key(:cadence, :modules)

    schemas =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :__schema__, 1),
          module.__schema__(:source) in tables,
          into: MapSet.new(),
          do: module |> Module.split() |> List.last()

    %{tables: tables, schemas: schemas}
  end

  defp seed_files do
    @dev
    |> Path.join("**/*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @dev))
    |> Enum.sort()
  end

  defp scan(source, names) do
    {_ast, hits} =
      source
      |> Code.string_to_quoted!(columns: false)
      |> Macro.prewalk([], fn node, acc -> {node, hit(node, names) ++ acc} end)

    Enum.reverse(hits)
  end

  defp hit({:__aliases__, meta, parts}, %{schemas: schemas}) when is_list(parts) do
    name = parts |> List.last() |> to_string()
    if name in schemas, do: [%{kind: :schema, name: name, line: meta[:line]}], else: []
  end

  defp hit(string, %{tables: tables}) when is_binary(string) do
    for table <- tables, string =~ ~r/\b#{table}\b/, do: %{kind: :table, name: table}
  end

  defp hit(_node, _names), do: []
end
