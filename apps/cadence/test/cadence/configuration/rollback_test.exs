defmodule Cadence.Configuration.RollbackTest do
  @moduledoc "Change-set rollback (change-sets.md §8, DECISIONS #49)."
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.GroundStationStore
  alias Cadence.Configuration.Ledger
  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.SpacecraftStore

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission()
    on_exit(with_approval_required(false))
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  defp apply_ops(ctx, summary, ops) do
    {:ok, staged} = Configuration.stage(ctx.alice, ctx.mission, %{summary: summary}, ops)

    {:ok, %{state: :applied, revision: revision}} =
      Configuration.submit(ctx.alice, ctx.mission, staged.change_set_id, %{
        reason: "Reason for this change",
        expected_version: staged.version
      })

    {staged, revision}
  end

  defp submit_open(ctx, params \\ %{}) do
    {:ok, %{change_set: set}} = Configuration.current(ctx.alice, ctx.mission)

    Configuration.submit(
      ctx.alice,
      ctx.mission,
      set.id,
      Map.merge(%{reason: "Roll it back", expected_version: set.version}, params)
    )
  end

  defp station(ctx, id), do: GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)

  test "rolling back an edit restores it and records a rollback revision", ctx do
    {%{entity_ids: [id]}, 2} = apply_ops(ctx, "Add Svalbard", [station_op("Svalbard")])

    {_, 3} =
      apply_ops(ctx, "Rename", [
        %{
          kind: "ground_station",
          action: "update",
          entity_id: id,
          changes: [%{path: "display_name", value: "Svalbard B"}]
        }
      ])

    assert {:ok, preview} = ConfigurationRollback.preview(ctx.alice, ctx.mission, 2)

    assert %{
             target: 2,
             head: 3,
             reverts: [3],
             summary: "Roll back to r2 (reverts r3)",
             outside: []
           } =
             preview

    assert [%{kind: "ground_station", entity_id: ^id, action: "update"}] = preview.ops
    assert preview.preview.verdict == :go

    assert {:ok, _staged} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 2)
    assert {:ok, %{state: :applied, revision: 4}} = submit_open(ctx)
    assert {:ok, %{display_name: "Svalbard"}} = station(ctx, id)

    assert {:ok, %{kind: :rollback, rolls_back_to: 2}} =
             Configuration.get_revision(ctx.alice, ctx.mission, 4)
  end

  test "rolling back past a creation removes (archives) what was created", ctx do
    {%{entity_ids: [id]}, 2} = apply_ops(ctx, "Add Kiruna", [station_op("Kiruna")])

    assert {:ok, %{ops: [%{action: "delete", entity_id: ^id}]}} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 1)

    assert {:ok, _} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 1)
    assert {:ok, %{state: :applied}} = submit_open(ctx)
    # The ground station kind archives on delete; archived stations aren't fetched.
    assert {:error, :ground_station_not_found} = station(ctx, id)
  end

  defmodule BusyTraffic do
    @moduledoc false
    def with_traffic(_org, _mission, ids), do: MapSet.new(ids)
    def archive_blockers(_org, _mission, _ids), do: %{}
  end

  test "rolling back a spacecraft's creation archives it; with traffic that's a HOLD", ctx do
    {%{entity_ids: [id]}, 2} =
      apply_ops(ctx, "Add craft", [
        %{kind: "spacecraft", action: :create, document: spacecraft_doc("ROLLBACK-1", 911)}
      ])

    previous = Application.get_env(:cadence, :spacecraft_traffic)
    Application.put_env(:cadence, :spacecraft_traffic, BusyTraffic)
    on_exit(fn -> Application.put_env(:cadence, :spacecraft_traffic, previous) end)

    assert {:ok,
            %{ops: [%{kind: "spacecraft", action: "delete", entity_id: ^id}], preview: preview}} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 1)

    assert preview.verdict == :hold

    assert %{items: [%{reason: :spacecraft_has_traffic, entity_id: ^id}]} =
             Enum.find(preview.checks, &(&1.key == "compatibility"))

    assert {:ok, _} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 1)
    assert {:ok, %{state: :applied}} = submit_open(ctx, %{acknowledged_holds: true})

    assert {:ok, %{lifecycle_state: :archived}} =
             SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, id)
  end

  test "refuses bad targets, an open set, nothing to revert and a legacy activation in range",
       ctx do
    {_, 2} = apply_ops(ctx, "Add Troll", [station_op("Troll")])

    assert {:error, :invalid_rollback_target} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 0)

    assert {:error, :invalid_rollback_target} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 2)

    {:ok, _} =
      Configuration.stage(ctx.alice, ctx.mission, %{summary: "Open"}, [station_op("Open")])

    assert {:error, :change_set_open} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 1)

    head = Ledger.lock_head(ctx.org, ctx.mission)

    {:ok, _legacy} =
      Repo.transaction(fn ->
        {:ok, revision} =
          Ledger.record(
            Ledger.lock_head(ctx.org, ctx.mission) || head,
            %{
              kind: "legacy_activation",
              applied_by: %{"kind" => "system", "id" => "test"},
              submitted_by: %{"kind" => "system", "id" => "test"},
              applied_at: DateTime.utc_now(),
              reason: "legacy",
              summary: "Legacy activation"
            },
            []
          )

        revision
      end)

    assert {:error, {:rollback_crosses_legacy, 3}} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 1)
  end

  test "deletes come children first, and nothing joins a rollback's set", ctx do
    station = unique("station")

    {_, 2} =
      apply_ops(ctx, "Station and transport", [
        Map.put(station_op("Hawaii"), :entity_id, station),
        %{
          kind: "transport",
          action: :create,
          document: Map.put(transport_doc("Hawaii TCP"), "ground_station_id", station)
        }
      ])

    assert {:ok,
            %{
              ops: [
                %{kind: "transport", action: "delete"},
                %{kind: "ground_station", action: "delete"}
              ]
            }} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 1)

    assert {:ok, _} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 1)

    assert {:error, :rollback_in_progress} =
             Configuration.stage(ctx.alice, ctx.mission, %{summary: "Sneak in"}, [
               station_op("Late")
             ])
  end

  test "a value changed outside change sets since the target is a HOLD to acknowledge", ctx do
    {%{entity_ids: [id]}, 2} = apply_ops(ctx, "Add Perth", [station_op("Perth")])

    {_, 3} =
      apply_ops(ctx, "Rename", [
        %{
          kind: "ground_station",
          action: "update",
          entity_id: id,
          changes: [%{path: "display_name", value: "Perth B"}]
        }
      ])

    {:ok, _} =
      GroundStationStore.update_ground_station(ctx.org, ctx.mission, id, %{
        region: "Changed directly"
      })

    assert {:ok,
            %{outside: [%{kind: "ground_station", entity_id: ^id}], preview: %{verdict: :hold}}} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, 2)

    assert {:ok, _} = ConfigurationRollback.stage(ctx.alice, ctx.mission, 2)
    assert {:error, {:holds_not_acknowledged, _}} = submit_open(ctx)
    assert {:ok, %{state: :applied}} = submit_open(ctx, %{acknowledged_holds: true})
  end
end
