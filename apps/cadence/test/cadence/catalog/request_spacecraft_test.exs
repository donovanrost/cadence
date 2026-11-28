defmodule Cadence.Catalog.RequestSpacecraftTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Catalog.{ChangeSetSpacecraft, ConfigurationReviews, RequestSpacecraft}
  alias Cadence.Control.Activations.Description

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("request-craft")

    %{organization_id: other_org, mission_id: other} =
      configuration_mission("request-craft-other")

    %{org: org, mission: mission, other_org: other_org, other: other}
  end

  defp review(c, ids) do
    {:ok, ref} =
      ConfigurationReviews.store(
        c.org,
        c.mission,
        Enum.map(ids, &%{id: &1, configuration_revision_id: "r-#{&1}", configuration_token: "t"})
      )

    %{"configuration_review" => ConfigurationReviews.metadata(ref, nil)}
  end

  defp change_set(c, change_set_id, ids) do
    {:ok, ref} = ChangeSetSpacecraft.store(c.org, c.mission, change_set_id, 1, ids)
    %{"change_set" => ref}
  end

  test "a change set's changed spacecraft are rows; the metadata keeps the reference and count",
       c do
    metadata = change_set(c, "cs-1", ["sc-2", "sc-1"])

    assert metadata["change_set"] == %{"id" => "cs-1", "revision" => 1, "count" => 2}
    assert ChangeSetSpacecraft.count(metadata) == 2
    assert ChangeSetSpacecraft.spacecraft_ids(c.org, c.mission, metadata) == ["sc-1", "sc-2"]

    # Idempotent: the same generation again changes nothing.
    assert {:ok, %{"count" => 2}} =
             ChangeSetSpacecraft.store(c.org, c.mission, "cs-1", 1, ["sc-1", "sc-2"])
  end

  test "another mission's change set is never read as this one's", c do
    {:ok, _} = ChangeSetSpacecraft.store(c.other_org, c.other, "cs-1", 1, ["sc-x"])
    metadata = %{"change_set" => %{"id" => "cs-1", "revision" => 1, "count" => 1}}

    assert ChangeSetSpacecraft.spacecraft_ids(c.org, c.mission, metadata) == []
    assert ChangeSetSpacecraft.spacecraft_ids(c.other_org, c.other, metadata) == ["sc-x"]

    assert_raise Postgrex.Error, ~r/foreign_key_violation/, fn ->
      ChangeSetSpacecraft.store(c.other_org, c.mission, "cs-2", 1, ["sc-1"])
    end
  end

  test "count and ids work for every kind of request metadata", c do
    assert RequestSpacecraft.count(review(c, ["sc-1", "sc-2", "sc-3"])) == 3
    assert RequestSpacecraft.count(change_set(c, "cs-1", ["sc-1"])) == 1
    assert RequestSpacecraft.count(%{}) == nil

    assert RequestSpacecraft.ids(c.org, c.mission, review(c, ["sc-2", "sc-1"])) == [
             "sc-1",
             "sc-2"
           ]

    assert RequestSpacecraft.ids(c.org, c.mission, %{}) == []
    # A review reference read under another mission is unreadable, so it names nothing.
    assert RequestSpacecraft.ids(c.other_org, c.other, review(c, ["sc-1"])) == []
  end

  test "which requests touch a spacecraft is answered for the whole list at once", c do
    requests =
      [
        %{metadata: review(c, ["sc-1", "sc-2"])},
        %{metadata: review(c, ["sc-3"])},
        %{metadata: change_set(c, "cs-1", ["sc-2"])},
        %{metadata: %{}}
      ]

    touches = RequestSpacecraft.touching(c.org, c.mission, requests, "sc-2")
    assert Enum.map(requests, touches) == [true, false, true, true]

    touches = RequestSpacecraft.touching(c.org, c.mission, requests, "sc-3")
    assert Enum.map(requests, touches) == [false, true, false, true]
  end

  test "describe counts from the reference alone and loads ids only when asked", c do
    request = %{
      organization_id: c.org,
      mission_id: c.mission,
      metadata: Map.put(review(c, ["sc-1", "sc-2"]), "spacecraft_configuration_version", 2)
    }

    assert %{
             kind: "spacecraft_configuration",
             summary: "Spacecraft configuration for 2 spacecraft",
             spacecraft_count: 2,
             spacecraft_ids: []
           } = Description.describe(request)

    assert %{spacecraft_ids: ["sc-1", "sc-2"]} = Description.describe(request, ids: true)

    assert %{summary: "Mission activation", spacecraft_count: 0} = Description.describe(%{})
  end
end
