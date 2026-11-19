defmodule Cadence.Spacecraft.StagedScidsTest do
  @moduledoc """
  S9 (#313, U20): the next free SCID comes from the server, and a SCID another change already
  staged (or another op of the same request) uses is refused at stage, with mms-ux's words.

  - The spacecraft directory sends `scids_in_use` (live, archived and staged in the mission's active
    change set, sorted, deduplicated) and `next_free_scid`, the lowest of 1..1023 not in it.
  - Staging refuses a SCID another staged op holds, or that an earlier op of the same request
    gives to another spacecraft. Re-staging a spacecraft (which replaces its own op) never collides
    with itself.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Control.Configuration
  alias Cadence.Reads.SpacecraftDirectory
  alias Cadence.Spacecraft
  alias Cadence.Spacecraft.StagedScids
  alias Cadence.SpacecraftStore

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("s9")

    %{
      org: org,
      mission: mission,
      alice: member_scope(org, :member, "Alice"),
      bob: member_scope(org, :member, "Bob")
    }
  end

  describe "the directory's SCIDs" do
    test "an empty mission suggests 1", c do
      assert %{next_free_scid: 1, scids_in_use: []} = directory(c)
    end

    test "live, archived and staged SCIDs are in use; the lowest free one is next", c do
      live!(c, "EARENDIL-1", 1)
      live!(c, "EARENDIL-2", 2)
      live!(c, "EARENDIL-5", 5)
      archived = live!(c, "EARENDIL-3", 3)
      {:ok, _} = SpacecraftStore.archive_spacecraft(c.org, c.mission, archived.spacecraft_id, %{})

      x = live!(c, "EARENDIL-10", 10)
      stage!(c.alice, c, [create("EARENDIL-4", 4)])
      stage!(c.bob, c, [scid_update(x, 7)])

      assert %{scids_in_use: [1, 2, 3, 4, 5, 7, 10], next_free_scid: 6} = directory(c)
    end

    test "next is the lowest of 1..1023 not in use, never 0, nil when none is free" do
      assert StagedScids.next_free([]) == 1
      assert StagedScids.next_free([0, 1, 2, 4]) == 3
      assert StagedScids.next_free(Enum.to_list(1..1022)) == 1023
      assert StagedScids.next_free(Enum.to_list(1..1023)) == nil
      assert StagedScids.next_free(Enum.to_list(0..1023)) == nil
    end
  end

  describe "staging refuses a SCID already staged (mms-ux's words)" do
    test "another author's staged create holds it", c do
      stage!(c.alice, c, [create("EARENDIL-313", 312)])

      assert {:error, {:invalid_op, 0, [error]}} =
               stage(c.bob, c, [create("EARENDIL-314", 312)])

      assert error.path == "scid"

      assert error.message ==
               "SCID 312 is already staged for EARENDIL-313 in the open change set; choose another"

      assert error.details == %{
               scid: 312,
               spacecraft_name: "EARENDIL-313",
               source: "staged",
               in_review: false
             }
    end

    test "a staged update of a live spacecraft holds it", c do
      x = live!(c, "EARENDIL-10", 10)
      stage!(c.alice, c, [scid_update(x, 312)])

      assert {:error, {:invalid_op, 0, [%{details: %{spacecraft_name: "EARENDIL-10"}}]}} =
               stage(c.bob, c, [create("EARENDIL-314", 312)])
    end

    test "two ops of the same request: the later one is refused, by its index", c do
      assert {:error, {:invalid_op, 2, [error]}} =
               stage(c.alice, c, [
                 create("EARENDIL-313", 312),
                 create("EARENDIL-500", 500),
                 create("EARENDIL-314", 312)
               ])

      assert error.message ==
               "SCID 312 is also given to EARENDIL-313 in this batch; choose another"

      assert error.details == %{
               scid: 312,
               spacecraft_name: "EARENDIL-313",
               source: "request",
               in_review: false
             }

      # Nothing was staged.
      assert {:ok, %{change_set: nil}} = Configuration.current(c.alice, c.mission)
    end

    test "re-staging a spacecraft never collides with its own staged op (fe-setup)", c do
      x = live!(c, "EARENDIL-10", 10)
      stage!(c.alice, c, [scid_update(x, 312)])

      # The same SCID again, then another free one: both replace alice's own op.
      stage!(c.alice, c, [scid_update(x, 312)])
      stage!(c.alice, c, [scid_update(x, 313)])

      assert %{scids_in_use: [10, 313]} = directory(c)

      # 312 is free again; 313 is x's, and refused for another spacecraft.
      stage!(c.bob, c, [create("EARENDIL-312", 312)])

      assert {:error,
              {:invalid_op, 0, [%{details: %{scid: 313, spacecraft_name: "EARENDIL-10"}}]}} =
               stage(c.bob, c, [create("EARENDIL-999", 313)])
    end

    test "a SCID nobody staged stages; a staged spacecraft with no SCID holds none", c do
      stage!(c.alice, c, [create("EARENDIL-313", nil)])
      stage!(c.bob, c, [create("EARENDIL-314", 314)])

      assert %{scids_in_use: [314]} = directory(c)
    end
  end

  defp directory(c) do
    c.org
    |> SpacecraftDirectory.index(c.mission)
    |> Map.take([:next_free_scid, :scids_in_use])
  end

  defp live!(c, name, scid) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: unique("sc"),
        organization_id: c.org,
        mission_id: c.mission,
        display_name: name,
        scid: scid
      })

    {:ok, persisted} = SpacecraftStore.persist_spacecraft(c.org, spacecraft)
    persisted
  end

  defp create(name, scid),
    do: %{kind: "spacecraft", action: :create, document: spacecraft_doc(name, scid)}

  defp scid_update(%Spacecraft{} = spacecraft, scid),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: spacecraft.spacecraft_id,
      changes: [%{path: "scid", value: scid}]
    }

  defp stage(scope, c, ops), do: Configuration.stage(scope, c.mission, %{summary: "S9"}, ops)

  defp stage!(scope, c, ops) do
    {:ok, staged} = stage(scope, c, ops)
    staged
  end
end
