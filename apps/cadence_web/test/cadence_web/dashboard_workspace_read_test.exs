defmodule CadenceWeb.DashboardWorkspaceReadTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    DocumentCodec,
    Documents,
    Management,
    Placement,
    ResolutionContext,
    WidgetDef
  }

  alias Cadence.Reads.Dashboards.Workspace
  alias Cadence.Telemetry.Sample
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @checker Path.expand(
             "../../../../frontend/modules/dashboards-and-exploration/src/features/workspace/producer-contract-check.mjs",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)
    [placement] = base.placements

    placement = %{
      placement
      | widget_def: %{
          placement.widget_def
          | binding: Map.put(placement.widget_def.binding, :overlays, [])
        }
    }

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "workspace-" <> Ecto.UUID.generate(),
        placements: [placement]
    }

    assert {:ok, document} = Documents.persist(org.organization_id, document)
    parent = self()

    context =
      ResolutionContext.new!(
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_health_events?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          source_opts: %{
            telemetry: [
              latest_fun: fn org_id, mission_id, point_id, _opts ->
                send(parent, {:resolved_workspace, org_id, mission_id, point_id})

                %Sample{
                  sample_id: "sample-1",
                  mission_id: mission_id,
                  spacecraft_id: "sc_001",
                  point_id: point_id,
                  point_name: point_id,
                  packet_definition_id: "packet-1",
                  packet_definition_version: 1,
                  packet_id: "packet-1",
                  evidence_id: "evidence-1",
                  raw_value: 28.4,
                  engineering_value: 28.4,
                  quality_state: :good,
                  generation_time: ~U[2026-09-07 00:00:00Z],
                  receipt_time: ~U[2026-09-07 00:00:01Z],
                  provenance: %{secret: "must-not-leak"}
                }
              end,
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    opts = [
      resolution_context: context,
      runtime: %{scope_context: %{primary: %{kind: :spacecraft, mode: :one, ids: ["sc_001"]}}}
    ]

    %{org: org, mission: mission, scope: scope, document: document, opts: opts}
  end

  test "published viewing never falls back to an unpublished draft and reads real resolved values",
       c do
    assert {:error, :unavailable} = load(c, :view)
    refute_received {:resolved_workspace, _, _, _}
    assert {:ok, draft} = load(c, :edit)
    assert draft.document_mode == "draft"
    assert draft.document_version == 1
    assert_received {:resolved_workspace, org, mission, "tlm.hk.battery_voltage"}
    assert org == c.org.organization_id
    assert mission == c.mission.mission_id

    assert {:ok, _} =
             Documents.publish(org, mission, c.document.dashboard_id, 1, expected_version: 1)

    assert {:ok, view} = load(c, :view)
    assert view.document_mode == "published"
    assert [%{status: "ready", frames: frames}] = view.placements

    assert Enum.any?(frames, fn frame ->
             Enum.any?(
               frame.fields,
               &(&1.name == "tlm.hk.battery_voltage" and &1.values == [28.4])
             )
           end)

    refute Jason.encode!(view) =~ "must-not-leak"

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!([draft, view])],
               stderr_to_stdout: true
             )

    assert output =~ "contract passed"
  end

  test "draft edits cannot replace the published viewer version", c do
    org = c.org.organization_id
    mission = c.mission.mission_id
    id = c.document.dashboard_id
    assert {:ok, _} = Documents.publish(org, mission, id, 1, expected_version: 1)

    assert {:ok, _} =
             Documents.update(org, mission, id, %{c.document | name: "Draft only"},
               expected_version: 1
             )

    assert {:ok, %{document_version: 1, name: "Power Latest"}} = load(c, :view)
    assert {:ok, %{document_version: 2, name: "Draft only"}} = load(c, :edit)
  end

  test "revoked, mismatched, invalid and cross-organization requests never execute sources", c do
    foreign_org = TestFixtures.persist_org!()
    foreign_mission = TestFixtures.persist_mission!(foreign_org)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "other"},
          %{c.scope | organization_id: foreign_org.organization_id}
        ] do
      assert {:error, :unavailable} =
               Workspace.load(scope, c.mission.mission_id, c.document.dashboard_id, :edit, c.opts)
    end

    assert {:error, :unavailable} =
             Workspace.load(
               c.scope,
               foreign_mission.mission_id,
               c.document.dashboard_id,
               :edit,
               c.opts
             )

    assert {:error, :unavailable} =
             Workspace.load(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               :other,
               c.opts
             )

    assert {:error, :unavailable} =
             Workspace.load(
               c.scope,
               c.mission.mission_id,
               String.duplicate("x", 257),
               :edit,
               c.opts
             )

    refute_received {:resolved_workspace, _, _, _}
  end

  test "library-backed rendering uses the hydrated definition and preserves unavailable references",
       c do
    [source] = c.document.placements

    assert {:ok, item} =
             Management.create_library_item(c.org.organization_id, c.mission.mission_id, %{
               name: "Library voltage",
               widget_definition: WidgetDef.to_map(source.widget_def)
             })

    id = item.dashboard_library_item_id

    placements = [
      %Placement{
        placement_id: "library",
        content_kind: :library,
        library_widget_id: id,
        library_version: 1
      },
      %Placement{
        placement_id: "missing",
        content_kind: :library,
        library_widget_id: "missing-library",
        library_version: 1
      }
    ]

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | placements: placements},
               expected_version: 1
             )

    assert {:ok, %{placements: [library, missing]}} = load(c, :edit)
    assert library.status == "ready"
    assert library.widget.title == source.widget_def.title
    assert missing.id == "missing"
    assert missing.status == "unavailable"
    assert missing.reason == "unsupported_widget"
  end

  defp load(c, mode),
    do: Workspace.load(c.scope, c.mission.mission_id, c.document.dashboard_id, mode, c.opts)
end
