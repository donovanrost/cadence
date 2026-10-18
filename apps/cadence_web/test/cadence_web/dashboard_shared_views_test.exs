defmodule CadenceWeb.DashboardSharedViewsTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Document,
    DocumentCodec,
    Documents,
    Management,
    ResolutionContext,
    SharedViewContext,
    WidgetDef
  }

  alias Cadence.Reads.Dashboards.SharedViews
  alias Cadence.Telemetry.Sample
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @checker Path.expand(
             "../../../../frontend/modules/dashboards-and-exploration/src/features/sharing/producer-contract-check.mjs",
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

    {:ok, document} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "shared-view-dashboard",
          placements: [placement]
      })

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
              latest_fun: fn org_id, mission_id, point, opts ->
                send(parent, {:shared_source, org_id, mission_id, point, opts})

                %Sample{
                  sample_id: "sample-1",
                  mission_id: mission_id,
                  spacecraft_id: "sc_001",
                  point_id: point,
                  point_name: point,
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

    %{
      org: org.organization_id,
      mission: mission.mission_id,
      user: user,
      scope: scope,
      document: document,
      opts: [resolution_context: context],
      conn: TestFixtures.member_conn(user)
    }
  end

  test "shares follow published definitions, never an unpublished or newer draft", c do
    {:ok, share} =
      Management.create_share(c.org, c.mission, c.document.dashboard_id, %{
        "spacecraft_id" => "sc_001"
      })

    assert {:ok, %{definition: nil, canvas: nil}} = load(c, :share, share.dashboard_share_id)
    refute_received {:shared_source, _, _, _, _}
    {:ok, _} = Documents.publish(c.org, c.mission, c.document.dashboard_id, 1, [])
    assert {:ok, model} = load(c, :share, share.dashboard_share_id)
    assert model.definition.version == 1
    assert model.canvas.document_mode == "published"
    refute model.canvas.author
    assert model.canvas.context.scope_ids == ["sc_001"]
    assert_received {:shared_source, org, mission, "tlm.hk.battery_voltage", _}
    assert {org, mission} == {c.org, c.mission}

    assert Enum.any?(hd(model.canvas.placements).frames, fn frame ->
             Enum.any?(frame.fields, &(&1.values == [28.4]))
           end)

    refute Jason.encode!(model) =~ "must-not-leak"

    {:ok, _} =
      Documents.update(
        c.org,
        c.mission,
        c.document.dashboard_id,
        %{c.document | name: "Unpublished change"},
        expected_version: 1
      )

    assert {:ok, %{definition: %{version: 1, name: "Power Latest"}}} =
             load(c, :share, share.dashboard_share_id)
  end

  test "definition-only views never resolve runtime sources and snapshots retain the exact version after archive",
       c do
    {:ok, snapshot} =
      Management.create_snapshot(c.org, c.mission, c.document, %{},
        data_visibility: "definition_only"
      )

    {:ok, share} =
      Management.create_share(c.org, c.mission, c.document.dashboard_id, %{},
        data_visibility: "definition_only"
      )

    {:ok, _} = Documents.publish(c.org, c.mission, c.document.dashboard_id, 1, [])
    assert {:ok, shared} = load(c, :share, share.dashboard_share_id)
    assert shared.canvas == nil
    assert {:ok, captured} = load(c, :snapshot, snapshot.dashboard_snapshot_id)
    assert captured.canvas == nil
    expected = Jason.decode!(captured.definition.json)
    assert expected == Jason.decode!(Jason.encode!(Document.to_map(c.document)))

    {:ok, _} =
      Documents.update(
        c.org,
        c.mission,
        c.document.dashboard_id,
        %{c.document | name: "Later draft"},
        expected_version: 1
      )

    :ok = Documents.archive(c.org, c.mission, c.document.dashboard_id, expected_version: 2)
    assert {:ok, after_archive} = load(c, :snapshot, snapshot.dashboard_snapshot_id)
    assert after_archive.definition == captured.definition
    assert {:ok, %{definition: nil, canvas: nil}} = load(c, :share, share.dashboard_share_id)
    refute_received {:shared_source, _, _, _, _}
  end

  test "persisted producers render through the actual Vue contribution, including runtime snapshots",
       c do
    {:ok, share} =
      Management.create_share(c.org, c.mission, c.document.dashboard_id, %{},
        data_visibility: "definition_only"
      )

    {:ok, unpublished} = load(c, :share, share.dashboard_share_id)
    {:ok, _} = Documents.publish(c.org, c.mission, c.document.dashboard_id, 1, [])
    {:ok, shared} = load(c, :share, share.dashboard_share_id)

    {:ok, snapshot} =
      Management.create_snapshot(c.org, c.mission, c.document, %{"spacecraft_id" => "sc_001"}, [])

    {:ok, runtime} = load(c, :snapshot, snapshot.dashboard_snapshot_id)
    assert runtime.canvas.document_mode == "snapshot"
    refute runtime.canvas.author
    assert runtime.canvas.document_version == 1

    {:ok, fixed} =
      Management.create_snapshot(
        c.org,
        c.mission,
        c.document,
        %{"from" => "2026-09-07T00:00:00Z", "to" => "2026-09-07T01:00:00Z"},
        data_visibility: "definition_only"
      )

    {:ok, fixed_view} = load(c, :snapshot, fixed.dashboard_snapshot_id)
    assert fixed_view.data_semantics == "frozen_time_window"

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               [
                 "--no-warnings",
                 @checker,
                 Jason.encode!([unpublished, shared, runtime, fixed_view])
               ],
               stderr_to_stdout: true
             )

    assert output =~ "shared view contract passed"
  end

  test "invalid scopes, expired/revoked shares and forged snapshot identity return no data", c do
    {:ok, share} = Management.create_share(c.org, c.mission, c.document.dashboard_id, %{})

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: "foreign"}
        ] do
      assert {:error, :unavailable} =
               SharedViews.load(scope, c.mission, :share, share.dashboard_share_id, c.opts)
    end

    {:ok, share} =
      share
      |> Ecto.Changeset.change(expires_at: ~U[2020-01-01 00:00:00.000000Z])
      |> Cadence.Repo.update()

    assert {:error, :unavailable} = load(c, :share, share.dashboard_share_id)
    {:ok, _} = Management.revoke_share(c.org, c.mission, share.dashboard_share_id)
    assert {:error, :unavailable} = load(c, :share, share.dashboard_share_id)

    {:ok, snapshot} =
      Management.create_snapshot(c.org, c.mission, c.document, %{},
        data_visibility: "definition_only"
      )

    for {key, value} <- [
          {"mission_id", "foreign"},
          {"organization_id", "foreign"},
          {"dashboard_id", "foreign"},
          {"metadata", %{"version" => 99}}
        ] do
      original = Jason.decode!(Jason.encode!(snapshot.document))

      {:ok, _} =
        snapshot
        |> Ecto.Changeset.change(document: Map.put(original, key, value))
        |> Cadence.Repo.update()

      assert {:error, :unavailable} = load(c, :snapshot, snapshot.dashboard_snapshot_id)
    end

    refute_received {:shared_source, _, _, _, _}
  end

  test "stored context is finite, preserves defaults and admits exact immutable windows", c do
    assert {:ok, %{time_context: %{}, scope_context: %{}}} =
             SharedViewContext.admit(%{}, c.mission)

    for bad <- [
          %{"realm" => "public"},
          %{"scope_kind" => "mission", "scope_id" => "foreign"},
          %{"spacecraft_id" => "one", "scope_id" => "two"},
          %{"from" => "bad", "to" => "bad"},
          %{"time_mode" => "live", "from" => "2026-09-07T00:00:00Z"},
          %{"component" => "Forged"},
          %{"selected_target" => "point"}
        ] do
      assert {:error, :invalid_context} = SharedViewContext.admit(bad, c.mission)
    end

    assert {:ok, %{time_context: %{mode: "range", from: from, to: to}}} =
             SharedViewContext.admit(
               %{"from" => "2026-09-07T00:00:00.000001Z", "to" => "2026-09-07T00:00:00.000002Z"},
               c.mission
             )

    assert DateTime.diff(to, from, :microsecond) == 1
  end

  test "snapshot library references remain pinned when a newer library version is added", c do
    [placement] = c.document.placements
    widget = placement.widget_def

    {:ok, item} =
      Management.create_library_item(c.org, c.mission, %{
        "name" => "Pinned widget",
        "widget_definition" => WidgetDef.to_map(widget)
      })

    placement = %{
      placement
      | content_kind: :library,
        widget_def: nil,
        library_widget_id: item.dashboard_library_item_id,
        library_version: 1
    }

    {:ok, document} =
      Documents.update(
        c.org,
        c.mission,
        c.document.dashboard_id,
        %{c.document | placements: [placement]},
        expected_version: 1
      )

    {:ok, captured} =
      Management.create_snapshot(c.org, c.mission, document, %{"spacecraft_id" => "sc_001"}, [])

    {:ok, before} = load(c, :snapshot, captured.dashboard_snapshot_id)

    changed = %{widget | title: "Later library title"}

    {:ok, _} =
      Management.add_library_version(
        c.org,
        c.mission,
        item.dashboard_library_item_id,
        WidgetDef.to_map(changed),
        expected_version: 1
      )

    {:ok, after_update} = load(c, :snapshot, captured.dashboard_snapshot_id)
    assert after_update.definition == before.definition
    assert hd(after_update.canvas.placements).widget == hd(before.canvas.placements).widget
    assert after_update.canvas.document_version == 2
  end

  test "host refresh reauthorizes and removes revoked shares while query identities cannot redirect reads",
       c do
    {:ok, share} =
      Management.create_share(c.org, c.mission, c.document.dashboard_id, %{},
        data_visibility: "definition_only"
      )

    path = "/missions/#{c.mission}/ops/dashboard-shares/#{share.dashboard_share_id}"
    {:ok, view, _} = live(c.conn, path <> "?share_id=foreign&mission_id=foreign&realm=simulation")
    assert page(view)["status"] == "ready"
    assert page(view)["context"]["resourceId"] == share.dashboard_share_id
    assert page(view)["data"]["runtime_context"] == %{}
    {:ok, _} = Management.revoke_share(c.org, c.mission, share.dashboard_share_id)
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
    assert page(view)["status"] == "unavailable"
    refute Map.has_key?(page(view), "data")
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path})
    assert_redirect(view, "/sign-in")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
  end

  defp load(c, kind, id), do: SharedViews.load(c.scope, c.mission, kind, id, c.opts)

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
end
