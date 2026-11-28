defmodule Cadence.Applications.SaveTrailTest do
  @moduledoc """
  The limits and derived-telemetry save trail (director, 2026-11-16; sweep row 3): a change set's
  save records who applied it and that it came through a change set, and the trail is never
  content (no new version, no change-set diff).
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Control.LimitDefinitionKind
  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Governance
  alias Cadence.Governance.DerivedTelemetryKind
  alias Cadence.Governance.GovernedDerivedTelemetryDefinitionRow, as: DerivedRow
  alias Cadence.Limits
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Limits.GovernedLimitDefinitionRow, as: LimitRow

  @org "org-save-trail"
  @mission "mission-save-trail"
  @alice %{"kind" => "user", "id" => "trail-operator-a"}
  @bob %{"kind" => "user", "id" => "trail-operator-b"}

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  describe "limits" do
    test "a change set's write records its applier and path; its document has no trail" do
      id = create_limit!("HK.trail_a", @alice)
      assert [first] = limit_rows(id)
      assert first.metadata["saved_by"] == @alice
      assert first.metadata["via"] == "change_set"

      live = LimitDefinitionKind.load(@org, @mission, [id])[id]
      refute Map.has_key?(live["metadata"], "saved_by")
      refute Map.has_key?(live["metadata"], "via")

      proposed = put_in(live, ["thresholds", "yellow_high"], 30.5)

      assert {:ok, stored, []} =
               LimitDefinitionKind.write(@org, @mission, :update, id, live, proposed, %{})

      refute Map.has_key?(stored["metadata"], "via")
      # Before and after: the previous version stays, unchanged, beside the new one.
      assert [latest, ^first] = limit_rows(id)
      assert latest.version == 2
      assert latest.metadata["via"] == "change_set"
      refute Map.has_key?(latest.metadata, "saved_by")
    end

    test "the same version saved again by someone else, another way, is the same version" do
      id = create_limit!("HK.trail_c", @alice)

      assert {:ok, %LimitDefinition{} = first} =
               Limits.fetch_latest_limit_definition(@org, @mission, id)

      again = %{first | metadata: %{"saved_by" => @bob, "via" => "console"}}

      assert {:ok, stored} = Limits.persist_limit_definition(again, [])
      assert stored.version == 1
      assert stored.metadata["saved_by"] == @alice
      assert Enum.map(limit_rows(id), & &1.version) == [1]
    end
  end

  describe "derived telemetry" do
    test "a change set's write records its applier and path; its document has no trail" do
      create_derived!("dd_trail_a", "DERIVED.trail_a", @alice)
      assert {:ok, first} = Governance.fetch_derived_definition(@org, @mission, "dd_trail_a", nil)
      assert first.metadata["saved_by"] == @alice
      assert first.metadata["via"] == "change_set"

      live = DerivedTelemetryKind.load(@org, @mission, ["dd_trail_a"])["dd_trail_a"]
      refute Map.has_key?(live["metadata"], "saved_by")

      proposed = %{live | "expression" => "HK.voltage * 2"}

      assert {:ok, _stored, []} =
               DerivedTelemetryKind.write(
                 @org,
                 @mission,
                 :update,
                 "dd_trail_a",
                 live,
                 proposed,
                 %{}
               )

      assert {:ok, latest} =
               Governance.fetch_derived_definition(@org, @mission, "dd_trail_a", nil)

      assert latest.version == 2
      assert latest.metadata["via"] == "change_set"
      refute Map.has_key?(latest.metadata, "saved_by")
      assert derived_versions("dd_trail_a") == [2, 1]
    end

    test "the same version saved again by someone else, another way, is the same version" do
      create_derived!("dd_trail_c", "DERIVED.trail_c", @alice)

      assert {:ok, %DerivedDefinition{} = first} =
               Governance.fetch_derived_definition(@org, @mission, "dd_trail_c", nil)

      again = %DerivedDefinition{first | metadata: %{"saved_by" => @bob, "via" => "console"}}

      assert {:ok, stored} = Governance.persist_derived_definition(again)
      assert stored.metadata["saved_by"] == @alice
      assert derived_versions("dd_trail_c") == [1]
    end
  end

  defp create_limit!(point, actor) do
    proposed = %{
      "point_id" => point,
      "limit_set_name" => "DEFAULT",
      "thresholds" => %{"red_low" => 24.0, "yellow_low" => 25.5, "yellow_high" => 31.0},
      "metadata" => %{}
    }

    assert {:ok, _document, []} =
             LimitDefinitionKind.write(@org, @mission, :create, nil, nil, proposed, %{
               actor: actor
             })

    Limits.limit_definition_id(point, "DEFAULT")
  end

  defp create_derived!(id, point, actor) do
    proposed = %{
      "point_id" => point,
      "expression" => "HK.voltage * HK.current",
      "metadata" => %{}
    }

    assert {:ok, _document, []} =
             DerivedTelemetryKind.write(@org, @mission, :create, id, nil, proposed, %{
               actor: actor
             })
  end

  defp limit_rows(id),
    do:
      Repo.all(
        from(r in LimitRow,
          where: r.mission_id == ^@mission and r.limit_definition_id == ^id,
          order_by: [desc: r.version]
        )
      )

  defp derived_versions(id),
    do:
      Repo.all(
        from(r in DerivedRow,
          where: r.mission_id == ^@mission and r.derived_definition_id == ^id,
          order_by: [desc: r.version],
          select: r.version
        )
      )
end
