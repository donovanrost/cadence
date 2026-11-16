defmodule Cadence.Configuration.DerivedTelemetryKindTest do
  @moduledoc """
  Derived telemetry points through change sets (DECISIONS #77, stage 1): create, edit and retire
  keep the definition's versions; ids and expressions are checked; retiring a point another
  derived point reads is a blocking HOLD (ux U42) unless that one changes too.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import Ecto.Query

  alias Cadence.Control.Configuration
  alias Cadence.Governance
  alias Cadence.Governance.DerivedTelemetryKind, as: ConfigKind
  alias Cadence.Governance.GovernedDerivedTelemetryDefinitionRow

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("derived")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  test "create, edit and retire keep the point's versions; retired leaves the live set", ctx do
    [id] = apply_ops(ctx, "Add", [create(point("DERIVED.BUS_POWER", "28 * 2", "Bus power"))])

    assert [%{derived_definition_id: ^id, version: 1, point_name: "Bus power"}] = live(ctx)

    apply_ops(ctx, "Edit", [edit(id, "expression", "28 * 3")])
    assert [%{version: 2, expression: "28 * 3"}] = live(ctx)

    apply_ops(ctx, "Retire", [%{kind: "derived_telemetry", action: :delete, entity_id: id}])
    assert live(ctx) == []
    assert ConfigKind.load(ctx.org, ctx.mission, [id]) == %{}

    # History stays: the retired version is the latest.
    assert {:ok, %{version: 3}} =
             Governance.fetch_derived_definition(ctx.org, ctx.mission, id, nil)

    # A retired point's id isn't reused.
    assert validation_errors(ctx, [create(point("DERIVED.BUS_POWER", "1 + 1"))]) == ["point_id"]
  end

  # Sweep row 3 (director): a change set's writes carry its applier. The save trail names them, and
  # a retire records them as retired_by (it was always nil: the kind never got the actor).
  test "the applier is the save trail's saved_by and the retire's retired_by", ctx do
    [id] = apply_ops(ctx, "Add", [create(point("DERIVED.TRAIL", "28 * 2"))])
    alice_id = ctx.alice.user.user_id

    assert {:ok, created} = Governance.fetch_derived_definition(ctx.org, ctx.mission, id, nil)
    assert %{"via" => "change_set", "saved_by" => %{"id" => ^alice_id}} = created.metadata

    apply_ops(ctx, "Retire", [%{kind: "derived_telemetry", action: :delete, entity_id: id}])

    assert %{retired_by: ^alice_id} =
             Repo.one(
               from(r in GovernedDerivedTelemetryDefinitionRow,
                 where: r.derived_definition_id == ^id and not is_nil(r.retired_at)
               )
             )
  end

  test "ids, expressions and source points are checked before anything applies", ctx do
    [_id] = apply_ops(ctx, "Add", [create(point("DERIVED.BASE", "2 + 2"))])

    assert validation_errors(ctx, [create(point("DERIVED.BASE", "3 + 3"))]) == ["point_id"]
    # A parse error is caught when staging.
    assert {:error, {:invalid_op, 0, [%{path: "expression"}]}} =
             Configuration.preview(
               ctx.alice,
               ctx.mission,
               {:ops, [create(point("DERIVED.BAD", "2 +"))]}
             )

    assert validation_errors(ctx, [create(point("DERIVED.USES_GHOST", "GHOST.value * 2"))]) == [
             "expression"
           ]

    # A live derived point is a valid source.
    assert [_] = apply_ops(ctx, "Add", [create(point("DERIVED.TWICE_BASE", "DERIVED.BASE * 2"))])
  end

  test "retiring a point another one reads holds, unless that one is retired too", ctx do
    [base] = apply_ops(ctx, "Add", [create(point("DERIVED.SOC", "50 + 1"))])
    [user] = apply_ops(ctx, "Add", [create(point("DERIVED.HEALTH", "DERIVED.SOC / 2"))])
    retire = %{kind: "derived_telemetry", action: :delete, entity_id: base}

    assert {:ok, %{verdict: verdict, checks: checks}} =
             Configuration.preview(ctx.alice, ctx.mission, {:ops, [retire]})

    assert verdict in [:no_go, :hold]

    assert %{
             items: [
               %{
                 reason: :derived_point_in_use,
                 blocking: true,
                 sentence:
                   "DERIVED.SOC can't be retired: DERIVED.HEALTH's expression uses it. " <>
                     "Change or retire DERIVED.HEALTH in this change set too.",
                 details: %{
                   point_id: "DERIVED.SOC",
                   used_by: [%{point_id: "DERIVED.HEALTH", definition_id: ^user}]
                 }
               }
             ]
           } = Enum.find(checks, &(&1.key == "compatibility"))

    both = [retire, %{kind: "derived_telemetry", action: :delete, entity_id: user}]
    assert {:ok, %{verdict: :go}} = Configuration.preview(ctx.alice, ctx.mission, {:ops, both})
  end

  defp point(id, expression, name \\ nil),
    do: %{"point_id" => id, "expression" => expression, "point_name" => name}

  defp live(%{org: org, mission: mission}), do: Governance.list_derived_definitions(org, mission)

  defp validation_errors(%{alice: alice, mission: mission}, ops) do
    {:ok, %{verdict: :no_go, checks: checks}} = Configuration.preview(alice, mission, {:ops, ops})
    %{items: [%{errors: errors}]} = Enum.find(checks, &(&1.key == "validation"))
    Enum.map(errors, & &1.path)
  end

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(document), do: %{kind: "derived_telemetry", action: :create, document: document}

  defp edit(id, path, value),
    do: %{
      kind: "derived_telemetry",
      action: :update,
      entity_id: id,
      changes: [%{path: path, value: value}]
    }
end
