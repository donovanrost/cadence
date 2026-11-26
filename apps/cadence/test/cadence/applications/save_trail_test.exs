defmodule Cadence.Applications.SaveTrailTest do
  @moduledoc """
  The limits and derived-telemetry save trail (director, 2026-11-16; sweep row 3): every save
  records who saved it and through which path, a save without a path is refused, and the trail is
  never content (no new version, no change-set diff).
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationInstallations,
    HostContext
  }

  alias Cadence.Auth.Scope
  alias Cadence.Control.LimitDefinitionKind
  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Governance
  alias Cadence.Governance.DerivedTelemetryKind
  alias Cadence.Governance.GovernedDerivedTelemetryDefinitionRow, as: DerivedRow
  alias Cadence.Limits
  alias Cadence.Limits.GovernedLimitDefinitionRow, as: LimitRow

  @org "org-save-trail"
  @mission "mission-save-trail"

  setup do
    persist_mission_scope(@org, @mission)
    scope = scope("trail-operator-a")
    host = HostContext.mission(@mission)

    for app <- ["limits", "derived_telemetry"],
        do: assert({:ok, _} = ApplicationInstallations.install(scope, host, app))

    %{scope: scope, host: host}
  end

  describe "limits save_limit_definition" do
    test "records the actor and the path", c do
      assert {:ok, first} = dispatch(c, limit_request(:console, "HK.trail_a"))
      assert first.metadata["saved_by"] == %{"kind" => "user", "id" => "trail-operator-a"}
      assert first.metadata["via"] == "console"
      assert first.metadata["application"] == "limits"

      other = %{c | scope: scope("trail-operator-b")}
      assert {:ok, second} = dispatch(other, limit_request(:console, "HK.trail_a", first))
      assert second.version == 2
      assert second.metadata["saved_by"] == %{"kind" => "user", "id" => "trail-operator-b"}
      assert second.metadata["via"] == "console"

      # Before and after: the previous version stays, unchanged, beside the new one.
      assert [2, 1] == limit_versions(first.limit_definition_id)
    end

    test "a save without a path is refused and writes nothing", c do
      assert {:error, :action_origin_required} = dispatch(c, limit_request(nil, "HK.trail_b"))
      assert limit_versions(Limits.limit_definition_id("HK.trail_b", "DEFAULT")) == []
    end

    test "the same version saved again by someone else, another way, is the same version", c do
      assert {:ok, first} = dispatch(c, limit_request(:console, "HK.trail_c"))

      again = %{
        first
        | metadata: %{
            "application" => "limits",
            "saved_by" => %{"kind" => "user", "id" => "trail-operator-b"},
            "via" => "change_set"
          }
      }

      assert {:ok, stored} = Limits.persist_limit_definition(again, [])
      assert stored.version == 1
      assert stored.metadata["saved_by"]["id"] == "trail-operator-a"
      assert limit_versions(first.limit_definition_id) == [1]
    end
  end

  describe "derived telemetry save_definition" do
    test "records the actor and the path", c do
      assert {:ok, first} = dispatch(c, derived_request(:console, "DERIVED.trail_a"))
      assert first.metadata["saved_by"] == %{"kind" => "user", "id" => "trail-operator-a"}
      assert first.metadata["via"] == "console"

      assert {:ok, second} = dispatch(c, derived_request(:console, "DERIVED.trail_a", first))
      assert second.version == 2
      assert second.metadata["via"] == "console"
      assert [2, 1] == derived_versions(first.derived_definition_id)
    end

    test "a save without a path is refused and writes nothing", c do
      assert {:error, :action_origin_required} =
               dispatch(c, derived_request(nil, "DERIVED.trail_b"))

      assert Repo.aggregate(where(DerivedRow, point_id: "DERIVED.trail_b"), :count) == 0
    end

    test "the same version saved again by someone else, another way, is the same version", c do
      assert {:ok, %DerivedDefinition{} = first} =
               dispatch(c, derived_request(:console, "DERIVED.trail_c"))

      again = %DerivedDefinition{
        first
        | metadata: %{
            "application" => "derived_telemetry",
            "saved_by" => %{"kind" => "user", "id" => "trail-operator-b"},
            "via" => "change_set"
          }
      }

      assert {:ok, stored} = Governance.persist_derived_definition(again)
      assert stored.metadata["saved_by"]["id"] == "trail-operator-a"
      assert derived_versions(first.derived_definition_id) == [1]
    end
  end

  describe "change-set kinds" do
    test "limits: a change set's write says via change_set, and its document has no trail", c do
      assert {:ok, first} = dispatch(c, limit_request(:console, "HK.trail_d"))
      id = first.limit_definition_id

      live = LimitDefinitionKind.load(@org, @mission, [id])[id]
      refute Map.has_key?(live["metadata"], "saved_by")
      refute Map.has_key?(live["metadata"], "via")

      proposed = put_in(live, ["thresholds", "yellow_high"], 30.5)

      assert {:ok, stored, []} =
               LimitDefinitionKind.write(@org, @mission, :update, id, live, proposed, %{})

      refute Map.has_key?(stored["metadata"], "via")
      assert [latest | _] = limit_rows(id)
      assert latest.metadata["via"] == "change_set"
      refute Map.has_key?(latest.metadata, "saved_by")
    end

    test "derived: a change set's write says via change_set, and its document has no trail", c do
      assert {:ok, first} = dispatch(c, derived_request(:console, "DERIVED.trail_d"))
      id = first.derived_definition_id

      live = DerivedTelemetryKind.load(@org, @mission, [id])[id]
      refute Map.has_key?(live["metadata"], "saved_by")

      proposed = %{live | "expression" => "HK.voltage * 2"}

      assert {:ok, _stored, []} =
               DerivedTelemetryKind.write(@org, @mission, :update, id, live, proposed, %{})

      assert {:ok, latest} = Governance.fetch_derived_definition(@org, @mission, id, nil)
      assert latest.version == 2
      assert latest.metadata["via"] == "change_set"
      refute Map.has_key?(latest.metadata, "saved_by")
    end
  end

  defp scope(user_id),
    do: %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: user_id},
      organization_membership: %{lifecycle_state: :active}
    }

  defp dispatch(c, request), do: ActionDispatcher.dispatch(c.scope, c.host, request)

  defp limit_request(origin, point, previous \\ nil),
    do: %ActionRequest{
      application_key: "limits",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_limit_definition",
      origin: origin,
      params:
        Map.merge(limit_review(point, previous), %{
          "point_id" => point,
          "red_low" => "24.0",
          "yellow_low" => "25.5",
          "yellow_high" => "31.0",
          "red_high" => "32.5"
        })
    }

  defp limit_review(_point, nil),
    do: %{
      "expected_definition_id" => nil,
      "expected_version" => 0,
      "expected_activation_event_id" => nil
    }

  defp limit_review(point, previous),
    do: %{
      "expected_definition_id" => previous.limit_definition_id,
      "expected_version" => previous.version,
      "expected_activation_event_id" =>
        Limits.limit_definition_review(@org, @mission, point, "DEFAULT").activation_event_id
    }

  defp derived_request(origin, point, previous \\ nil),
    do: %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      origin: origin,
      params: %{
        "expected_version" => (previous && previous.version) || 0,
        "expected_definition_id" => previous && previous.derived_definition_id,
        "point_id" => point,
        "expression" => "HK.voltage * HK.current"
      }
    }

  defp limit_rows(id),
    do:
      Repo.all(
        from(r in LimitRow,
          where: r.mission_id == ^@mission and r.limit_definition_id == ^id,
          order_by: [desc: r.version]
        )
      )

  defp limit_versions(id), do: Enum.map(limit_rows(id), & &1.version)

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
