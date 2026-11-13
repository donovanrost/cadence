defmodule Cadence.Reads.Readiness.RulesTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.Readiness.Rules

  defp facts(overrides) do
    Map.merge(
      %{
        fleet: %{
          total: 500,
          missing_scid: 0,
          missing_profile: 0,
          without_routing: 0,
          drifted: 0,
          drifted_profile_ids: [],
          profile_count: 1
        },
        catalog: %{database_count: 1, revision_count: 3, latest_label: "Latest r3"},
        comms: %{transport_count: 2, routing_rule_count: 500},
        stations: %{count: 4},
        data_sources: %{statuses: [%{data_source_id: "qdb", health: :healthy}]},
        apps: %{installed_count: 1, available_count: 1, missing: []}
      },
      overrides
    )
  end

  defp area(result, key), do: Enum.find(result.areas, &(&1.key == key))

  test "a fully set-up mission is ready everywhere with no findings" do
    result = Rules.build(facts(%{}))

    assert Enum.map(result.areas, & &1.key) ==
             [:fleet, :catalog, :comms, :stations, :data_sources, :apps]

    statuses = Map.new(result.areas, &{&1.key, &1.status})
    assert statuses.stations == :unknown
    assert statuses |> Map.delete(:stations) |> Map.values() |> Enum.all?(&(&1 == :ready))
    assert area(result, :fleet).secondary_unit == "profile"
    assert area(result, :stations).unit == "stations"
    assert result.findings == []
    assert result.verdict == %{blocker: 0, caution: 0, stale: 0, not_set_up: 0, optional: 0}
    assert area(result, :fleet).detail =~ "Every spacecraft"
  end

  test "an empty mission blocks on spacecraft and catalog" do
    result =
      Rules.build(
        facts(%{
          fleet: %{facts(%{}).fleet | total: 0, profile_count: 0},
          catalog: %{database_count: 0, revision_count: 0, latest_label: nil}
        })
      )

    assert area(result, :fleet).status == :blocker
    assert area(result, :fleet).count == 0
    assert area(result, :catalog).status == :blocker

    assert [
             %{cause: :no_spacecraft, fix: %{kind: :spacecraft_new}},
             %{cause: :no_catalog, fix: %{kind: :catalog_import}}
           ] =
             result.findings
  end

  test "groups fleet problems by cause with counts and typed fixes, worst first" do
    fleet = %{
      facts(%{}).fleet
      | without_routing: 12,
        missing_scid: 2,
        drifted: 3,
        drifted_profile_ids: ["prof-1"]
    }

    result = Rules.build(facts(%{fleet: fleet}))

    assert [
             %{cause: :spacecraft_missing_scid, severity: :blocker, affected_count: 2},
             %{
               cause: :spacecraft_without_routing_rule,
               severity: :blocker,
               affected_count: 12,
               title: "12 spacecraft have no routing rule"
             },
             %{
               cause: :spacecraft_on_older_profile_version,
               severity: :caution,
               fix: %{kind: :profile, id: "prof-1"}
             }
           ] = result.findings

    assert area(result, :fleet).status == :blocker
    assert result.verdict.blocker == 2
  end

  test "missing Limits is not_set_up and degrades apps; other apps are optional" do
    result =
      Rules.build(
        facts(%{
          apps: %{
            installed_count: 0,
            available_count: 2,
            missing: [
              %{key: "limits", name: "Limits & Alarming", description: nil},
              %{key: "derived", name: "Derived telemetry", description: "Computes points"}
            ]
          }
        })
      )

    assert area(result, :apps).status == :not_set_up

    assert area(result, :apps).detail ==
             "Limits & Alarming and Derived telemetry aren't installed"

    assert Enum.map(result.findings, &{&1.cause, &1.severity}) == [
             {:"app_not_installed:limits", :not_set_up},
             {:"app_not_installed:derived", :optional}
           ]
  end

  test "optional findings never degrade an area; unknown data sources are unknown" do
    result =
      Rules.build(
        facts(%{
          apps: %{
            installed_count: 0,
            available_count: 1,
            missing: [
              %{key: "derived", name: "Derived telemetry", description: "Computes points"}
            ]
          },
          data_sources: %{statuses: []}
        })
      )

    assert area(result, :apps).status == :ready
    assert area(result, :data_sources).status == :unknown
    assert area(result, :data_sources).count == nil
    assert [%{severity: :optional, fix: %{kind: :app, id: "derived"}}] = result.findings
  end

  test "contact planning not set up is a not_set_up finding without its own area" do
    result =
      Rules.build(facts(%{planning: %{ready: false, missing: ["fleet_planning_policy"]}}))

    assert length(result.areas) == 6

    assert [
             %{
               cause: :planning_not_set_up,
               severity: :not_set_up,
               fix: %{kind: :contact_planning}
             }
           ] =
             result.findings

    assert Rules.build(facts(%{planning: %{ready: true, missing: []}})).findings == []
  end

  test "degraded and unavailable data sources are separate causes" do
    statuses = [
      %{data_source_id: "a", health: :degraded},
      %{data_source_id: "b", health: :unavailable},
      %{data_source_id: "c", health: :healthy}
    ]

    result = Rules.build(facts(%{data_sources: %{statuses: statuses}}))

    assert area(result, :data_sources).status == :blocker

    assert Enum.map(result.findings, & &1.cause) == [
             :data_source_unavailable,
             :data_source_degraded
           ]

    assert hd(result.findings).fix == %{kind: :data_source, id: "b", label: nil}
  end

  test "spacecraft not yet on their profile's catalog are a caution with the list (DECISIONS #65)" do
    mismatch = %{
      spacecraft_id: "spacecraft-004",
      effective_catalog_revision_id: "catalog-r5",
      configured_catalog_revision_id: "catalog-r4"
    }

    result =
      Rules.build(
        facts(%{
          catalog: %{
            database_count: 1,
            revision_count: 5,
            latest_label: "Latest r5",
            not_converged: [mismatch]
          }
        })
      )

    assert [
             %{
               id: "catalog.catalog_not_converged",
               severity: :caution,
               affected_count: 1,
               affected: [^mismatch],
               fix: %{kind: :change_set}
             }
           ] = Enum.filter(result.findings, &(&1.area == :catalog))
  end

  test "a spacecraft whose telemetry endpoint can't be derived is a caution pointing to Data sources (L22)" do
    ambiguous = %{spacecraft_id: "spacecraft-007", source_endpoint_ids: ["ep-a", "ep-b"]}

    result =
      Rules.build(
        facts(%{
          data_sources: %{
            statuses: [%{data_source_id: "qdb", health: :healthy}],
            ambiguous_endpoints: [ambiguous]
          }
        })
      )

    assert [
             %{
               id: "data_sources.source_endpoint_ambiguous",
               severity: :caution,
               affected_count: 1,
               affected: [^ambiguous],
               fix: %{kind: :data_source, id: nil}
             }
           ] = Enum.filter(result.findings, &(&1.area == :data_sources))
  end
end
