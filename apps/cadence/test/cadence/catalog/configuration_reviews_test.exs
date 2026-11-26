defmodule Cadence.Catalog.ConfigurationReviewsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Catalog.ConfigurationReviews
  alias Cadence.Catalog.ConfigurationReviews.{MemberRow, SetRow}

  setup do
    %{mission_id: mission} = configuration_mission("review-evidence")
    %{mission: mission}
  end

  defp items(count) do
    for n <- 1..count,
        do: %{
          id: "sc-#{n}",
          configuration_revision_id: "rev-#{n}",
          configuration_token: "tok-#{n}"
        }
  end

  test "stores a review once and reads its evidence back by spacecraft", %{mission: mission} do
    assert {:ok, %{"count" => 3, "sha256" => sha} = ref} =
             ConfigurationReviews.store(mission, items(3))

    assert {:ok, ^ref} = ConfigurationReviews.store(mission, Enum.reverse(items(3)))
    assert Repo.aggregate(where(SetRow, mission_id: ^mission), :count) == 1
    assert Repo.aggregate(where(MemberRow, mission_id: ^mission), :count) == 3

    metadata = %{"configuration_review" => ConfigurationReviews.metadata(ref, "base-1")}
    assert ConfigurationReviews.reviewed?(metadata)
    assert {:ok, ["sc-1", "sc-2", "sc-3"]} = ConfigurationReviews.spacecraft_ids(metadata)

    assert {:ok, %{"sc-2" => evidence} = all} = ConfigurationReviews.evidence(metadata)
    assert map_size(all) == 3

    assert evidence == %{
             "spacecraft_id" => "sc-2",
             "configuration_revision_id" => "rev-2",
             "configuration_token" => "tok-2",
             "base_activation_id" => "base-1"
           }

    assert ^evidence = ConfigurationReviews.evidence_for(metadata, "sc-2")
    assert ConfigurationReviews.evidence_for(metadata, "nope") == nil
    assert sha == ref["sha256"]
  end

  test "a changed token or version is a different review", %{mission: mission} do
    {:ok, one} = ConfigurationReviews.store(mission, items(2))

    changed = List.update_at(items(2), 0, &%{&1 | configuration_token: "tok-new"})
    {:ok, two} = ConfigurationReviews.store(mission, changed)

    refute one["sha256"] == two["sha256"]
  end

  test "the evidence of a review is constant-size in the metadata", %{mission: mission} do
    {:ok, ref} = ConfigurationReviews.store(mission, items(5))
    small = byte_size(Jason.encode!(ConfigurationReviews.metadata(ref, nil)))
    {:ok, ref} = ConfigurationReviews.store(mission, items(50))
    assert byte_size(Jason.encode!(ConfigurationReviews.metadata(ref, nil))) - small < 8
  end

  test "a review set has no size cap", %{mission: mission} do
    assert {:ok, %{"count" => 2_100} = ref} = ConfigurationReviews.store(mission, items(2_100))
    metadata = %{"configuration_review" => ConfigurationReviews.metadata(ref, nil)}
    assert {:ok, evidence} = ConfigurationReviews.evidence(metadata)
    assert map_size(evidence) == 2_100
  end

  test "metadata without a readable reference is stale, never partial", %{mission: mission} do
    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(%{})

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.spacecraft_ids(%{
               "configuration_review" => %{"spacecraft_id" => "x"}
             })

    refute ConfigurationReviews.reviewed?(%{"configuration_review" => %{"spacecraft_id" => "x"}})

    unknown = %{"mission_id" => mission, "sha256" => "missing", "count" => 2}

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(%{
               "configuration_review" => ConfigurationReviews.metadata(unknown, nil)
             })
  end
end
