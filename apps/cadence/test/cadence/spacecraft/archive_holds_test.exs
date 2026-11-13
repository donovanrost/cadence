defmodule Cadence.Spacecraft.ConfigKinds.ArchiveHoldsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Commanding.ReleaseTargetGuard
  alias Cadence.Control.{Configuration, SpacecraftTraffic}
  alias Cadence.Spacecraft.ConfigKinds.ArchiveHolds
  alias Cadence.SpacecraftStore

  defmodule AheadTraffic do
    @moduledoc false
    def with_traffic(_org, _mission, ids), do: MapSet.new(ids)

    def archive_blockers(_org, _mission, _ids),
      do: %{
        "sc-busy" => %{
          waiting_requests: 2,
          booked_passes: 3,
          earliest_pass_at: ~U[2026-11-15 03:00:00Z]
        },
        "sc-one" => %{waiting_requests: 0, booked_passes: 1, earliest_pass_at: nil}
      }
  end

  setup do
    previous = Application.get_env(:cadence, :spacecraft_traffic)
    Application.put_env(:cadence, :spacecraft_traffic, AheadTraffic)
    on_exit(fn -> Application.put_env(:cadence, :spacecraft_traffic, previous) end)
  end

  defp archive(id, name),
    do: %{kind: "spacecraft", op: :delete, entity_id: id, previous: %{"display_name" => name}}

  test "waiting requests block; booked passes and past traffic are acknowledged" do
    holds = ArchiveHolds.holds("org", "mission", [archive("sc-busy", "EARENDIL-312")])
    by_reason = Map.new(holds, &{&1.reason, &1})

    assert %{blocking: true, sentence: waiting, details: %{waiting_requests: 2}} =
             by_reason.spacecraft_commands_waiting

    assert waiting == "EARENDIL-312 has 2 command requests waiting. Release or cancel them first."

    assert %{blocking: false, sentence: booked, details: details} =
             by_reason.spacecraft_passes_booked

    assert booked ==
             "3 booked passes from 11-15 03:00Z stay booked after EARENDIL-312 is archived. " <>
               "Release them in Contacts if they're not needed."

    assert details == %{
             waiting_requests: 2,
             booked_passes: 3,
             earliest_pass_at: ~U[2026-11-15 03:00:00Z]
           }

    assert %{
             blocking: false,
             sentence: "EARENDIL-312 has had passes booked or commands requested." <> _
           } =
             by_reason.spacecraft_has_traffic
  end

  test "one booked pass with no known time reads in the singular, without 'on'" do
    holds = ArchiveHolds.holds("org", "mission", [archive("sc-one", "EARENDIL-009")])

    assert [
             %{reason: :spacecraft_passes_booked, sentence: sentence},
             %{reason: :spacecraft_has_traffic}
           ] =
             holds

    assert sentence ==
             "1 booked pass stays booked after EARENDIL-009 is archived. " <>
               "Release it in Contacts if it isn't needed."
  end

  test "only archives raise them" do
    assert ArchiveHolds.holds("org", "mission", [
             %{kind: "spacecraft", op: :update, entity_id: "sc-busy"}
           ]) == []
  end

  test "an archived spacecraft is never a release target" do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("archived")
    alice = member_scope(org, :member, "Alice")
    ops = [%{kind: "spacecraft", action: :create, document: spacecraft_doc("ARCHIVED-1", 911)}]
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: "Add"}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: add a spacecraft",
        expected_version: staged.version
      })

    [id] = staged.entity_ids
    # The real adapter's queries: nothing waits on, or is booked for, a new spacecraft.
    assert SpacecraftTraffic.archive_blockers(org, mission, [id]) == %{}
    assert SpacecraftTraffic.with_traffic(org, mission, [id]) == MapSet.new()
    assert ReleaseTargetGuard.live(org, mission, id) == :ok

    assert {:ok, _archived} =
             SpacecraftStore.archive_spacecraft(org, mission, id, %{kind: "user", id: "u"})

    assert ReleaseTargetGuard.live(org, mission, id) == {:error, {:spacecraft_archived, id}}
  end
end
