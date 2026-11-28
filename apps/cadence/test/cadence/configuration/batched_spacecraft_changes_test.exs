defmodule Cadence.Configuration.BatchedSpacecraftChangesTest do
  @moduledoc """
  A change set's spacecraft changes cost the same however many there are (#1049): the checks read
  their context once, and creates, updates and archives are one statement each. The fleet approve
  ran ~12 statements per spacecraft; the rollback preview of a fleet ran one lock and one job
  insert per spacecraft.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Bulk

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("batched")
    %{org: org, mission: mission, scope: member_scope(org, :organization_admin, "Mira")}
  end

  describe "statements per change set (5 vs 50 spacecraft)" do
    test "adding spacecraft" do
      assert_equal_counts(fn n ->
        ctx = fresh("add#{n}")
        stage_submit_counted(ctx, "Add #{n}", adds(n, 1))
      end)
    end

    test "editing spacecraft: name, SCID and switches" do
      assert_equal_counts(fn n ->
        ctx = fresh("edit#{n}")
        ids = apply_ops(ctx, "Seed #{n}", adds(n, 1))

        edits =
          for {id, i} <- Enum.with_index(ids, 1) do
            %{
              kind: "spacecraft",
              action: :update,
              entity_id: id,
              changes: [
                %{path: "display_name", value: "Renamed #{i}"},
                %{path: "scid", value: 500 + i},
                %{path: "commanding_enabled", value: true}
              ]
            }
          end

        stage_submit_counted(ctx, "Edit #{n}", edits)
      end)
    end

    test "archiving spacecraft" do
      assert_equal_counts(fn n ->
        ctx = fresh("archive#{n}")
        ids = apply_ops(ctx, "Seed #{n}", adds(n, 1))
        deletes = for id <- ids, do: %{kind: "spacecraft", action: :delete, entity_id: id}
        stage_submit_counted(ctx, "Archive #{n}", deletes)
      end)
    end

    test "previewing a rollback of the fleet's addition" do
      assert_equal_counts(fn n ->
        ctx = fresh("rollback#{n}")
        apply_ops(ctx, "Seed #{n}", adds(n, 1))

        {result, queries} =
          count(fn -> ConfigurationRollback.preview(ctx.scope, ctx.mission, 1) end)

        assert {:ok, %{ops: ops, preview: %{verdict: verdict}}} = result
        assert length(ops) == n
        assert verdict in [:go, :hold]
        queries
      end)
    end
  end

  describe "the same answers as checking and writing one change at a time" do
    test "a SCID one spacecraft gives up is free for the next change in the set", c do
      [a, b] = apply_ops(c, "Two", adds(2, 21))

      chain = [scid_op(a, 23), scid_op(b, 21)]

      assert {:ok, staged} = Configuration.stage(c.scope, c.mission, %{summary: "Chain"}, chain)
      assert {:ok, %{state: :applied}} = submit(c, staged)
      assert scids(c, [a, b]) == %{a => 23, b => 21}
    end

    test "a swap is refused, as when each change was checked after the one before", c do
      [a, b] = apply_ops(c, "Two", adds(2, 25))

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mission, {:ops, [scid_op(a, 26), scid_op(b, 25)]})

      assert %{items: [%{entity_id: ^a, errors: [%{path: "scid"}]} | _]} =
               Enum.find(checks, &(&1.key == "validation"))
    end

    test "a SCID an archived spacecraft keeps is taken", c do
      [id] = apply_ops(c, "One", adds(1, 31))
      apply_ops(c, "Archive", [%{kind: "spacecraft", action: :delete, entity_id: id}])
      assert %{31 => ^id} = Bulk.scid_holders(c.org, c.mission, [31])

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(
                 c.scope,
                 c.mission,
                 {:ops, [create_op("Late", 31)]}
               )

      assert %{items: [%{errors: [%{path: "scid", message: message}]}]} =
               Enum.find(checks, &(&1.key == "validation"))

      assert message == "SCID 31 is already used in this mission"
    end

    test "only the changes that fail are named; the others stay valid", c do
      [taken] = apply_ops(c, "One", adds(1, 41))

      ops = [create_op("Fine", 42), create_op("Clash", 41), create_op("Also fine", 43)]

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(c.scope, c.mission, {:ops, ops})

      assert %{items: [%{errors: [%{path: "scid"}]}]} =
               Enum.find(checks, &(&1.key == "validation"))

      assert [^taken] =
               SpacecraftStore.list_spacecraft(c.org, c.mission) |> Enum.map(& &1.spacecraft_id)
    end

    test "creates, edits and archives of one change set apply together", c do
      [keep, edit, drop] = apply_ops(c, "Three", adds(3, 51))

      ops = [
        create_op("New", 60),
        %{
          kind: "spacecraft",
          action: :update,
          entity_id: edit,
          changes: [
            %{path: "display_name", value: "Edited"},
            %{path: "telemetry_enabled", value: false}
          ]
        },
        %{kind: "spacecraft", action: :delete, entity_id: drop}
      ]

      [created, ^edit, ^drop] = apply_ops(c, "Mixed", ops)

      assert {:ok, %{display_name: "New", scid: 60, commanding_enabled: nil}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, created)

      assert {:ok, %{display_name: "Edited", scid: 52, telemetry_enabled: false}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, edit)

      assert {:ok, %{lifecycle_state: :archived}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, drop)

      assert {:ok, %{display_name: "Craft 51", lifecycle_state: :active}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, keep)
    end

    test "a new spacecraft carries the switches the change set set", c do
      doc = Map.merge(spacecraft_doc("Switched", 70), %{"commanding_enabled" => true})
      [id] = apply_ops(c, "Switched", [%{kind: "spacecraft", action: :create, document: doc}])

      assert {:ok, %{commanding_enabled: true, telemetry_enabled: nil}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, id)
    end
  end

  describe "a spacecraft written outside the change set" do
    test "is not recorded as this change set's create", c do
      [existing] = apply_ops(c, "One", adds(1, 80))
      {:ok, taken} = SpacecraftStore.fetch_spacecraft(c.org, c.mission, existing)
      fresh = Spacecraft.new(%{mission_id: c.mission, display_name: "Fresh", scid: 81})
      clash = %{taken | display_name: "Clash", scid: 82}

      assert {:error, ^existing, :entity_exists} =
               Bulk.insert(c.org, c.mission, [fresh, clash])

      # The craft that is there keeps what it had.
      assert {:ok, %{display_name: "Craft 80", scid: 80}} =
               SpacecraftStore.fetch_spacecraft(c.org, c.mission, existing)
    end
  end

  # Both sizes run in the same test, each in its own mission; the counts must be equal.
  defp assert_equal_counts(measure) do
    small = measure.(5)
    large = measure.(50)
    assert small == large, "5 spacecraft: #{small} statements, 50 spacecraft: #{large}"
  end

  defp fresh(prefix) do
    %{organization_id: org, mission_id: mission} = configuration_mission(prefix)
    %{org: org, mission: mission, scope: member_scope(org, :organization_admin, "Mira")}
  end

  defp adds(n, first_scid),
    do: for(i <- 0..(n - 1), do: create_op("Craft #{first_scid + i}", first_scid + i))

  defp create_op(name, scid),
    do: %{kind: "spacecraft", action: :create, document: spacecraft_doc(name, scid)}

  defp scid_op(id, scid),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: "scid", value: scid}]
    }

  defp scids(c, ids) do
    {:ok, found} = SpacecraftStore.fetch_spacecrafts(c.org, c.mission, ids)
    Map.new(found, fn {id, craft} -> {id, craft.scid} end)
  end

  defp apply_ops(c, summary, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mission, %{summary: summary}, ops)
    {:ok, %{state: :applied}} = submit(c, staged)
    staged.entity_ids
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission, staged.change_set_id, %{
      reason: "Batched spacecraft changes test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp stage_submit_counted(c, summary, ops) do
    {:ok, staged} = Configuration.stage(c.scope, c.mission, %{summary: summary}, ops)
    {result, queries} = count(fn -> submit(c, staged) end)
    assert {:ok, %{state: :applied}} = result
    queries
  end

  # The statements the calling process runs inside `fun`.
  defp count(fun) do
    test_pid = self()
    handler = "batched-spacecraft-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    try do
      {fun.(), :counters.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end
end
