defmodule CadenceWeb.DashboardExplorationReadTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.{DocumentCodec, Documents, ResolutionContext}
  alias Cadence.Reads.Dashboards.{Exploration, ExplorationSnapshot, Workspace}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.Sample
  alias CadenceWeb.TestFixtures

  @checker Path.expand(
             "../../../../frontend/modules/dashboards-and-exploration/src/features/exploration/producer-contract-check.mjs",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    parent = self()

    sample = %Sample{
      sample_id: "sample-a",
      mission_id: mission.mission_id,
      spacecraft_id: spacecraft.spacecraft_id,
      point_id: "voltage",
      point_name: "voltage",
      raw_value: 42,
      engineering_value: 4.2,
      quality_state: :good,
      provenance: %{secret: "must-not-reach-browser"},
      receipt_time: ~U[2026-09-07 12:00:00.123456Z],
      generation_time: ~U[2026-09-07 11:59:59.654321Z]
    }

    context =
      ResolutionContext.new!(
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_health_events?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          source_opts: %{
            telemetry: [
              latest_fun: fn org, mission, point, opts ->
                send(parent, {:read_explore, :latest, org, mission, point, opts})
                sample
              end,
              history_fun: fn org, mission, point, opts ->
                send(parent, {:read_explore, :history, org, mission, point, opts})
                {:ok, [sample]}
              end,
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    %{
      org: org.organization_id,
      mission: mission.mission_id,
      scope: scope,
      spacecraft: spacecraft.spacecraft_id,
      opts: [resolution_context: context, now: ~U[2026-09-07 12:01:00Z]]
    }
  end

  test "authorized unsaved history executes the scoped adapter with the admitted window", c do
    params = %{
      "point_id" => "voltage",
      "spacecraft_id" => c.spacecraft,
      "time_mode" => "last_15m",
      "limit" => "7",
      "order" => "desc",
      "sample_id" => "sample-a",
      "selected_time" => "2026-09-07T12:00:00.123456Z"
    }

    assert {:ok, read} = load(c, params)
    assert read.query == params
    assert read.request.document.metadata == %{ephemeral: true}
    assert_received {:read_explore, :history, org, mission, "voltage", opts}
    assert org == c.org and mission == c.mission
    assert opts[:spacecraft_id] == c.spacecraft
    assert opts[:limit] == 7 and opts[:order] == :desc
    assert opts[:from_receipt_time] == ~U[2026-09-07 11:46:00Z]
    assert opts[:to_receipt_time] == ~U[2026-09-07 12:01:00Z]
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, field] = frame.fields
    assert time.values == [~U[2026-09-07 12:00:00.123456Z]]
    assert field.values == [4.2]
    assert field.metadata.sample_ids == ["sample-a"]
  end

  test "preparation retains the effective query without executing sources or creating documents",
       c do
    params = %{
      "point_id" => "voltage",
      "spacecraft_id" => c.spacecraft,
      "time_mode" => "last_1h",
      "time_axis" => "generation_time",
      "data_view" => "all_revisions",
      "validity_state" => "conflict",
      "limit_mode" => "compare",
      "limit" => "7",
      "order" => "asc",
      "source_dashboard_id" => "origin",
      "sample_id" => "sample-a",
      "selected_time" => "2026-09-07T12:00:00.123456Z",
      "selected_data_source_id" => "inspection-only-source",
      "selected_source_binding_id" => "inspection-only-binding"
    }

    before = Cadence.Dashboards.list_dashboard_summaries(c.org, c.mission)
    assert {:ok, prepared} = Exploration.prepare(c.scope, c.mission, params, c.opts)

    assert prepared.context.query ==
             params |> Map.delete("data_view") |> Map.put("selection_view", "all_revisions")

    assert prepared.context.time.from == ~U[2026-09-07 11:01:00Z]
    assert prepared.context.time.to == ~U[2026-09-07 12:01:00Z]
    assert prepared.request.time_context.axis == "generation_time"
    assert prepared.request.scope_context.spacecraft_id == c.spacecraft
    assert prepared.request.data_context.view == "all_revisions"
    assert prepared.request.data_context.validity_state == "conflict"
    assert prepared.request.limit_context.semantics_mode == "compare"
    assert prepared.request.interaction_context.source_query == %{max_raw_points: 7, order: :asc}
    assert prepared.request.data_context.data_source_id == nil
    assert prepared.request.data_context.source_binding_id == nil
    assert prepared.request.document.defaults == %{}
    assert prepared.request.document.metadata == %{ephemeral: true}
    refute Map.has_key?(prepared, :result)
    refute Map.has_key?(prepared, :selected_sample)
    assert Cadence.Dashboards.list_dashboard_summaries(c.org, c.mission) == before
    refute_received {:read_explore, _, _, _, _, _}

    assert {:ok, read} = load(c, params)
    assert read.request == prepared.request
    assert read.query == prepared.context.query
    assert_received {:read_explore, :history, _, _, _, _}
  end

  test "preparation is not execution availability or a retained authorization grant", c do
    params = %{
      "point_id" => "voltage",
      "time_mode" => "replay_run",
      "from" => "2026-09-07T11:00:00.123456Z",
      "to" => "2026-09-07T12:00:00.654321Z",
      "replay_run_id" => "run-a",
      "source_binding_id" => "missing-binding",
      "data_source_id" => "missing-source"
    }

    # Preparation must not even acquire the runtime composition or read an adapter.
    opts = Keyword.put(c.opts, :resolution_context, :not_an_execution_context)
    assert {:ok, prepared} = Exploration.prepare(c.scope, c.mission, params, opts)
    assert prepared.request.data_context.realm == "replay"
    assert prepared.request.data_context.replay_run_id == "run-a"
    assert prepared.request.data_context.source_binding_id == "missing-binding"
    assert prepared.request.data_context.data_source_id == "missing-source"
    assert prepared.request.time_context.from == ~U[2026-09-07 11:00:00.123456Z]
    assert prepared.request.time_context.to == ~U[2026-09-07 12:00:00.654321Z]
    revoked = %{c.scope | organization_membership: nil}
    assert {:error, :unavailable} = Exploration.prepare(revoked, c.mission, params, c.opts)
    assert {:error, :unavailable} = Exploration.load(revoked, c.mission, params, c.opts)

    assert {:error, :invalid_exploration_context} =
             Exploration.load(c.scope, c.mission, prepared, c.opts)

    refute_received {:read_explore, _, _, _, _, _}
  end

  test "latest executes a current-value read without needing a saved dashboard", c do
    assert {:ok, read} = load(c, %{"point_id" => "voltage"})
    assert_received {:read_explore, :latest, _, _, "voltage", _}
    refute_received {:read_explore, :history, _, _, _, _}
    assert [frame] = read.result.frames_by_placement["exploration"].primary
    assert frame.shape == :scalar
  end

  test "real authorized snapshots validate and render through the feature public entry", c do
    dashboard = dashboard(c)

    assert {:ok, _} =
             Documents.publish(c.org, c.mission, dashboard.dashboard_id, 1, expected_version: 1)

    models =
      for params <- [
            %{},
            %{"source_dashboard_id" => dashboard.dashboard_id},
            %{"source_dashboard_id" => "missing", "point_id" => "voltage"},
            %{"point_id" => "voltage"},
            %{"point_id" => "voltage", "time_mode" => "last_15m", "sample_id" => "sample-a"},
            %{"point_id" => "voltage", "source_binding_id" => "missing"},
            %{"point_id" => "metric", "logical_source" => "operational_observables"},
            %{"point_id" => "voltage", "scope_kind" => "transport", "scope_id" => "transport"}
          ] do
        assert {:ok, model} = ExplorationSnapshot.load(c.scope, c.mission, params, c.opts)
        refute Jason.encode!(model) =~ "must-not-reach-browser"
        model
      end

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!(models)],
               stderr_to_stdout: true
             )

    assert output =~ "Vue renderer contract passed"
  end

  test "origin reads published metadata without executing widgets and never falls back to drafts",
       c do
    dashboard = dashboard(c)
    params = %{"source_dashboard_id" => dashboard.dashboard_id}
    assert {:ok, model} = ExplorationSnapshot.load(c.scope, c.mission, params, c.opts)
    assert model.origin == %{status: "unavailable", dashboard: nil}

    assert {:ok, _} =
             Documents.publish(c.org, c.mission, dashboard.dashboard_id, 1, expected_version: 1)

    assert {:ok, model} = ExplorationSnapshot.load(c.scope, c.mission, params, c.opts)

    assert model.origin == %{
             status: "ready",
             dashboard: %{id: dashboard.dashboard_id, name: dashboard.name}
           }

    assert model.query == params
    assert model.status == "point_required"
    assert model.version == 3

    assert {:ok, _} =
             Documents.update(
               c.org,
               c.mission,
               dashboard.dashboard_id,
               %{dashboard | name: "Unpublished secret name"},
               expected_version: 1
             )

    assert {:ok, refreshed} = ExplorationSnapshot.load(c.scope, c.mission, params, c.opts)
    assert refreshed.origin == model.origin
    refute Jason.encode!(refreshed) =~ "Unpublished secret name"
    refute_received {:read_explore, _, _, _, _, _}
  end

  test "foreign, missing and archived origins do not erase observations or expose dashboard metadata",
       c do
    dashboard = dashboard(c)

    assert {:ok, _} =
             Documents.publish(c.org, c.mission, dashboard.dashboard_id, 1, expected_version: 1)

    assert :ok = Documents.archive(c.org, c.mission, dashboard.dashboard_id, [])
    foreign_org = TestFixtures.persist_org!()
    foreign_mission = TestFixtures.persist_mission!(foreign_org)
    foreign = dashboard(%{org: foreign_org.organization_id, mission: foreign_mission.mission_id})
    same_org_mission = TestFixtures.persist_mission!(%{organization_id: c.org})
    other_mission = dashboard(%{org: c.org, mission: same_org_mission.mission_id})

    for document <- [foreign, other_mission] do
      assert {:ok, _} =
               Documents.publish(
                 document.organization_id,
                 document.mission_id,
                 document.dashboard_id,
                 1,
                 expected_version: 1
               )
    end

    for id <- [
          dashboard.dashboard_id,
          foreign.dashboard_id,
          other_mission.dashboard_id,
          "missing"
        ] do
      assert {:ok, model} =
               ExplorationSnapshot.load(
                 c.scope,
                 c.mission,
                 %{"source_dashboard_id" => id, "point_id" => "voltage"},
                 c.opts
               )

      assert model.origin == %{status: "unavailable", dashboard: nil}
      assert model.status == "ready"
      assert length(model.rows) == 1
    end
  end

  test "origin metadata requires current mission operation authority", c do
    dashboard = dashboard(c)

    assert {:ok, _} =
             Documents.publish(c.org, c.mission, dashboard.dashboard_id, 1, expected_version: 1)

    assert {:ok, _} = Workspace.reference(c.scope, c.mission, dashboard.dashboard_id)

    for scope <- [
          %{c.scope | organization_membership: nil},
          %{c.scope | user: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | actor_kind: :service}
        ] do
      assert {:error, :unavailable} =
               Workspace.reference(scope, c.mission, dashboard.dashboard_id)

      assert {:error, :unavailable} =
               ExplorationSnapshot.load(
                 scope,
                 c.mission,
                 %{"source_dashboard_id" => dashboard.dashboard_id},
                 c.opts
               )
    end

    refute_received {:read_explore, _, _, _, _, _}
  end

  test "host adapter returns only the safe model and reauthorizes each preparation", c do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: c.scope}}

    info = %{
      route: "/missions/:mission_id/ops/explore",
      params: %{"mission_id" => c.mission, "point_id" => "voltage"}
    }

    prepared = CadenceWeb.OpsExplorationPage.prepare(socket, info, "/explore", c.opts)
    page = prepared.assigns.ops_page
    assert page.id == "dashboards.exploration"
    assert page.status == "ready"
    assert page.data.status == "ready"
    refute Jason.encode!(page) =~ "must-not-reach-browser"
    refute Map.has_key?(page, :token)
    refute Map.has_key?(page.data, :request)

    revoked =
      Phoenix.Component.assign(prepared, :current_scope, %{c.scope | organization_membership: nil})

    rejected = CadenceWeb.OpsExplorationPage.prepare(revoked, info, "/explore", c.opts)
    assert rejected.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(rejected.assigns.ops_page, :data)
  end

  test "foreign, revoked and malformed inputs do not execute sources", c do
    foreign_org = TestFixtures.persist_org!()
    foreign_mission = TestFixtures.persist_mission!(foreign_org)
    foreign_spacecraft = TestFixtures.persist_spacecraft!(foreign_mission)
    params = %{"point_id" => "voltage"}

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: foreign_mission.mission_id},
          %{c.scope | organization_id: foreign_org.organization_id}
        ] do
      assert {:error, :unavailable} = Exploration.prepare(scope, c.mission, params, c.opts)
      assert {:error, :unavailable} = Exploration.load(scope, c.mission, params, c.opts)
    end

    assert {:error, :unavailable} =
             Exploration.load(c.scope, foreign_mission.mission_id, params, c.opts)

    for selectors <- [
          %{"spacecraft_id" => foreign_spacecraft.spacecraft_id},
          %{"scope_kind" => "spacecraft", "scope_id" => foreign_spacecraft.spacecraft_id},
          %{"scope_kind" => "mission", "scope_id" => foreign_mission.mission_id},
          %{"scope_kind" => "source_endpoint", "scope_id" => "missing"},
          %{"scope_kind" => "contact", "scope_id" => "missing"}
        ] do
      assert {:error, :unavailable} =
               Exploration.prepare(c.scope, c.mission, Map.merge(params, selectors), c.opts)

      assert {:error, :unavailable} = load(c, Map.merge(params, selectors))
    end

    assert {:error, :invalid_exploration_context} =
             load(c, Map.put(params, "mission_id", c.mission))

    assert {:error, :point_required} = load(c, %{})
    assert {:error, :point_required} = Exploration.prepare(c.scope, c.mission, %{}, c.opts)

    assert {:error, :invalid_exploration_context} =
             Exploration.prepare(c.scope, c.mission, Map.put(params, "document", %{}), c.opts)

    refute_received {:read_explore, _, _, _, _, _}
  end

  test "a missing explicit source or binding never reads the default source", c do
    for selector <- ["source_binding_id", "data_source_id"] do
      assert {:ok, read} = load(c, %{"point_id" => "voltage", selector => "missing"})
      assert read.result.frames_by_placement["exploration"].primary == []
      assert read.result.frames_by_placement["exploration"].warnings != []
    end

    refute_received {:read_explore, _, _, _, _, _}
  end

  test "contact reads freeze the authorized endpoint set and preserve the contact URL", c do
    endpoint =
      SourceEndpoint.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        spacecraft_id: c.spacecraft
      })

    assert {:ok, endpoint} = Cadence.SourceEndpoints.persist_source_endpoint(c.org, endpoint)
    contact = contact(c, [endpoint.source_endpoint_id])

    params = %{
      "point_id" => "voltage",
      "scope_kind" => "contact",
      "scope_id" => contact.scheduled_contact_id,
      "time_mode" => "last_15m"
    }

    assert {:ok, prepared} = Exploration.prepare(c.scope, c.mission, params, c.opts)
    assert prepared.context.query == params
    assert prepared.request.scope_context.primary.ids == [endpoint.source_endpoint_id]
    refute_received {:read_explore, _, _, _, _, _}
    assert {:ok, read} = load(c, params)
    assert read.request == prepared.request
    assert read.query == params
    assert_received {:read_explore, :history, _, _, _, opts}
    assert opts[:source_endpoint_ids] == [endpoint.source_endpoint_id]
    assert read.request.scope_context.contact_id == nil
    assert read.request.scope_context.primary.ids == [endpoint.source_endpoint_id]
  end

  test "empty contact scopes and unsupported source semantics never become wider reads", c do
    contact = contact(c, [])

    for selectors <- [
          %{"scope_kind" => "contact", "scope_id" => contact.scheduled_contact_id},
          %{"scope_kind" => "transport", "scope_id" => "transport-a"},
          %{"scope_kind" => "ground_station", "scope_id" => "station-a"},
          %{"scope_kind" => "link", "scope_id" => "link-a"}
        ] do
      assert {:error, :unsupported_exploration_scope} =
               Exploration.prepare(
                 c.scope,
                 c.mission,
                 Map.put(selectors, "point_id", "voltage"),
                 c.opts
               )

      assert {:error, :unsupported_exploration_scope} =
               load(c, Map.put(selectors, "point_id", "voltage"))
    end

    params = %{
      "point_id" => "comms.transport.downlink_bitrate",
      "logical_source" => "operational_observables"
    }

    assert {:error, :unsupported_exploration_source} =
             Exploration.prepare(c.scope, c.mission, params, c.opts)

    assert {:error, :unsupported_exploration_source} = load(c, params)

    refute_received {:read_explore, _, _, _, _, _}
  end

  defp contact(c, endpoints) do
    contact =
      ScheduledContact.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        source_endpoint_refs: endpoints,
        paths: [%{direction: :downlink, selection_role: :selected}],
        starts_at: ~U[2026-09-07 11:00:00Z],
        ends_at: ~U[2026-09-07 13:00:00Z]
      })

    assert {:ok, contact} = Cadence.Contacts.persist_scheduled_contact(c.org, contact)
    contact
  end

  defp load(c, params), do: Exploration.load(c.scope, c.mission, params, c.opts)

  defp dashboard(c) do
    fixture =
      Path.expand("../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json", __DIR__)

    base = DocumentCodec.load!(fixture)
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
      | organization_id: c.org,
        mission_id: c.mission,
        dashboard_id: "origin-" <> Ecto.UUID.generate(),
        name: "Flight <overview>",
        placements: [placement]
    }

    assert {:ok, saved} = Documents.persist(c.org, document)
    saved
  end
end
