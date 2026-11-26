defmodule Cadence.Configuration.PreviewOutcomeTest do
  @moduledoc """
  #522 (#313 K9, Changes.md K3): the explicit preview says what the set would leave behind,
  read in the preview's own rolled-back transaction before and after the staged ops: the fleet
  size, the usable routes (added and removed) and readiness' counts.

  api-ops' line: only the explicit preview computes it, never the preview that submit and review
  run as their gate, and a failed or slow outcome read leaves `outcome: nil` without touching the
  verdict. domain's: readiness is evaluated only when the set touches what it reads.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Configuration.{Ledger, Preview, Staging}
  alias Cadence.Control.Configuration
  alias Cadence.Reads.ChangeSetOutcome

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("outcome-522")
    alice = member_scope(org, :member, "Alice")
    ids = %{svb: unique("svb"), svb_tcp: unique("svb-tcp"), profile: unique("block1")}

    apply_ops(%{alice: alice, mission: mission}, "Block 1 with Svalbard", [
      create("ground_station", %{"display_name" => "Svalbard", "code" => "SVB"}, ids.svb),
      create("transport", station_transport("Svalbard TCP", ids.svb, "inbound"), ids.svb_tcp),
      create("spacecraft_profile", profile_with_rule(ids.svb), ids.profile)
    ])

    [sc] =
      apply_ops(%{alice: alice, mission: mission}, "First spacecraft", [
        create("spacecraft", spacecraft_doc("EARENDIL-001", 1, {ids.profile, 1}))
      ])

    %{org: org, mission: mission, alice: alice, ids: ids, sc: sc}
  end

  test "a create: one more spacecraft, its profile's routes added", c do
    outcome =
      outcome!(c, [create("spacecraft", spacecraft_doc("EARENDIL-002", 2, {c.ids.profile, 1}))])

    assert outcome.spacecraft == %{now: 1, after: 2}
    assert %{now: now, after: later, added: added, removed: 0} = outcome.routes
    assert added > 0 and later == now + added
    assert %{now: %{blocker: _}, after: %{blocker: _}} = outcome.readiness
  end

  test "an archive: one fewer spacecraft, its routes removed", c do
    outcome = outcome!(c, [%{kind: "spacecraft", action: :delete, entity_id: c.sc}])

    assert outcome.spacecraft == %{now: 1, after: 0}
    assert %{now: now, after: 0, added: 0, removed: removed} = outcome.routes
    assert now > 0 and removed == now
  end

  test "a routing change: an extra route adds routes and removes none", c do
    inu = unique("inu")

    apply_ops(c, "Inuvik spare", [
      create("ground_station", %{"display_name" => "Inuvik", "code" => "INU"}, inu),
      create(
        "transport",
        station_transport("Inuvik TCP", inu, "bidirectional"),
        unique("inu-tcp")
      )
    ])

    # As spacecraft_route_kind_test's extra/1: a downlink and an uplink leg at Inuvik.
    extra = %{
      "spacecraft_id" => c.sc,
      "ground_station_id" => inu,
      "purpose_label" => "Recovery",
      "downlink" => "primary",
      "uplink" => "primary"
    }

    outcome = outcome!(c, [create("spacecraft_route", extra)])
    assert outcome.spacecraft == %{now: 1, after: 1}
    assert %{added: 2, removed: 0} = outcome.routes
  end

  test "readiness after differs from now when the set changes what it reads", c do
    outcome = outcome!(c, [create("spacecraft", spacecraft_doc("NO-PROFILE-1", 9))])
    refute outcome.readiness.after == outcome.readiness.now
  end

  test "readiness is read only when the set touches what it reads (domain)" do
    assert ChangeSetOutcome.readiness?([%{kind: "spacecraft"}])
    assert ChangeSetOutcome.readiness?([%{kind: "derived_telemetry"}, %{kind: "transport"}])
    refute ChangeSetOutcome.readiness?([%{kind: "derived_telemetry"}])
    refute ChangeSetOutcome.readiness?([%{kind: "limit_definition"}])
  end

  test "a set the pipeline can't fully check (a validation error) has no outcome", c do
    # As config_kinds_test's "invalid settings are a NO-GO in preview".
    bad_transport = put_in(transport_doc("Bad")["configuration"]["port"], "not-a-port")

    assert {:ok, %{verdict: :no_go, outcome: nil}} =
             Configuration.preview(
               c.alice,
               c.mission,
               {:ops, [create("transport", bad_transport)]},
               outcome: ChangeSetOutcome
             )
  end

  test "a failing outcome read gives outcome nil and leaves the verdict and checks alone", c do
    ops = [%{kind: "spacecraft", action: :delete, entity_id: c.sc}]
    head = Ledger.ensure_head(c.org, c.mission).revision_number
    {:ok, prepared} = Staging.prepare_ops(c.org, c.mission, ops)

    assert {:ok, plain} = Preview.run(c.org, c.mission, head, prepared)
    refute Map.has_key?(plain, :outcome)

    # A database error inside the reader: the preview's transaction must survive it.
    failing = fn -> Repo.query!("SELECT * FROM no_such_table_522") end

    assert {:ok, with_failure} = Preview.run(c.org, c.mission, head, prepared, outcome: failing)
    assert with_failure.outcome == nil
    assert Map.delete(with_failure, :outcome) == plain
  end

  test "submit's answer carries no outcome", c do
    {:ok, staged} =
      Configuration.stage(c.alice, c.mission, %{summary: "Archive"}, [
        %{kind: "spacecraft", action: :delete, entity_id: c.sc}
      ])

    assert {:ok, answer} =
             Configuration.submit(c.alice, c.mission, staged.change_set_id, %{
               reason: "Archive the first spacecraft",
               expected_version: staged.version,
               acknowledged_holds: true
             })

    refute has_outcome?(answer)
  end

  defp outcome!(c, ops) do
    assert {:ok, %{outcome: %{} = outcome}} =
             Configuration.preview(c.alice, c.mission, {:ops, ops}, outcome: ChangeSetOutcome)

    outcome
  end

  defp has_outcome?(%{} = map) when not is_struct(map),
    do: Map.has_key?(map, :outcome) or Enum.any?(Map.values(map), &has_outcome?/1)

  defp has_outcome?(list) when is_list(list), do: Enum.any?(list, &has_outcome?/1)
  defp has_outcome?(_other), do: false

  # As spacecraft_route_kind_test's helpers.
  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(kind, document, id \\ nil) do
    op = %{kind: kind, action: :create, document: document}
    if id, do: Map.put(op, :entity_id, id), else: op
  end

  defp station_transport(name, station, direction) do
    name
    |> transport_doc()
    |> put_in(["configuration", "direction_capability"], direction)
    |> Map.put("ground_station_id", station)
  end

  defp profile_with_rule(station),
    do:
      Map.put(profile_doc("Block 1"), "routing_rules", [
        %{
          "id" => "ttc",
          "label" => "TT&C",
          "stations" => [%{"ground_station_id" => station}],
          "legs" => [%{"direction" => "downlink", "role" => "primary"}]
        }
      ])
end
