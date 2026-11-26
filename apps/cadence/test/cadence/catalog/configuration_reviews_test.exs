defmodule Cadence.Catalog.ConfigurationReviewsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Catalog.ConfigurationReviews
  alias Cadence.Catalog.ConfigurationReviews.{MemberRow, SetRow}
  alias Cadence.TestSupport.DecisionRecordPurge

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("review-evidence")
    %{organization_id: other_org, mission_id: other} = configuration_mission("review-other")
    %{org: org, mission: mission, other_org: other_org, other: other}
  end

  defp items(count) do
    for n <- 1..count,
        do: %{
          id: "sc-#{n}",
          configuration_revision_id: "rev-#{n}",
          configuration_token: "tok-#{n}"
        }
  end

  defp meta(ref, base \\ nil),
    do: %{"configuration_review" => ConfigurationReviews.metadata(ref, base)}

  test "stores a review once and reads its evidence back by spacecraft", c do
    assert {:ok, %{"count" => 3} = ref} = ConfigurationReviews.store(c.org, c.mission, items(3))

    assert {:ok, ^ref} = ConfigurationReviews.store(c.org, c.mission, Enum.reverse(items(3)))
    assert Repo.aggregate(where(SetRow, mission_id: ^c.mission), :count) == 1
    assert Repo.aggregate(where(MemberRow, mission_id: ^c.mission), :count) == 3

    metadata = meta(ref, "base-1")
    assert ConfigurationReviews.count(metadata) == 3
    assert ConfigurationReviews.sha(metadata) == ref["sha256"]

    assert {:ok, ["sc-1", "sc-2", "sc-3"]} =
             ConfigurationReviews.spacecraft_ids(c.org, c.mission, metadata)

    assert {:ok, %{"sc-2" => evidence} = all} =
             ConfigurationReviews.evidence(c.org, c.mission, metadata)

    assert map_size(all) == 3

    assert evidence == %{
             "spacecraft_id" => "sc-2",
             "configuration_revision_id" => "rev-2",
             "configuration_token" => "tok-2",
             "base_activation_id" => "base-1"
           }

    assert ^evidence = ConfigurationReviews.evidence_for(c.org, c.mission, metadata, "sc-2")
    assert ConfigurationReviews.evidence_for(c.org, c.mission, metadata, "nope") == nil
  end

  test "organization_id is set from the mission on both tables", c do
    {:ok, _ref} = ConfigurationReviews.store(c.org, c.mission, items(2))

    assert [c.org] ==
             Repo.all(
               from(s in SetRow, where: s.mission_id == ^c.mission, select: s.organization_id)
             )

    assert [c.org] ==
             Repo.all(
               from(m in MemberRow,
                 where: m.mission_id == ^c.mission,
                 select: m.organization_id,
                 distinct: true
               )
             )
  end

  test "an organization that doesn't own the mission can't store a review for it (composite FK)",
       c do
    assert_raise Postgrex.Error, ~r/foreign_key_violation/, fn ->
      ConfigurationReviews.store(c.other_org, c.mission, items(1))
    end
  end

  test "a reference to another mission's review is refused, and its rows are never read", c do
    {:ok, ref} = ConfigurationReviews.store(c.other_org, c.other, items(3))

    # Another mission's own reference, read as this mission's request.
    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(c.org, c.mission, meta(ref))

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.spacecraft_ids(c.org, c.mission, meta(ref))

    assert ConfigurationReviews.evidence_for(c.org, c.mission, meta(ref), "sc-1") == nil

    # The same sha claimed under this mission's id finds nothing there.
    forged = %{ref | "mission_id" => c.mission}

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(c.org, c.mission, meta(forged))

    # And the other mission's own request under the wrong organization finds nothing.
    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(c.org, c.other, meta(ref))

    assert {:ok, %{}} = ConfigurationReviews.evidence(c.other_org, c.other, meta(ref))
  end

  test "an identical set in two missions is stored per mission", c do
    {:ok, one} = ConfigurationReviews.store(c.org, c.mission, items(2))
    {:ok, two} = ConfigurationReviews.store(c.other_org, c.other, items(2))

    assert one["sha256"] == two["sha256"]
    assert Repo.aggregate(MemberRow, :count) >= 4
    assert {:ok, [_, _]} = ConfigurationReviews.spacecraft_ids(c.org, c.mission, meta(one))
    assert {:ok, [_, _]} = ConfigurationReviews.spacecraft_ids(c.other_org, c.other, meta(two))
  end

  test "a changed token or version is a different review", c do
    {:ok, one} = ConfigurationReviews.store(c.org, c.mission, items(2))

    changed = List.update_at(items(2), 0, &%{&1 | configuration_token: "tok-new"})
    {:ok, two} = ConfigurationReviews.store(c.org, c.mission, changed)

    refute one["sha256"] == two["sha256"]
  end

  test "which of several reviews cover a spacecraft is one query", c do
    {:ok, a} = ConfigurationReviews.store(c.org, c.mission, items(2))
    {:ok, b} = ConfigurationReviews.store(c.org, c.mission, Enum.drop(items(3), 2))

    assert ConfigurationReviews.covering(c.org, c.mission, [a["sha256"], b["sha256"]], "sc-1") ==
             MapSet.new([a["sha256"]])

    assert ConfigurationReviews.covering(c.org, c.mission, [a["sha256"], b["sha256"]], "sc-3") ==
             MapSet.new([b["sha256"]])

    assert ConfigurationReviews.covering(c.other_org, c.other, [a["sha256"]], "sc-1") ==
             MapSet.new()
  end

  test "the evidence of a review is constant-size in the metadata", c do
    {:ok, ref} = ConfigurationReviews.store(c.org, c.mission, items(5))
    small = byte_size(Jason.encode!(ConfigurationReviews.metadata(ref, nil)))
    {:ok, ref} = ConfigurationReviews.store(c.org, c.mission, items(50))
    assert byte_size(Jason.encode!(ConfigurationReviews.metadata(ref, nil))) - small < 8
  end

  test "a review set has no size cap", c do
    assert {:ok, %{"count" => 2_100} = ref} =
             ConfigurationReviews.store(c.org, c.mission, items(2_100))

    assert {:ok, evidence} = ConfigurationReviews.evidence(c.org, c.mission, meta(ref))
    assert map_size(evidence) == 2_100
  end

  test "metadata without a readable reference is stale, never partial", c do
    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(c.org, c.mission, %{})

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.spacecraft_ids(c.org, c.mission, %{
               "configuration_review" => %{"spacecraft_id" => "x"}
             })

    assert ConfigurationReviews.count(%{"configuration_review" => %{"spacecraft_id" => "x"}}) ==
             nil

    unknown = %{"mission_id" => c.mission, "sha256" => "missing", "count" => 2}

    assert {:error, :spacecraft_configuration_review_stale} =
             ConfigurationReviews.evidence(c.org, c.mission, meta(unknown))
  end

  describe "the evidence an approval rests on is immutable (commanding's review, DECISIONS #107)" do
    test "the review tables and the change-set rows refuse UPDATE, DELETE and TRUNCATE", c do
      {:ok, _} = ConfigurationReviews.store(c.org, c.mission, items(2))
      {:ok, _} = Cadence.Catalog.ChangeSetSpacecraft.store(c.org, c.mission, "cs-1", 1, ["sc-1"])

      for sql <- [
            "UPDATE spacecraft_configuration_review_members SET configuration_token = 'x'",
            "DELETE FROM spacecraft_configuration_review_members",
            "TRUNCATE spacecraft_configuration_review_members",
            "UPDATE spacecraft_configuration_reviews SET spacecraft_count = 9",
            "DELETE FROM spacecraft_configuration_reviews",
            "TRUNCATE spacecraft_configuration_reviews",
            "UPDATE activation_change_set_spacecraft SET spacecraft_id = 'x'",
            "DELETE FROM activation_change_set_spacecraft",
            "TRUNCATE activation_change_set_spacecraft"
          ] do
        assert_raise Postgrex.Error, ~r/decision records are append-only/, fn ->
          Repo.transaction(fn -> Repo.query!(sql) end)
        end
      end

      assert Repo.aggregate(where(MemberRow, mission_id: ^c.mission), :count) == 2
    end

    test "a changed token or revision reads as stale, never as what was approved", c do
      {:ok, ref} = ConfigurationReviews.store(c.org, c.mission, items(3))
      metadata = meta(ref)
      assert {:ok, _} = ConfigurationReviews.evidence(c.org, c.mission, metadata)

      # Only a test database's purge setting gets past the trigger.
      {:ok, _} =
        DecisionRecordPurge.run(fn ->
          Repo.query!(
            "UPDATE spacecraft_configuration_review_members SET configuration_token = 'evil' WHERE spacecraft_id = 'sc-2'"
          )
        end)

      assert {:error, :spacecraft_configuration_review_stale} =
               ConfigurationReviews.evidence(c.org, c.mission, metadata)

      assert {:error, :spacecraft_configuration_review_stale} =
               ConfigurationReviews.spacecraft_ids(c.org, c.mission, metadata)
    end

    test "a member swapped at the same count reads as stale", c do
      {:ok, ref} = ConfigurationReviews.store(c.org, c.mission, items(3))
      metadata = meta(ref)

      {:ok, _} =
        DecisionRecordPurge.run(fn ->
          Repo.query!(
            "UPDATE spacecraft_configuration_review_members SET spacecraft_id = 'sc-other' WHERE spacecraft_id = 'sc-3'"
          )
        end)

      assert length(Repo.all(from(m in MemberRow, where: m.mission_id == ^c.mission))) == 3

      assert {:error, :spacecraft_configuration_review_stale} =
               ConfigurationReviews.evidence(c.org, c.mission, metadata)

      assert {:error, :spacecraft_configuration_review_stale} =
               ConfigurationReviews.spacecraft_ids(c.org, c.mission, metadata)
    end
  end
end
