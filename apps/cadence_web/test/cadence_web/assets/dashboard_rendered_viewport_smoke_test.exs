defmodule CadenceWeb.Assets.DashboardRenderedViewportSmokeTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000

  import Ecto.Query
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision
  alias Cadence.Commanding.{CommandQueueEntry, CommandRequest}
  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Contacts.{LinkAssignment, PathTemplate, RealizedContact, ScheduledContact}
  alias Cadence.Contacts.Path, as: ContactPath

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Placement,
    RenderItem,
    SourceCredentials,
    SourceHealth,
    SourceWatermarks,
    WidgetDef
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.{EffectiveInterval, Event}

  alias Cadence.Persistence.Schemas.{
    BackgroundJobRow,
    CommandQueueEntryRow,
    CommandRequestRow,
    ReplayRunRow,
    ReplayTelemetrySampleRow,
    TelemetryLimitEventRow,
    TelemetrySampleRow
  }

  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Runtime.ManagedActionRequest
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.{PacketDefinition, Sample, Storage}
  alias CadenceWeb.TestFixtures
  alias Ecto.Adapters.SQL.Sandbox

  defp reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  defp persist_command_queue_entry!(
         org,
         mission,
         command_queue_entry_id,
         source_endpoint_ref,
         lifecycle_state \\ :pending,
         opts \\ []
       ) do
    requested_at = DateTime.from_unix!(1_700_000_000, :second)
    command_request_id = command_queue_entry_id <> "-request"

    metadata =
      opts
      |> Keyword.take([:spacecraft_id])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: command_queue_entry_id <> "-snapshot",
        command_id: command_queue_entry_id <> "-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-browser-test"},
        requested_at: requested_at,
        metadata: metadata
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-browser-test"},
        enqueued_at: requested_at,
        metadata: metadata
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
  end

  defp persist_ingress_latency_through_write_path!(org, mission, source_endpoint_id, opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    contact_id = Keyword.get(opts, :contact_id)
    receipt_time = Keyword.fetch!(opts, :receipt_time)
    packet_value = Keyword.get(opts, :packet_value, 31)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_id,
        spacecraft_id: spacecraft_id,
        receipt_time: receipt_time,
        metadata: %{
          "contact_id" => contact_id,
          "scheduled_contact_id" => Keyword.get(opts, :scheduled_contact_id, contact_id),
          "realized_contact_id" => Keyword.get(opts, :realized_contact_id)
        },
        raw: build_space_packet(42, Keyword.get(opts, :sequence_count, 1), <<packet_value::16>>)
      })

    assert {:ok, _processing_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence)

    [latency_sample | _] =
      Cadence.operational_observable_metric_samples(org.organization_id, mission.mission_id,
        observable_id: "ingress.processing_latency_ms",
        source_endpoint_id: source_endpoint_id,
        order: :desc
      )

    assert latency_sample.resource_id == source_endpoint_id
    assert latency_sample.source_endpoint_id == source_endpoint_id
    assert latency_sample.spacecraft_id == spacecraft_id
    assert Map.get(latency_sample, :contact_id) == contact_id
    assert latency_sample.unit == "ms"
    assert is_number(latency_sample.value)
    assert latency_sample.value > 0

    latency_sample
  end

  test "rendered dashboard HTML passes browser viewport smoke", %{conn: _conn} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "viewport", display_name: "Viewport Mission")

    conn = TestFixtures.member_conn(user)

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

    [older_sample, _latest_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Viewport Power",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          },
          %{
            type: :event_timeline,
            title: "Workflow Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 4, y: 3, w: 8, h: 3}
          },
          %{
            type: :constellation_health,
            title: "Fleet",
            binding: %{mode: :constellation},
            layout: %{x: 0, y: 3, w: 4, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    selected_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      source_binding_id: "default_flight_telemetry",
      limit_mode: "compare"
    }

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"
      )

    html = render_async(view, 5_000)

    assert has_element?(view, "#ops-dashboard-show-page")
    assert has_element?(view, ~s([phx-hook="DashboardGrid"]))
    assert has_element?(view, ~s([phx-hook="TelemetryChart"]))
    assert has_element?(view, "#dashboard-panel")
    assert has_element?(view, "#dashboard-data-link-copy-link")

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    artifact_path = rendered_dashboard_artifact!(html, app_root)
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    on_exit(fn -> File.rm(artifact_path) end)

    assert {output, 0} =
             System.cmd(
               "node",
               [script, "--profile", "rendered-dashboard", "--html", artifact_path],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-runtime-context-batch",
        display_name: "Source Endpoint Runtime Context Batch"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Context")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 31, 1_700_000_090)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 32, 1_700_000_100)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Alpha",
        source_ref: "browser-context-alpha",
        metadata: %{"ground_station_id" => "browser-context-dss-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Beta",
        source_ref: "browser-context-beta",
        metadata: %{"ground_station_id" => "browser-context-dss-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id], ",")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-source-endpoint-batch",
                 "--context-search-query",
                 "browser-context",
                 "--expected-context-source-endpoint-ids",
                 scope_ids,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live contact runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-runtime-context-batch",
        display_name: "Contact Runtime Context Batch"
      )

    _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Contact Context")

    alpha_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-context-contact-alpha",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-context-contact-source-alpha"],
        paths: contact_paths("browser-context-contact-source-alpha"),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z]
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-context-contact-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-context-contact-source-beta"],
        paths: contact_paths("browser-context-contact-source-beta"),
        starts_at: ~U[2026-06-30 12:09:00Z],
        ends_at: ~U[2026-06-30 12:16:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_contact.scheduled_contact_id, beta_contact.scheduled_contact_id], ",")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-contact-batch",
                 "--context-search-query",
                 "browser-context-contact",
                 "--expected-context-contact-ids",
                 scope_ids,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live ground-station runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ground-station-runtime-context-batch",
        display_name: "Ground Station Runtime Context Batch"
      )

    _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Ground Context")

    alpha_ground_station =
      GroundStation.new(%{
        ground_station_id: "browser-context-ground-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Ground Alpha",
        provider: "browser-ground-provider",
        region: "west"
      })

    beta_ground_station =
      GroundStation.new(%{
        ground_station_id: "browser-context-ground-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Ground Beta",
        provider: "browser-ground-provider",
        region: "east"
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, alpha_ground_station)

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, beta_ground_station)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ground Station Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join(
        [
          alpha_ground_station.ground_station_id,
          beta_ground_station.ground_station_id
        ],
        ","
      )

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-ground-station-batch",
                 "--context-search-query",
                 "browser-context-ground",
                 "--expected-context-ground-station-ids",
                 scope_ids,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live link runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-runtime-context-batch",
        display_name: "Link Runtime Context Batch"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Link Context")

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-link-source-alpha",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Browser Context Link Source Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-link-source-beta",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Browser Context Link Source Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_template =
      PathTemplate.new(%{
        path_template_id: "browser-context-link-template-alpha",
        mission_id: mission.mission_id,
        path_id: "browser-context-link-path-alpha",
        direction: :downlink,
        selection_role: :selected
      })

    beta_template =
      PathTemplate.new(%{
        path_template_id: "browser-context-link-template-beta",
        mission_id: mission.mission_id,
        path_id: "browser-context-link-path-beta",
        direction: :downlink,
        selection_role: :selected
      })

    assert {:ok, _path_template} =
             Cadence.persist_path_template(org.organization_id, alpha_template)

    assert {:ok, _path_template} =
             Cadence.persist_path_template(org.organization_id, beta_template)

    alpha_link =
      LinkAssignment.new(%{
        link_assignment_id: "browser-context-link-alpha",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: alpha_endpoint.source_endpoint_id,
        path_template_id: alpha_template.path_template_id,
        path_template_version: alpha_template.version,
        direction: alpha_template.direction,
        selection_role: alpha_template.selection_role,
        provider_path_ref: "browser-link-alpha"
      })

    beta_link =
      LinkAssignment.new(%{
        link_assignment_id: "browser-context-link-beta",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: beta_endpoint.source_endpoint_id,
        path_template_id: beta_template.path_template_id,
        path_template_version: beta_template.version,
        direction: beta_template.direction,
        selection_role: beta_template.selection_role,
        provider_path_ref: "browser-link-beta"
      })

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, alpha_link)

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, beta_link)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Link Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids = Enum.join([alpha_link.link_assignment_id, beta_link.link_assignment_id], ",")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-link-batch",
                 "--context-search-query",
                 "browser-context-link",
                 "--expected-context-link-ids",
                 scope_ids,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live spacecraft runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "spacecraft-runtime-context-batch",
        display_name: "Spacecraft Runtime Context Batch"
      )

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-context-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-context-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, beta_spacecraft)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Spacecraft Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_spacecraft.spacecraft_id, beta_spacecraft.spacecraft_id], ",")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-spacecraft-batch",
                 "--context-search-query",
                 "Browser Context Spacecraft",
                 "--expected-context-spacecraft-ids",
                 scope_ids,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live authenticated dashboard route passes browser viewport smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_live_deps = Application.get_env(:cadence_web, :ops_dashboard_show_live, [])

    previous_inline_resolve? =
      Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)

    Application.put_env(
      :cadence_web,
      :ops_dashboard_show_live,
      Keyword.put(
        previous_live_deps,
        :late_data_policy_event_opts,
        dashboard_runtime_invalidation?: false
      )
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :ops_dashboard_show_live, previous_live_deps)

      case previous_inline_resolve? do
        nil -> Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)
        value -> Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "live-viewport", display_name: "Live Viewport")

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Live")
    binding_set = persist_binding_set!(org, mission)
    seed_limit_definition!(mission)

    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)

    catalog_revision_id =
      seed_catalog_revision_event!(org, mission, DateTime.from_unix!(base_unix - 60))

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, base_unix)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 22, base_unix + 10)
    evaluate_limit_events!(org, mission, spacecraft)

    [older_sample, latest_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Viewport Power",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          },
          %{
            type: :event_timeline,
            title: "Workflow Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 4, y: 3, w: 8, h: 3}
          },
          %{
            type: :constellation_health,
            title: "Fleet",
            binding: %{mode: :constellation},
            layout: %{x: 0, y: 3, w: 4, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    selected_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      source_binding_id: "default_flight_telemetry"
    }

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--url",
                 dashboard_url,
                 "--expected-limit-definition-id",
                 "browser-viewport-counter-limits",
                 "--expected-limit-set-name",
                 "browser-smoke",
                 "--expected-catalog-revision-id",
                 catalog_revision_id,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    persisted_layout_document = fetch_dashboard_document!(org, mission, dashboard)

    persisted_counter_placement =
      placement_by_id!(persisted_layout_document, counter_item.placement_id)

    assert persisted_counter_placement.layout.x == counter_item.layout.x
    assert persisted_counter_placement.layout.y == counter_item.layout.y + 1
    assert persisted_counter_placement.layout.w == counter_item.layout.w
    assert persisted_counter_placement.layout.h == counter_item.layout.h

    assert [started_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_started
             )
             |> Enum.filter(&(&1.reason == "browser_smoke_historical_start"))

    assert started_event.payload["stage_transition_source"] == "dashboard_stage_action"
    assert started_event.payload["dashboard_context"]["dashboard_id"] == dashboard.dashboard_id
    assert started_event.payload["dashboard_context"]["dashboard_limit_mode"] == "compare"

    assert {:ok, started_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(started_event.backfill_run_id)

    assert started_job.status == :queued
    assert started_job.payload["workflow"] == "backfill"

    claimed_jobs = Cadence.Jobs.claim_jobs(10)
    claimed_started_job = Enum.find(claimed_jobs, &(&1.job_id == started_job.job_id))

    assert claimed_started_job

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_started_job.job_id)
    assert completed_job.status == :completed

    assert [completed_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_completed
             )
             |> Enum.filter(&(&1.backfill_run_id == started_event.backfill_run_id))

    assert completed_event.reason == "historical_data_job_completed"
    assert completed_event.payload["job_id"] == completed_job.job_id

    completed_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: completed_event.backfill_lifecycle_event_id
    }

    completed_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{completed_query}"

    assert {completed_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "completed-workflow",
                 "--url",
                 completed_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert completed_output =~ "dashboard_viewport_smoke passed"

    assert [late_data_policy_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :late_data_accepted
             )
             |> Enum.filter(
               &(&1.payload["source_event_id"] == completed_event.backfill_lifecycle_event_id)
             )

    assert late_data_policy_event.payload["dashboard_context"]["dashboard_limit_mode"] ==
             "compare"

    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    for limit_mode <- ["current", "recomputed"] do
      completed_event =
        record_completed_late_data_policy_source_event!(
          org,
          mission,
          dashboard,
          spacecraft,
          [older_sample, latest_sample],
          limit_mode
        )

      completed_query = %{
        panel: "data_link",
        selected_target: "telemetry_backfill_lifecycle_event",
        selected_id: completed_event.backfill_lifecycle_event_id,
        limit_mode: limit_mode
      }

      completed_dashboard_url =
        base_url <>
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{completed_query}"

      assert {completed_output, 0} =
               System.cmd(
                 "node",
                 [
                   script,
                   "--profile",
                   "live-dashboard",
                   "--interaction-mode",
                   "completed-workflow",
                   "--expected-limit-mode",
                   limit_mode,
                   "--url",
                   completed_dashboard_url,
                   "--login-url",
                   base_url <> ~p"/sign-in",
                   "--login-email",
                   user.email,
                   "--login-password",
                   TestFixtures.default_password()
                 ],
                 cd: app_root,
                 stderr_to_stdout: true
               )

      assert completed_output =~ "dashboard_viewport_smoke passed"

      assert [late_data_policy_event] =
               mission.mission_id
               |> Storage.list_backfill_lifecycle_events(
                 organization_id: org.organization_id,
                 event_type: :late_data_accepted
               )
               |> Enum.filter(
                 &(&1.payload["source_event_id"] == completed_event.backfill_lifecycle_event_id)
               )

      assert late_data_policy_event.reason == "browser_smoke_late_data_policy_#{limit_mode}"

      assert late_data_policy_event.payload["dashboard_context"]["dashboard_limit_mode"] ==
               limit_mode
    end

    replay_policy_mission =
      TestFixtures.persist_mission!(org,
        slug: "live-viewport-replay-policy",
        display_name: "Live Viewport Replay Policy"
      )

    replay_policy_spacecraft =
      TestFixtures.persist_spacecraft!(replay_policy_mission, display_name: "SC Replay Policy")

    replay_policy_binding_set = persist_binding_set!(org, replay_policy_mission)
    seed_limit_definition!(replay_policy_mission)

    ingest!(
      replay_policy_mission,
      replay_policy_binding_set,
      replay_policy_spacecraft.spacecraft_id,
      21,
      base_unix
    )

    ingest!(
      replay_policy_mission,
      replay_policy_binding_set,
      replay_policy_spacecraft.spacecraft_id,
      22,
      base_unix + 10
    )

    evaluate_limit_events!(org, replay_policy_mission, replay_policy_spacecraft)

    [replay_older_sample, replay_latest_sample] =
      Cadence.telemetry_history(
        org.organization_id,
        replay_policy_mission.mission_id,
        "HK.counter",
        spacecraft_id: replay_policy_spacecraft.spacecraft_id,
        order: :asc
      )

    replay_policy_dashboard =
      TestFixtures.persist_dashboard_document!(replay_policy_mission,
        name: "Replay Policy Power",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: replay_policy_spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: replay_policy_spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          },
          %{
            type: :event_timeline,
            title: "Workflow Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 4, y: 3, w: 8, h: 3}
          },
          %{
            type: :constellation_health,
            title: "Fleet",
            binding: %{mode: :constellation},
            layout: %{x: 0, y: 3, w: 4, h: 3}
          }
        ]
      )

    replay_policy_run_id = "browser-smoke-late-policy-replay"
    persist_replay_dashboard_sources!(org.organization_id, replay_policy_mission.mission_id)

    replay_policy_run =
      Run.new(%{
        replay_run_id: replay_policy_run_id,
        mission_id: replay_policy_mission.mission_id,
        binding_set_id: replay_policy_binding_set.binding_set_id,
        binding_set_version: replay_policy_binding_set.version,
        status: :completed,
        replayed_evidence_count: 2,
        replayed_packet_count: 2,
        replayed_sample_count: 2,
        started_at: DateTime.add(replay_older_sample.receipt_time, -60, :second),
        completed_at: DateTime.add(replay_older_sample.receipt_time, 60, :second)
      })

    Repo.insert!(ReplayRunRow.changeset(replay_policy_run))

    insert_replay_telemetry_samples!(
      [replay_older_sample, replay_latest_sample],
      replay_policy_run_id
    )

    insert_replay_limit_events!(
      replay_policy_mission,
      replay_policy_spacecraft,
      [replay_older_sample, replay_latest_sample],
      replay_policy_run_id
    )

    replay_completed_event =
      record_completed_late_data_policy_source_event!(
        org,
        replay_policy_mission,
        replay_policy_dashboard,
        replay_policy_spacecraft,
        [replay_older_sample, replay_latest_sample],
        "compare",
        dashboard_time_mode: "replay_run",
        dashboard_replay_run_id: replay_policy_run_id
      )

    replay_completed_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: replay_completed_event.backfill_lifecycle_event_id,
      time_mode: "replay_run",
      replay_run_id: replay_policy_run_id,
      limit_mode: "compare"
    }

    replay_completed_dashboard_url =
      base_url <>
        ~p"/missions/#{replay_policy_mission.mission_id}/ops/dashboards/#{replay_policy_dashboard.dashboard_id}?#{replay_completed_query}"

    assert {replay_completed_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "completed-workflow",
                 "--expected-time-mode",
                 "replay_run",
                 "--expected-replay-run-id",
                 replay_policy_run_id,
                 "--expected-limit-mode",
                 "compare",
                 "--expected-late-data-policy-execution-mode",
                 "event_only",
                 "--skip-late-data-policy-submit",
                 "--url",
                 replay_completed_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert replay_completed_output =~ "dashboard_viewport_smoke passed"

    case previous_inline_resolve? do
      nil -> Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)
      value -> Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
    end

    retry_run_id = "browser-smoke-workflow-run-retry"
    retry_source_from = DateTime.from_unix!(base_unix - 60)
    retry_source_to = DateTime.from_unix!(base_unix + 60)

    assert {:ok, failed_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: retry_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: retry_source_from,
                 source_to: retry_source_to,
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "failure" => "source window unavailable",
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-retry-group",
                   "request_item_index" => 1,
                   "request_item_count" => 2,
                   "request_item_run_id" => retry_run_id,
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_version" => "1",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-retry-browser",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retry_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               retry_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => retry_run_id}
               }
             )

    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == retry_job.job_id))

    assert {:ok, failed_job} =
             Cadence.Jobs.fail_worker_start(retry_job.job_id, :source_window_failed)

    assert failed_job.status == :failed

    retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: failed_event.backfill_lifecycle_event_id
    }

    retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{retry_query}"

    assert {retry_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "retry-workflow",
                 "--url",
                 retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert retry_output =~ "dashboard_viewport_smoke passed"

    assert {:ok, retried_job} = Cadence.fetch_telemetry_historical_data_workflow_job(retry_run_id)
    assert retried_job.status == :queued
    assert retried_job.failure_reason == nil

    assert [retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == retry_run_id))

    assert retried_event.reason == "dashboard_historical_workflow_retried"
    assert retried_event.payload["retry_action"] == "retry_job"

    assert retried_event.payload["retry_source_event_id"] ==
             failed_event.backfill_lifecycle_event_id

    assert retried_event.payload["retry_job_id"] == retry_job.job_id
    assert retried_event.payload["retry_job_status"] == "queued"

    correction_run_id = "browser-smoke-workflow-run-nonretryable"
    corrected_run_id = "browser-smoke-workflow-run-corrected"

    assert {:ok, correction_group_context_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "completed",
               %{
                 backfill_run_id: "browser-smoke-workflow-run-context",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 authority: :authoritative,
                 reason: "historical_data_job_completed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-correction-group",
                   "request_item_index" => 2,
                   "request_item_count" => 2,
                   "request_item_run_id" => "browser-smoke-workflow-run-context"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_source_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: correction_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-correction-group",
                   "request_item_index" => 1,
                   "request_item_count" => 2,
                   "request_item_run_id" => correction_run_id,
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_version" => "1",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-correction-browser",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "source" => %{
                     "failure" => %{
                       "code" => "missing_field:point_id",
                       "retryable" => false,
                       "retry_blockers" => ["missing point_id"],
                       "recovery_action" => "correct_workflow_request"
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               correction_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => correction_run_id}
               }
             )

    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == correction_job.job_id))

    assert {:ok, failed_correction_job} =
             Cadence.Jobs.fail_worker_start(correction_job.job_id, :missing_point_id)

    assert failed_correction_job.status == :failed

    correction_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: correction_group_context_event.backfill_lifecycle_event_id
    }

    correction_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{correction_query}"

    assert {correction_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "correction-workflow",
                 "--url",
                 correction_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert correction_output =~ "dashboard_viewport_smoke passed"

    corrected_events =
      mission.mission_id
      |> Storage.list_backfill_lifecycle_events(
        organization_id: org.organization_id,
        backfill_run_id: corrected_run_id
      )

    assert %{event_type: :backfill_requested} =
             corrected_event =
             Enum.find(corrected_events, &(&1.event_type == :backfill_requested))

    assert corrected_event.reason == "browser_smoke_historical_correction"
    assert corrected_event.point_id == "HK.counter"
    assert corrected_event.payload["recovery_action"] == "correct_workflow_request"
    assert corrected_event.payload["correction_source"] == "dashboard_correction_request"
    assert corrected_event.payload["correction_source_event_type"] == "backfill_failed"
    assert corrected_event.payload["request_mode"] == "bulk_points"

    assert corrected_event.payload["request_group_id"] ==
             "browser-smoke-workflow-correction-group"

    assert corrected_event.payload["request_item_index"] == 1
    assert corrected_event.payload["request_item_count"] == 2
    assert corrected_event.payload["request_item_run_id"] == corrected_run_id
    assert corrected_event.payload["corrects_run_id"] == correction_run_id

    assert corrected_event.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert corrected_event.payload["corrects_job_id"] == correction_job.job_id

    assert corrected_event.payload["dashboard_context"] == %{
             "dashboard_id" => dashboard.dashboard_id,
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-browser",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert %{event_type: :backfill_approved} =
             approved_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_approved))

    assert approved_replacement.reason == "dashboard_recovery_replacement_approved"

    assert approved_replacement.payload["request_group_id"] ==
             "browser-smoke-workflow-correction-group"

    assert approved_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert approved_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert approved_replacement.payload["group_transition_scope"] == "replacement_corrections"

    assert %{event_type: :backfill_started} =
             started_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_started))

    assert started_replacement.reason == "dashboard_recovery_replacement_started"
    assert started_replacement.backfill_run_id == corrected_run_id

    assert started_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert started_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert started_replacement.payload["group_transition_scope"] == "replacement_corrections"

    assert %{event_type: :backfill_completed} =
             completed_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_completed))

    assert completed_replacement.reason == "dashboard_recovery_replacement_completed"
    assert completed_replacement.backfill_run_id == corrected_run_id

    assert completed_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert completed_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert completed_replacement.payload["group_transition_scope"] == "replacement_corrections"

    closure_group_id = "browser-smoke-workflow-closure-group"
    closure_failed_run_id = "browser-smoke-workflow-closure-failed"
    closure_corrected_run_id = "browser-smoke-workflow-closure-corrected"
    closure_ready_run_id = "browser-smoke-workflow-closure-ready"

    closure_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-closure-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    closure_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        closure_failed_run_id,
        :closure_ready_source_failed
      )

    closure_source_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: closure_failed_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: %{
            "dashboard_context" => closure_dashboard_context,
            "source" => %{
              "failure" => %{
                "code" => "missing_field:point_id",
                "retryable" => false,
                "retry_blockers" => ["missing point_id"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    closure_correction_payload = %{
      "dashboard_context" => closure_dashboard_context,
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "recovery_action" => "correct_workflow_request",
      "corrects_run_id" => closure_failed_run_id,
      "corrects_event_id" => closure_source_event.backfill_lifecycle_event_id,
      "corrects_job_id" => closure_source_job.job_id
    }

    _closure_corrected_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_approved =
      record_backfill_workflow_event!(
        org,
        mission,
        "approved",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_started =
      record_backfill_workflow_event!(
        org,
        mission,
        "started",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_completed =
      record_backfill_workflow_event!(
        org,
        mission,
        "completed",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_ready_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    _closure_ready_approved =
      record_backfill_workflow_event!(
        org,
        mission,
        "approved",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    closure_ready_started =
      record_backfill_workflow_event!(
        org,
        mission,
        "started",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    _closure_corrected_job =
      enqueue_completed_historical_workflow_job!(mission, closure_corrected_run_id)

    _closure_ready_job =
      enqueue_completed_historical_workflow_job!(mission, closure_ready_run_id)

    closure_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: closure_ready_started.backfill_lifecycle_event_id
    }

    closure_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{closure_query}"

    assert {closure_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "closure-completion-workflow",
                 "--url",
                 closure_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert closure_output =~ "dashboard_viewport_smoke passed"

    assert [closure_completion_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_completed
             )
             |> Enum.filter(&(&1.backfill_run_id == closure_ready_run_id))

    assert closure_completion_event.reason == "dashboard_recovery_group_completed"
    assert closure_completion_event.payload["request_group_id"] == closure_group_id
    assert closure_completion_event.payload["request_item_index"] == 2
    assert closure_completion_event.payload["request_item_count"] == 2
    assert closure_completion_event.payload["request_item_run_id"] == closure_ready_run_id

    assert closure_completion_event.payload["requested_event_id"] ==
             closure_ready_started.backfill_lifecycle_event_id

    assert closure_completion_event.payload["group_transition_source"] ==
             "dashboard_group_action"

    assert closure_completion_event.payload["dashboard_context"] == closure_dashboard_context

    real_job_group_id = "browser-smoke-workflow-real-job-group"
    real_job_completed_run_id = "browser-smoke-workflow-real-job-completed"
    real_job_retryable_failed_run_id = "browser-smoke-workflow-real-job-retryable-failed"
    real_job_failed_run_id = "browser-smoke-workflow-real-job-failed"

    real_job_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-real-job-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    real_job_comparison_review_origin = %{
      "request_event_id" => "browser-smoke-review-origin-request",
      "request_kind" => "comparison_open_findings_review",
      "open_count" => "1",
      "open_placement_ids" => trend_widget.widget_id,
      "workflow_kind" => "bulk_correction_authority_review",
      "workflow_action" => "request_comparison_review",
      "workflow_selection_kind" => "open_comparison_findings",
      "workflow_selection_count" => "1",
      "primary_data_view" => "all_revisions",
      "compare_data_view" => "canonical"
    }

    real_job_completed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_completed_run_id,
        "HK.counter",
        real_job_group_id,
        1,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    real_job_failed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_failed_run_id,
        nil,
        real_job_group_id,
        3,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    real_job_retryable_failed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_retryable_failed_run_id,
        "HK.voltage",
        real_job_group_id,
        2,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    _real_job_completed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_completed_attrs)

    _real_job_completed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_completed_attrs)

    _real_job_completed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_completed_attrs)

    _real_job_retryable_failed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_retryable_failed_attrs)

    _real_job_retryable_failed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_retryable_failed_attrs)

    _real_job_retryable_failed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_retryable_failed_attrs)

    _real_job_failed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_failed_attrs)

    _real_job_failed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_failed_attrs)

    _real_job_failed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_failed_attrs)

    assert {:ok, real_retryable_failed_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               real_job_retryable_failed_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => real_job_retryable_failed_run_id}
               }
             )

    assert Enum.any?(
             Cadence.Jobs.claim_jobs(10),
             &(&1.job_id == real_retryable_failed_job.job_id)
           )

    assert {:ok, failed_retryable_real_job} =
             Cadence.Jobs.fail_worker_start(
               real_retryable_failed_job.job_id,
               :source_window_failed
             )

    assert failed_retryable_real_job.status == :failed

    real_job_retryable_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: real_job_retryable_failed_run_id,
          point_id: "HK.voltage",
          request_group_id: real_job_group_id,
          item_index: 2,
          item_count: 3,
          payload: %{
            "dashboard_context" => real_job_dashboard_context,
            "comparison_review_origin" => real_job_comparison_review_origin,
            "job_id" => real_retryable_failed_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => true,
                "retry_blockers" => [],
                "recovery_action" => "retry_job"
              }
            }
          }
        }
      )

    assert {:ok, real_completed_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               real_job_completed_attrs,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, real_failed_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               real_job_failed_attrs,
               dashboard_runtime_invalidation?: false
             )

    claimed_real_jobs = Cadence.Jobs.claim_jobs(10)

    claimed_real_completed_job =
      Enum.find(claimed_real_jobs, &(&1.job_id == real_completed_job.job_id))

    claimed_real_failed_job = Enum.find(claimed_real_jobs, &(&1.job_id == real_failed_job.job_id))

    assert claimed_real_completed_job
    assert claimed_real_failed_job

    assert {:ok, completed_real_job} = Cadence.Jobs.run_job(claimed_real_completed_job.job_id)
    assert completed_real_job.status == :completed

    assert {:ok, failed_real_job} = Cadence.Jobs.run_job(claimed_real_failed_job.job_id)
    assert failed_real_job.status == :failed

    assert [real_completed_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_completed
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_completed_run_id))

    assert real_completed_event.reason == "historical_data_job_completed"
    assert real_completed_event.payload["job_id"] == real_completed_job.job_id
    assert real_completed_event.payload["workflow_job_status"] == "completed"
    assert real_completed_event.payload["request_group_id"] == real_job_group_id
    assert real_completed_event.payload["request_item_index"] == 1
    assert real_completed_event.payload["request_item_count"] == 3
    assert real_completed_event.payload["request_item_run_id"] == real_job_completed_run_id
    assert real_completed_event.payload["dashboard_context"] == real_job_dashboard_context

    assert real_completed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert [real_failed_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_failed
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_failed_run_id))

    assert real_failed_event.reason == :historical_data_job_failed
    assert real_failed_event.payload["job_id"] == real_failed_job.job_id
    assert real_failed_event.payload["workflow_job_status"] == "failed"
    assert real_failed_event.payload["request_group_id"] == real_job_group_id
    assert real_failed_event.payload["request_item_index"] == 3
    assert real_failed_event.payload["request_item_count"] == 3
    assert real_failed_event.payload["request_item_run_id"] == real_job_failed_run_id
    assert real_failed_event.payload["dashboard_context"] == real_job_dashboard_context

    assert real_failed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_failed_event.payload["source"]["failure"]["recovery_action"] ==
             "correct_workflow_request"

    assert real_job_retryable_failed_event.payload["request_group_id"] == real_job_group_id
    assert real_job_retryable_failed_event.payload["request_item_index"] == 2
    assert real_job_retryable_failed_event.payload["request_item_count"] == 3

    assert real_job_retryable_failed_event.payload["request_item_run_id"] ==
             real_job_retryable_failed_run_id

    assert real_job_retryable_failed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_retryable_failed_event.payload["source"]["failure"]["recovery_action"] ==
             "retry_job"

    real_job_recovery_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: real_failed_event.backfill_lifecycle_event_id
    }

    real_job_recovery_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{real_job_recovery_query}"

    assert {real_job_recovery_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-job-recovery-workflow",
                 "--url",
                 real_job_recovery_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert real_job_recovery_output =~ "dashboard_viewport_smoke passed"

    real_job_corrected_run_id = "browser-smoke-workflow-real-job-corrected"

    real_job_corrected_events =
      mission.mission_id
      |> Storage.list_backfill_lifecycle_events(
        organization_id: org.organization_id,
        backfill_run_id: real_job_corrected_run_id
      )

    assert %{event_type: :backfill_requested} =
             real_job_corrected_requested =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_requested))

    assert real_job_corrected_requested.reason == "browser_smoke_real_worker_correction"
    assert real_job_corrected_requested.point_id == "HK.current"

    assert real_job_corrected_requested.payload["request_group_id"] ==
             real_job_group_id

    assert real_job_corrected_requested.payload["request_item_index"] == 3
    assert real_job_corrected_requested.payload["request_item_count"] == 3

    assert real_job_corrected_requested.payload["request_item_run_id"] ==
             real_job_corrected_run_id

    assert real_job_corrected_requested.payload["corrects_run_id"] == real_job_failed_run_id

    assert real_job_corrected_requested.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_requested.payload["corrects_job_id"] == real_failed_job.job_id

    assert real_job_corrected_requested.payload["dashboard_context"] ==
             real_job_dashboard_context

    assert real_job_corrected_requested.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert %{event_type: :backfill_approved} =
             real_job_corrected_approved =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_approved))

    assert real_job_corrected_approved.reason == "dashboard_recovery_replacement_approved"
    assert real_job_corrected_approved.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_approved.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_approved.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_approved.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert %{event_type: :backfill_started} =
             real_job_corrected_started =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_started))

    assert real_job_corrected_started.reason == "dashboard_recovery_replacement_started"
    assert real_job_corrected_started.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_started.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_started.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_started.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert %{event_type: :backfill_completed} =
             real_job_corrected_completed =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_completed))

    assert real_job_corrected_completed.reason == "dashboard_recovery_replacement_completed"
    assert real_job_corrected_completed.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_completed.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_completed.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_completed.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert [real_job_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_retryable_failed_run_id))

    assert real_job_retried_event.payload["retry_source_event_id"] ==
             real_job_retryable_failed_event.backfill_lifecycle_event_id

    assert real_job_retried_event.payload["retry_job_id"] == real_retryable_failed_job.job_id
    assert real_job_retried_event.payload["retry_job_status"] == "queued"
    assert real_job_retried_event.payload["request_group_id"] == real_job_group_id

    assert {:ok, real_job_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               real_job_retryable_failed_run_id
             )

    assert real_job_retried_job.status == :queued

    skipped_retry_group_id = "browser-smoke-workflow-skipped-retry-group"
    skipped_retryable_run_id = "browser-smoke-workflow-skipped-retryable"
    skipped_missing_job_run_id = "browser-smoke-workflow-skipped-missing-job"

    skipped_retry_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-skipped-retry-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    skipped_retryable_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        skipped_retryable_run_id,
        "HK.voltage",
        skipped_retry_group_id,
        1,
        2,
        dashboard_context: skipped_retry_dashboard_context
      )

    skipped_missing_job_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        skipped_missing_job_run_id,
        "HK.current",
        skipped_retry_group_id,
        2,
        2,
        dashboard_context: skipped_retry_dashboard_context
      )

    for attrs <- [skipped_retryable_attrs, skipped_missing_job_attrs],
        stage <- ["requested", "approved", "started"] do
      record_backfill_workflow_event!(org, mission, stage, attrs)
    end

    assert {:ok, skipped_retryable_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               skipped_retryable_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => skipped_retryable_run_id}
               }
             )

    assert Enum.any?(
             Cadence.Jobs.claim_jobs(10),
             &(&1.job_id == skipped_retryable_job.job_id)
           )

    assert {:ok, failed_skipped_retryable_job} =
             Cadence.Jobs.fail_worker_start(
               skipped_retryable_job.job_id,
               :source_window_failed
             )

    assert failed_skipped_retryable_job.status == :failed

    skipped_retryable_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: skipped_retryable_run_id,
          point_id: "HK.voltage",
          request_group_id: skipped_retry_group_id,
          item_index: 1,
          item_count: 2,
          payload: %{
            "dashboard_context" => skipped_retry_dashboard_context,
            "job_id" => skipped_retryable_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => true,
                "retry_blockers" => [],
                "recovery_action" => "retry_job"
              }
            }
          }
        }
      )

    skipped_missing_job_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: skipped_missing_job_run_id,
          point_id: "HK.current",
          request_group_id: skipped_retry_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{
            "dashboard_context" => skipped_retry_dashboard_context,
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => true,
                "retry_blockers" => [],
                "recovery_action" => "retry_job"
              }
            }
          }
        }
      )

    skipped_retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: skipped_missing_job_failed_event.backfill_lifecycle_event_id
    }

    skipped_retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{skipped_retry_query}"

    assert {skipped_retry_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-retry-skipped-workflow",
                 "--url",
                 skipped_retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert skipped_retry_output =~ "dashboard_viewport_smoke passed"

    assert [skipped_retry_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == skipped_retryable_run_id))

    assert skipped_retry_retried_event.payload["retry_source_event_id"] ==
             skipped_retryable_failed_event.backfill_lifecycle_event_id

    assert skipped_retry_retried_event.payload["retry_job_id"] == skipped_retryable_job.job_id
    assert skipped_retry_retried_event.payload["request_group_id"] == skipped_retry_group_id

    assert {:ok, skipped_retryable_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(skipped_retryable_run_id)

    assert skipped_retryable_retried_job.status == :queued
    refute skipped_retry_retried_event.backfill_run_id == skipped_missing_job_run_id

    replacement_retry_group_id = "browser-smoke-workflow-replacement-retry-group"
    replacement_retry_source_run_id = "browser-smoke-workflow-replacement-retry-source"
    replacement_retry_corrected_run_id = "browser-smoke-workflow-replacement-retry-corrected"

    replacement_retry_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-replacement-retry-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    replacement_retry_source_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        replacement_retry_source_run_id,
        "HK.current",
        replacement_retry_group_id,
        1,
        1,
        dashboard_context: replacement_retry_dashboard_context
      )

    _replacement_retry_source_requested =
      record_backfill_workflow_event!(org, mission, "requested", replacement_retry_source_attrs)

    _replacement_retry_source_approved =
      record_backfill_workflow_event!(org, mission, "approved", replacement_retry_source_attrs)

    _replacement_retry_source_started =
      record_backfill_workflow_event!(org, mission, "started", replacement_retry_source_attrs)

    replacement_retry_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        replacement_retry_source_run_id,
        :replacement_retry_source_failed
      )

    replacement_retry_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: replacement_retry_source_run_id,
          point_id: "HK.current",
          request_group_id: replacement_retry_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => replacement_retry_dashboard_context,
            "job_id" => replacement_retry_source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    replacement_retry_correction_payload = %{
      "dashboard_context" => replacement_retry_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => replacement_retry_source_run_id,
      "corrects_event_id" => replacement_retry_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => replacement_retry_source_job.job_id
    }

    replacement_retry_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        replacement_retry_corrected_run_id,
        "HK.current",
        replacement_retry_group_id,
        1,
        1,
        dashboard_context: replacement_retry_dashboard_context
      )
      |> Map.put(:payload, replacement_retry_correction_payload)

    _replacement_retry_corrected_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        replacement_retry_corrected_attrs
      )

    _replacement_retry_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", replacement_retry_corrected_attrs)

    _replacement_retry_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", replacement_retry_corrected_attrs)

    replacement_retry_corrected_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        replacement_retry_corrected_run_id,
        :replacement_retry_corrected_failed
      )

    replacement_retry_corrected_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: replacement_retry_corrected_run_id,
          point_id: "HK.current",
          request_group_id: replacement_retry_group_id,
          item_index: 1,
          item_count: 1,
          payload:
            Map.merge(replacement_retry_correction_payload, %{
              "job_id" => replacement_retry_corrected_job.job_id,
              "job_type" => "telemetry_historical_data_workflow",
              "workflow_job_status" => "failed",
              "source" => %{
                "failure" => %{
                  "code" => "replacement_worker_failed",
                  "retryable" => true,
                  "retry_blockers" => [],
                  "recovery_action" => "retry_job"
                }
              }
            })
        }
      )

    replacement_retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: replacement_retry_source_failed_event.backfill_lifecycle_event_id
    }

    replacement_retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replacement_retry_query}"

    assert {replacement_retry_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-retry-workflow",
                 "--url",
                 replacement_retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert replacement_retry_output =~ "dashboard_viewport_smoke passed"

    assert [replacement_retry_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == replacement_retry_corrected_run_id))

    assert replacement_retry_retried_event.payload["retry_source_event_id"] ==
             replacement_retry_corrected_failed_event.backfill_lifecycle_event_id

    assert replacement_retry_retried_event.payload["retry_job_id"] ==
             replacement_retry_corrected_job.job_id

    assert replacement_retry_retried_event.payload["retry_job_status"] == "queued"

    assert replacement_retry_retried_event.payload["request_group_id"] ==
             replacement_retry_group_id

    assert {:ok, replacement_retry_requeued_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               replacement_retry_corrected_run_id
             )

    assert replacement_retry_requeued_job.status == :queued

    stale_group_id = "browser-smoke-workflow-stale-replacement-group"
    stale_source_run_id = "browser-smoke-workflow-stale-replacement-source"
    stale_corrected_run_id = "browser-smoke-workflow-stale-replacement-corrected"

    stale_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-stale-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    stale_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        stale_source_run_id,
        :stale_replacement_source_failed
      )

    stale_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: stale_source_run_id,
          point_id: "HK.gyro",
          request_group_id: stale_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => stale_dashboard_context,
            "job_id" => stale_source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    stale_correction_payload = %{
      "dashboard_context" => stale_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => stale_source_run_id,
      "corrects_event_id" => stale_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => stale_source_job.job_id
    }

    stale_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        stale_corrected_run_id,
        "HK.gyro",
        stale_group_id,
        1,
        1,
        dashboard_context: stale_dashboard_context
      )
      |> Map.put(:payload, stale_correction_payload)

    _stale_corrected_requested =
      record_backfill_workflow_event!(org, mission, "requested", stale_corrected_attrs)

    _stale_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", stale_corrected_attrs)

    stale_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", stale_corrected_attrs)

    stale_corrected_job =
      enqueue_stale_running_historical_workflow_job!(mission, stale_corrected_run_id)

    stale_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: stale_source_failed_event.backfill_lifecycle_event_id
    }

    stale_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{stale_query}"

    assert {stale_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-stale-workflow",
                 "--url",
                 stale_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert stale_output =~ "dashboard_viewport_smoke passed"

    assert [stale_requeue_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_stale_replacement_requeued
             )
             |> Enum.filter(&(&1.backfill_run_id == stale_corrected_run_id))

    assert stale_requeue_event.payload["stale_replacement_source_event_id"] ==
             stale_corrected_started.backfill_lifecycle_event_id

    assert stale_requeue_event.payload["stale_replacement_job_id"] ==
             stale_corrected_job.job_id

    assert stale_requeue_event.payload["stale_replacement_job_status"] == "running"

    assert stale_requeue_event.payload["stale_replacement_action"] ==
             "requeue_stale_replacement_job"

    assert stale_requeue_event.payload["stale_replacement_requeued_job_id"] ==
             stale_corrected_job.job_id

    assert stale_requeue_event.payload["stale_replacement_requeued_job_status"] == "queued"

    assert stale_requeue_event.payload["stale_replacement_requeued_failure_reason"] ==
             "dashboard_stale_replacement_requeued"

    assert {:ok, stale_requeued_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(stale_corrected_run_id)

    assert stale_requeued_job.status == :queued

    missing_job_group_id = "browser-smoke-workflow-missing-job-replacement-group"
    missing_job_source_run_id = "browser-smoke-workflow-missing-job-replacement-source"
    missing_job_corrected_run_id = "browser-smoke-workflow-missing-job-replacement-corrected"

    missing_job_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-missing-job-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    missing_job_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        missing_job_source_run_id,
        :missing_job_replacement_source_failed
      )

    missing_job_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: missing_job_source_run_id,
          point_id: "HK.power",
          request_group_id: missing_job_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => missing_job_dashboard_context,
            "job_id" => missing_job_source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    missing_job_correction_payload = %{
      "dashboard_context" => missing_job_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => missing_job_source_run_id,
      "corrects_event_id" => missing_job_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => missing_job_source_job.job_id
    }

    missing_job_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        missing_job_corrected_run_id,
        "HK.power",
        missing_job_group_id,
        1,
        1,
        dashboard_context: missing_job_dashboard_context
      )
      |> Map.put(:payload, missing_job_correction_payload)

    _missing_job_corrected_requested =
      record_backfill_workflow_event!(org, mission, "requested", missing_job_corrected_attrs)

    _missing_job_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", missing_job_corrected_attrs)

    _missing_job_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", missing_job_corrected_attrs)

    _missing_job_corrected_completed =
      record_backfill_workflow_event!(org, mission, "completed", missing_job_corrected_attrs)

    missing_job_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: missing_job_source_failed_event.backfill_lifecycle_event_id
    }

    missing_job_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{missing_job_query}"

    assert {missing_job_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-missing-job-workflow",
                 "--url",
                 missing_job_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert missing_job_output =~ "dashboard_viewport_smoke passed"

    assert {:error, :job_not_found} =
             Cadence.fetch_telemetry_historical_data_workflow_job(missing_job_corrected_run_id)

    mixed_group_id = "browser-smoke-workflow-mixed-replacement-group"
    mixed_missing_source_run_id = "browser-smoke-workflow-mixed-source-missing"
    mixed_failed_source_run_id = "browser-smoke-workflow-mixed-source-failed"
    mixed_stale_source_run_id = "browser-smoke-workflow-mixed-source-stale"
    mixed_missing_corrected_run_id = "browser-smoke-workflow-mixed-replacement-missing"
    mixed_failed_corrected_run_id = "browser-smoke-workflow-mixed-replacement-failed"
    mixed_stale_corrected_run_id = "browser-smoke-workflow-mixed-replacement-stale"

    mixed_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-mixed-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    mixed_source_events =
      [
        {mixed_missing_source_run_id, "HK.mixed_missing", 1},
        {mixed_failed_source_run_id, "HK.mixed_failed", 2},
        {mixed_stale_source_run_id, "HK.mixed_stale", 3}
      ]
      |> Enum.map(fn {run_id, point_id, index} ->
        source_job =
          enqueue_failed_historical_workflow_job!(
            mission,
            run_id,
            :"mixed_replacement_source_failed_#{index}"
          )

        event =
          record_backfill_workflow_event!(
            org,
            mission,
            "failed",
            %{
              run_id: run_id,
              point_id: point_id,
              request_group_id: mixed_group_id,
              item_index: index,
              item_count: 3,
              payload: %{
                "dashboard_context" => mixed_dashboard_context,
                "job_id" => source_job.job_id,
                "job_type" => "telemetry_historical_data_workflow",
                "workflow_job_status" => "failed",
                "source" => %{
                  "failure" => %{
                    "code" => "source_window_failed",
                    "retryable" => false,
                    "retry_blockers" => ["operator_correction_required"],
                    "recovery_action" => "correct_workflow_request"
                  }
                }
              }
            }
          )

        {run_id, point_id, source_job, event}
      end)

    mixed_correction_context =
      mixed_source_events
      |> Enum.zip([
        {mixed_missing_corrected_run_id, "HK.mixed_missing", 1},
        {mixed_failed_corrected_run_id, "HK.mixed_failed", 2},
        {mixed_stale_corrected_run_id, "HK.mixed_stale", 3}
      ])
      |> Enum.map(fn {{source_run_id, _source_point_id, source_job, source_event},
                      {corrected_run_id, corrected_point_id, index}} ->
        payload = %{
          "dashboard_context" => mixed_dashboard_context,
          "recovery_action" => "correct_workflow_request",
          "correction_source" => "dashboard_correction_request",
          "correction_source_event_type" => "backfill_failed",
          "corrects_run_id" => source_run_id,
          "corrects_event_id" => source_event.backfill_lifecycle_event_id,
          "corrects_job_id" => source_job.job_id
        }

        attrs =
          historical_workflow_item_attrs(
            org,
            mission,
            corrected_run_id,
            corrected_point_id,
            mixed_group_id,
            index,
            3,
            dashboard_context: mixed_dashboard_context
          )
          |> Map.put(:payload, payload)

        {corrected_run_id, attrs, payload, source_event}
      end)

    {^mixed_missing_corrected_run_id, mixed_missing_attrs, _mixed_missing_payload,
     mixed_missing_source_event} =
      Enum.at(mixed_correction_context, 0)

    {^mixed_failed_corrected_run_id, mixed_failed_attrs, mixed_failed_payload,
     _mixed_failed_source_event} =
      Enum.at(mixed_correction_context, 1)

    {^mixed_stale_corrected_run_id, mixed_stale_attrs, _mixed_stale_payload,
     _mixed_stale_source_event} =
      Enum.at(mixed_correction_context, 2)

    for stage <- ["requested", "approved", "started", "completed"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_missing_attrs)
    end

    for stage <- ["requested", "approved", "started"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_failed_attrs)
    end

    mixed_failed_corrected_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        mixed_failed_corrected_run_id,
        :mixed_replacement_corrected_failed
      )

    _mixed_failed_corrected_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: mixed_failed_corrected_run_id,
          point_id: "HK.mixed_failed",
          request_group_id: mixed_group_id,
          item_index: 2,
          item_count: 3,
          payload:
            Map.merge(mixed_failed_payload, %{
              "job_id" => mixed_failed_corrected_job.job_id,
              "job_type" => "telemetry_historical_data_workflow",
              "workflow_job_status" => "failed",
              "source" => %{
                "failure" => %{
                  "code" => "replacement_worker_failed",
                  "retryable" => true,
                  "retry_blockers" => [],
                  "recovery_action" => "retry_job"
                }
              }
            })
        }
      )

    for stage <- ["requested", "approved"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_stale_attrs)
    end

    _mixed_stale_started_event =
      record_backfill_workflow_event!(org, mission, "started", mixed_stale_attrs)

    _mixed_stale_job =
      enqueue_stale_running_historical_workflow_job!(mission, mixed_stale_corrected_run_id)

    mixed_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: mixed_missing_source_event.backfill_lifecycle_event_id
    }

    mixed_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{mixed_query}"

    assert {mixed_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-mixed-workflow",
                 "--url",
                 mixed_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert mixed_output =~ "dashboard_viewport_smoke passed"

    assert [
             %{event_type: :comparison_review_requested} = comparison_review_request,
             %{event_type: :comparison_review_resolved} = resolution
           ] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert comparison_review_request.payload["source"] == "dashboard_comparison_rollup"
    assert trend_widget.widget_id in comparison_review_request.payload["open_placement_ids"]

    assert resolution.payload["source_request_event_id"] ==
             comparison_review_request.dashboard_lifecycle_event_id

    assert resolution.payload["resolution_reason"] == "Resolved by browser smoke"
  end

  test "live comparison review bulk decision passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-bulk-decision-viewport",
        display_name: "Comparison Review Bulk Decision Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Bulk Decision")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Bulk Decision Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 1,
                 "open_placement_ids" => [counter_item.placement_id],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecision\""
    assert bulk_decision_output =~ "\"actionOutcome\""
    assert bulk_decision_output =~ "\"source_request_event_id\""

    Sandbox.allow(Cadence.Repo, sandbox_owner, self())

    assert [bulk_decision_event] =
             Storage.list_observation_identity_decision_events(
               observation_identity_state.observation_identity_id,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry"
             )

    assert bulk_decision_event.decision == :mark_conflict
    assert bulk_decision_event.actor_id == user.user_id
    assert bulk_decision_event.decision_reason == "dashboard_comparison_review_mark_conflict"
    assert bulk_decision_event.evidence_ref["kind"] == "dashboard_comparison_review_finding"

    assert bulk_decision_event.evidence_ref["bulk_workflow_item"]["workflow_id"] ==
             bulk_request.dashboard_lifecycle_event_id

    assert bulk_decision_event.evidence_ref["correction_workflow"]["id"] ==
             bulk_request.dashboard_lifecycle_event_id

    assert bulk_decision_event.evidence_ref["correction_workflow"]["requested_by"] ==
             "dashboard_comparison_review"
  end

  test "live comparison review partial bulk decision passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-partial-bulk-decision-viewport",
        display_name: "Comparison Review Partial Bulk Decision Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Bulk")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Partial Bulk Decision Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Missing Review Target",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.voltage"
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 2, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")
    missing_item = render_item_by_title(document, "Missing Review Target")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    missing_observation_identity_id = "missing-comparison-review-browser-identity"

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 2,
                 "open_placement_ids" => [
                   counter_item.placement_id,
                   missing_item.placement_id
                 ],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     },
                     %{
                       "placement_id" => missing_item.placement_id,
                       "title" => "Missing identity",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "observation_identity_id" => missing_observation_identity_id,
                       "primary_observation_identity_id" => missing_observation_identity_id,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision",
                 "--expected-bulk-decision-status",
                 "degraded",
                 "--expected-bulk-decision-status-label",
                 "Partial",
                 "--expected-bulk-decision-reason",
                 "comparison_review_bulk_decision_partially_applied",
                 "--expected-bulk-decision-applied",
                 "1",
                 "--expected-bulk-decision-failed",
                 "1",
                 "--expected-bulk-decision-message",
                 "Comparison review decisions applied to 1 findings; 1 failed.",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecision\""
    assert bulk_decision_output =~ "\"status\": \"degraded\""
    assert bulk_decision_output =~ "\"applied\": \"1\""
    assert bulk_decision_output =~ "\"failed\": \"1\""
  end

  test "live revision decision inspector preserves dashboard limit mode in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "revision-limit-mode-viewport",
        display_name: "Revision Limit Mode Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Browser")
    binding_set = persist_binding_set!(org, mission)
    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 37, base_unix,
      dashboard_runtime_invalidation?: false
    )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [initial_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert {:ok, _state} =
             Cadence.apply_telemetry_observation_identity_decision(
               initial_state.observation_identity_id,
               "mark_canonical",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 canonical_observation_id: initial_state.canonical_observation_id,
                 canonical_sample_id: initial_state.canonical_sample_id,
                 canonical_revision: initial_state.canonical_revision,
                 decision_reason: "browser_smoke_revision_source_marker",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-source-marker-1",
                   "source_target" => "comparison_finding",
                   "source_target_id" => "browser-placement-1",
                   "source_link_label" => "Comparison finding"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    [source_event] =
      Storage.list_observation_identity_decision_events(
        initial_state.observation_identity_id,
        query_opts
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Limit Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter",
            layout: %{x: 0, y: 0, w: 4, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Counter",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          },
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 4, y: 0, w: 6, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: [:events]
              },
              options: %{}
            }
          }
        ]
      )

    selected_query = %{
      limit_mode: "compare"
    }

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "revision-decision-limit-mode",
                 "--expected-limit-mode",
                 "compare",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"revisionDecisionLimitMode\""

    Sandbox.allow(Cadence.Repo, sandbox_owner, self())

    decision_events =
      Storage.list_observation_identity_decision_events(
        initial_state.observation_identity_id,
        query_opts
      )

    applied_event =
      Enum.find(
        decision_events,
        &(&1.evidence_ref["kind"] == "dashboard_revision_decision")
      )

    assert applied_event
    assert applied_event.decision == :mark_conflict
    assert applied_event.actor_id == user.user_id
    assert applied_event.actor_kind == "operator"
    assert applied_event.decision_reason == "browser_smoke_revision_conflict_compare"
    assert applied_event.evidence_ref["id"] == source_event.decision_event_id

    assert applied_event.evidence_ref["dashboard_context"] == %{
             "dashboard_limit_mode" => "compare"
           }

    assert {:ok, applied_state} =
             Storage.fetch_observation_identity_state(initial_state.observation_identity_id)

    assert applied_state.validity_state == :conflict
    assert applied_state.decision_event_id == applied_event.decision_event_id

    assert applied_state.payload["decision"]["evidence_ref"]["dashboard_context"] == %{
             "dashboard_limit_mode" => "compare"
           }
  end

  test "live telemetry revision range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "revision-range-marker-viewport",
        display_name: "Revision Range Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Range")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [initial_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    corrected_sample = %{
      initial_sample
      | sample_id: "browser-revision-range-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([corrected_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [revision_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert revision_state.latest_sample_id == corrected_sample.sample_id
    assert revision_state.validity_state == :conflict

    assert {:ok, decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_superseded_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-corrected-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert decided_state.validity_state == :superseded
    assert decided_state.latest_sample_id == corrected_sample.sample_id

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Range Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Revision Range",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"telemetryRevisionRangeEvidence\""
  end

  test "live telemetry advisory backfill range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "advisory-backfill-marker-viewport",
        display_name: "Advisory Backfill Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Advisory Backfill")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [initial_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    advisory_sample = %{
      initial_sample
      | sample_id: "browser-revision-range-advisory-sample",
        raw_value: 39,
        engineering_value: 39
    }

    assert :ok =
             Storage.persist_samples([advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [revision_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert revision_state.latest_sample_id == advisory_sample.sample_id
    assert revision_state.validity_state == :conflict

    assert {:ok, decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               revision_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_advisory_backfill_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-advisory-backfill-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert decided_state.validity_state == :advisory
    assert decided_state.latest_sample_id == advisory_sample.sample_id

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Advisory Backfill Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Advisory Backfill Range",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "advisory_backfill",
                 "--expected-revision-state",
                 "backfill",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"telemetryRevisionRangeEvidence\""
  end

  test "live telemetry mixed revision range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mixed-revision-marker-viewport",
        display_name: "Mixed Revision Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Mixed Revision")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [corrected_initial_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    advisory_initial_sample = %Sample{
      sample_id: "browser-mixed-revision-voltage-initial-sample",
      mission_id: mission.mission_id,
      spacecraft_id: spacecraft.spacecraft_id,
      point_id: "HK.voltage",
      point_name: "HK.voltage",
      packet_definition_id: corrected_initial_sample.packet_definition_id,
      packet_definition_version: corrected_initial_sample.packet_definition_version,
      packet_id: corrected_initial_sample.packet_id,
      evidence_id: corrected_initial_sample.evidence_id,
      raw_value: 120,
      engineering_value: 120,
      quality_state: :good,
      generation_time: sample_time,
      receipt_time: sample_time,
      provenance: %{}
    }

    assert :ok =
             Storage.persist_samples([advisory_initial_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    corrected_sample = %{
      corrected_initial_sample
      | sample_id: "browser-mixed-revision-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    advisory_sample = %{
      advisory_initial_sample
      | sample_id: "browser-mixed-revision-advisory-sample",
        raw_value: 122,
        engineering_value: 122
    }

    assert :ok =
             Storage.persist_samples([corrected_sample, advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    revision_states =
      Storage.list_observation_identity_states(
        mission.mission_id,
        query_opts
      )

    assert length(revision_states) == 2

    corrected_state =
      Enum.find(revision_states, &(&1.latest_sample_id == corrected_sample.sample_id))

    advisory_state =
      Enum.find(revision_states, &(&1.latest_sample_id == advisory_sample.sample_id))

    assert corrected_state.validity_state == :conflict
    assert advisory_state.validity_state == :conflict

    assert {:ok, corrected_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               corrected_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_mixed_corrected_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-mixed-corrected-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, advisory_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               advisory_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_mixed_advisory_backfill_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-mixed-advisory-backfill-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert corrected_decided_state.validity_state == :superseded
    assert advisory_decided_state.validity_state == :advisory

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Mixed Revision Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Mixed Revision Range",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    shared_marker_args = [
      "--expected-revision-warning-codes",
      "corrected_range,advisory_backfill"
    ]

    assert {corrected_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected"
               ] ++
                 shared_marker_args ++
                 [
                   "--url",
                   dashboard_url,
                   "--login-url",
                   base_url <> ~p"/sign-in",
                   "--login-email",
                   user.email,
                   "--login-password",
                   TestFixtures.default_password()
                 ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert corrected_output =~ "dashboard_viewport_smoke passed"
    assert corrected_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {advisory_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "advisory_backfill",
                 "--expected-revision-state",
                 "backfill",
                 "--expected-revision-evidence-subject",
                 "HK.voltage"
               ] ++
                 shared_marker_args ++
                 [
                   "--url",
                   dashboard_url,
                   "--login-url",
                   base_url <> ~p"/sign-in",
                   "--login-email",
                   user.email,
                   "--login-password",
                   TestFixtures.default_password()
                 ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert advisory_output =~ "dashboard_viewport_smoke passed"
    assert advisory_output =~ "\"telemetryRevisionRangeEvidence\""

    counter_only_dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Counter Only Mixed Revision Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Only Revision Range",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    counter_only_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{counter_only_dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {counter_only_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected",
                 "--expected-revision-warning-codes",
                 "corrected_range",
                 "--absent-revision-warning-codes",
                 "advisory_backfill",
                 "--url",
                 counter_only_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert counter_only_output =~ "dashboard_viewport_smoke passed"
    assert counter_only_output =~ "\"telemetryRevisionRangeEvidence\""
  end

  test "live telemetry revision range markers stay scoped to source binding and data view in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "revision-source-binding-isolation-viewport",
        display_name: "Revision Source Binding Isolation Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Binding")
    binding_set = persist_binding_set!(org, mission)
    alternate_binding_id = "alternate_flight_telemetry"

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    assert {:ok, _alternate_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | binding_id: alternate_binding_id,
                 dataset: "alternate-flight",
                 priority: 1,
                 metadata: %{test_binding?: true}
             })

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [default_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    alternate_initial_sample = %{
      default_sample
      | sample_id: "browser-source-binding-alt-initial-sample"
    }

    assert :ok =
             Storage.persist_samples([alternate_initial_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: alternate_binding_id,
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    alternate_corrected_sample = %{
      alternate_initial_sample
      | sample_id: "browser-source-binding-alt-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([alternate_corrected_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: alternate_binding_id,
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    alternate_query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: alternate_binding_id,
      point_id: "HK.counter"
    ]

    [alternate_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id, alternate_query_opts)

    assert alternate_revision_state.latest_sample_id == alternate_corrected_sample.sample_id
    assert alternate_revision_state.validity_state == :conflict

    assert {:ok, alternate_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               alternate_revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: alternate_binding_id,
                 decision_reason: "browser_smoke_source_binding_isolation",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-source-binding-isolation-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert alternate_decided_state.validity_state == :superseded

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Source Binding Isolation Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Revision Source Binding Isolation",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_path = ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    alternate_all_revisions_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: alternate_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    default_all_revisions_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    alternate_canonical_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "canonical", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: alternate_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {alternate_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected",
                 "--expected-revision-source-binding-id",
                 alternate_binding_id,
                 "--url",
                 alternate_all_revisions_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert alternate_output =~ "dashboard_viewport_smoke passed"
    assert alternate_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {default_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-absence",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--url",
                 default_all_revisions_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert default_output =~ "dashboard_viewport_smoke passed"
    assert default_output =~ "\"telemetryRevisionRangeAbsence\""

    assert {canonical_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "rendered-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-absence",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--allow-missing-revision-chart",
                 "--url",
                 alternate_canonical_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert canonical_output =~ "dashboard_viewport_smoke passed"
    assert canonical_output =~ "\"telemetryRevisionRangeAbsence\""
  end

  test "live telemetry revision range markers stay scoped to replay realm in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-revision-marker-isolation-viewport",
        display_name: "Replay Revision Marker Isolation Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Revision")
    binding_set = persist_binding_set!(org, mission)
    replay_run_id = "browser-replay-revision-marker"
    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    persist_replay_run!(mission, replay_run_id, sample_time)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [flight_initial_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    flight_advisory_sample = %{
      flight_initial_sample
      | sample_id: "browser-realm-flight-advisory-sample",
        raw_value: 39,
        engineering_value: 39
    }

    assert :ok =
             Storage.persist_samples([flight_advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    replay_initial_sample = %{
      flight_initial_sample
      | sample_id: "browser-realm-replay-initial-sample"
    }

    assert :ok =
             Storage.persist_samples([replay_initial_sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: replay_sources.telemetry_data_source_id,
               binding_id: replay_sources.telemetry_binding_id,
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    replay_corrected_sample = %{
      replay_initial_sample
      | sample_id: "browser-realm-replay-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([replay_corrected_sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: replay_sources.telemetry_data_source_id,
               binding_id: replay_sources.telemetry_binding_id,
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    insert_replay_persisted_telemetry_samples!(
      [replay_initial_sample.sample_id, replay_corrected_sample.sample_id],
      replay_run_id
    )

    [flight_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: DataSources.default_managed_data_source().data_source_id,
        binding_id: "default_flight_telemetry",
        point_id: "HK.counter"
      )

    [replay_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :replay,
        replay_run_id: replay_run_id,
        data_source_id: replay_sources.telemetry_data_source_id,
        binding_id: replay_sources.telemetry_binding_id,
        point_id: "HK.counter"
      )

    assert flight_revision_state.latest_sample_id == flight_advisory_sample.sample_id
    assert replay_revision_state.latest_sample_id == replay_corrected_sample.sample_id

    assert {:ok, flight_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               flight_revision_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_realm_flight_advisory",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-realm-flight-advisory-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replay_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               replay_revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 data_source_id: replay_sources.telemetry_data_source_id,
                 binding_id: replay_sources.telemetry_binding_id,
                 decision_reason: "browser_smoke_realm_replay_corrected",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-realm-replay-corrected-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert flight_decided_state.validity_state == :advisory
    assert replay_decided_state.validity_state == :superseded

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Revision Marker Isolation Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Replay Revision Isolation",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"
    dashboard_path = ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    flight_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    replay_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "replay_run", replay_run_id: replay_run_id, data_view: "all_revisions", data_source_id: replay_sources.telemetry_data_source_id, source_binding_id: replay_sources.telemetry_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    assert {flight_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "advisory_backfill",
                 "--expected-revision-state",
                 "backfill",
                 "--expected-revision-warning-codes",
                 "advisory_backfill",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--url",
                 flight_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert flight_output =~ "dashboard_viewport_smoke passed"
    assert flight_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {replay_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected",
                 "--expected-revision-warning-codes",
                 "corrected_range",
                 "--absent-revision-warning-codes",
                 "advisory_backfill",
                 "--expected-revision-data-source-id",
                 replay_sources.telemetry_data_source_id,
                 "--expected-revision-source-binding-id",
                 replay_sources.telemetry_binding_id,
                 "--expected-revision-replay-run-id",
                 replay_run_id,
                 "--url",
                 replay_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert replay_output =~ "dashboard_viewport_smoke passed"
    assert replay_output =~ "\"telemetryRevisionRangeEvidence\""
  end

  test "live telemetry watermark fallback markers open source evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    source_watermark_config =
      Application.get_env(:cadence, :dashboard_source_watermark_events, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    Application.put_env(
      :cadence,
      :dashboard_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )

      Application.put_env(:cadence, :dashboard_source_watermark_events, source_watermark_config)
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "telemetry-watermark-marker-viewport",
        display_name: "Telemetry Watermark Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Marker")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _events_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_events_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _events_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_events_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      27,
      DateTime.to_unix(~U[2026-06-16 00:20:00Z])
    )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      29,
      DateTime.to_unix(~U[2026-06-16 00:30:00Z])
    )

    assert {:ok, watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 complete_through: ~U[2026-06-16 00:30:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:30:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 2,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:30:30Z],
                 payload: %{write_id: "browser-telemetry-time-series-watermark-event"}
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, unrelated_watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: "alternate_flight_telemetry",
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 complete_through: ~U[2026-06-16 00:31:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:31:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:31:30Z],
                 payload: %{write_id: "browser-unrelated-telemetry-time-series-watermark-event"}
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, unrelated_dataset_watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: "alternate_flight_dataset",
                 complete_through: ~U[2026-06-16 00:32:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:32:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:32:30Z],
                 payload: %{
                   write_id: "browser-unrelated-dataset-telemetry-time-series-watermark-event"
                 }
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Telemetry Watermark Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Retention Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: [:events]
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: DataSources.default_flight_telemetry_binding().binding_id, dataset: DataSources.default_flight_telemetry_binding().dataset, from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-watermark-marker-evidence",
                 "--expected-source-watermark-event-id",
                 watermark_event.source_watermark_event_id,
                 "--absent-source-watermark-event-ids",
                 [
                   unrelated_watermark_event.source_watermark_event_id,
                   unrelated_dataset_watermark_event.source_watermark_event_id
                 ]
                 |> Enum.join(","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"telemetryWatermarkMarkerEvidence\""
  end

  test "live replay telemetry watermark fallback markers open replay source evidence in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-telemetry-watermark-marker-viewport",
        display_name: "Replay Telemetry Watermark Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Marker")
    binding_set = persist_binding_set!(org, mission)
    replay_run_id = "browser-replay-watermark-marker"

    persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, ~U[2026-06-16 00:20:00Z])

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      27,
      DateTime.to_unix(~U[2026-06-16 00:20:00Z])
    )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      29,
      DateTime.to_unix(~U[2026-06-16 00:30:00Z])
    )

    samples =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    assert length(samples) == 2
    insert_replay_telemetry_samples!(samples, replay_run_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Telemetry Watermark Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Replay Counter Retention Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "replay_run", replay_run_id: replay_run_id, from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-watermark-marker-evidence",
                 "--expected-time-mode",
                 "replay_run",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"telemetryWatermarkMarkerEvidence\""
  end

  test "live BYO source readiness inventory passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "byo-source-readiness-viewport",
        display_name: "BYO Source Readiness Viewport"
      )

    credentials_ref = "cred-browser-byo-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "byo-browser-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{
                 endpoint_ref: "endpoint://browser/customer-questdb",
                 http_endpoint: "http://browser-customer-questdb:9000"
               }
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-browser-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://browser/customer-questdb"
               }
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "byo-browser-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "byo-browser-questdb",
               dataset: "flight",
               priority: 0
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "byo-browser-questdb",
                 source_binding_id: "byo-browser-flight",
                 realm: :flight,
                 dataset: "flight",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "adapter",
                   probe_message: "QuestDB schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Adapter connection test succeeded.",
                   probe_metadata: %{
                     adapter: "telemetry",
                     storage: "questdb",
                     connection_profile?: true,
                     source_connection_profile: %{
                       credentials_ref: credentials_ref,
                       credential_provider: "questdb",
                       credential_kind: "byo_tsdb_connection",
                       credential_owner: "customer",
                       credential_version: 1,
                       credential_status: "active",
                       data_source_id: "byo-browser-questdb",
                       data_source_kind: "byo_tsdb",
                       data_source_owner: "customer",
                       isolation_level: "customer_owned",
                       endpoint_ref: "endpoint://browser/customer-questdb",
                       http_endpoint: "http://browser-customer-questdb:9000",
                       secret_material?: true,
                       secret_material_fields: ["bearer_token", "headers"]
                     }
                   }
                 }
               },
               invalidate_runtime_cache?: false
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    data_sources_url = base_url <> ~p"/missions/#{mission.mission_id}/ops/data-sources"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-data-sources",
                 "--interaction-mode",
                 "byo-source-readiness",
                 "--url",
                 data_sources_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational source product publish blocker passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-source-product-readiness-viewport",
        display_name: "Operational Source Product Readiness Viewport"
      )

    for {data_source_id, products} <- [
          {"browser-operational-bitrate-source", [:transport_bitrate_history]},
          {"browser-operational-bitrate-history", [:transport_bitrate_history]},
          {"browser-operational-rf-history", [:link_rf_metric_history]}
        ] do
      assert {:ok, _source} =
               DataSources.persist_data_source(%DataSource{
                 data_source_id: data_source_id,
                 owner: :cadence,
                 kind: :managed_tsdb,
                 adapter: Cadence.Dashboards.Sources.OperationalObservables,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 isolation_level: :mission_isolated,
                 capabilities: %{
                   latest?: true,
                   range_scan?: true,
                   supported_products: products
                 },
                 metadata: %{storage: :postgres_projection}
               })
    end

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "browser-operational-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :operational_observables,
               data_source_id: "browser-operational-bitrate-source",
               dataset: "operational_observables",
               priority: 0
             })

    document = %Document{
      dashboard_id: "dashboard-operational-source-product-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Operational Source Product Readiness Browser",
      placements: [
        %Placement{
          placement_id: "placement-browser-rf-product-mismatch",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR History",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: []
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, dashboard} = Cadence.Dashboards.persist_document(org.organization_id, document)

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}"

    source_inventory_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "browser-operational-bitrate-source", source_binding_id: "browser-operational-flight", logical_source: "operational_observables", realm: "flight", source_dashboard_id: dashboard.dashboard_id, source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "raw_series", supported_sampling: "latest,event_history,raw_series", requested_products: "link_rf", requested_source_products: "link_rf_metric_history", supported_products: "transport_bitrate_history", requested_product_families: "link_rf", supported_product_families: "transport_bitrate"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-source-product-readiness",
                 "--source-inventory-url",
                 source_inventory_url,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"operationalSourceProductReadiness\""
  end

  test "live operational source product runtime posture passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-source-product-runtime-viewport",
        display_name: "Operational Source Product Runtime Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "browser-operational-rf-runtime-source",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: true,
                 supported_products: [:operational_metric_history]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "browser-operational-rf-runtime-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :operational_observables,
               data_source_id: "browser-operational-rf-runtime-source",
               dataset: "operational_observables",
               priority: 0
             })

    document = %Document{
      dashboard_id: "dashboard-operational-source-runtime-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Operational Source Product Runtime Browser",
      placements: [
        %Placement{
          placement_id: "placement-browser-rf-product-runtime",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR Runtime History",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: []
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, dashboard} = Cadence.Dashboards.persist_document(org.organization_id, document)

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-source-product-runtime",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"operationalSourceProductRuntime\""
  end

  test "live authenticated replay controls preserve replay limit context in browser",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-controls-viewport",
        display_name: "Replay Controls Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay")
    binding_set = persist_binding_set!(org, mission)
    seed_limit_definition!(mission)

    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 25, base_unix)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 26, base_unix + 10)

    [older_sample, latest_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    replay_run_id = "browser-smoke-replay-run"
    persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)

    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        status: :completed,
        replayed_evidence_count: 2,
        replayed_packet_count: 2,
        replayed_sample_count: 2,
        started_at: DateTime.add(older_sample.receipt_time, -60, :second),
        completed_at: DateTime.add(older_sample.receipt_time, 60, :second)
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
    insert_replay_telemetry_samples!([older_sample, latest_sample], replay_run_id)
    insert_replay_limit_events!(mission, spacecraft, [older_sample, latest_sample], replay_run_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Controls Power",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    replay_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      limit_mode: "compare",
      from: older_sample.receipt_time |> DateTime.add(-600, :second) |> DateTime.to_iso8601(),
      to: older_sample.receipt_time |> DateTime.add(600, :second) |> DateTime.to_iso8601()
    }

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-limits",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-limit-mode",
                 "compare",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay mission timeline renders managed runtime operational events in browser",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-managed-runtime-timeline-viewport",
        display_name: "Replay Managed Runtime Timeline Viewport"
      )

    replay_run_id = "browser-managed-runtime-replay-run"
    other_replay_run_id = "browser-managed-runtime-other-replay-run"
    event_time = ~U[2026-06-30 12:06:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, event_time)
    persist_replay_run!(mission, other_replay_run_id, event_time)

    assert {:ok, matching_event} =
             managed_action_operational_event(
               org.organization_id,
               mission.mission_id,
               "matching",
               event_time,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_event} =
             managed_action_operational_event(
               org.organization_id,
               mission.mission_id,
               "other",
               event_time,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Runtime Timeline",
        widgets: [
          %{
            type: :event_timeline,
            title: "Replay Mission Events",
            binding: %{source: :events, observables: []},
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    dashboard =
      persist_dashboard_defaults!(org, mission, dashboard, %{
        "data" => %{
          "realm" => "replay",
          "source_mode" => "specific",
          "source_contexts" => %{
            "events" => %{
              "source_binding_id" => replay_sources.events_binding_id
            }
          }
        }
      })

    replay_query = %{
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      from: event_time |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
      to: event_time |> DateTime.add(60, :second) |> DateTime.to_iso8601()
    }

    conn = TestFixtures.member_conn(user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"
      )

    render_async(view, 5_000)

    assert has_element?(
             view,
             ~s([data-event-timeline-replay-run-id="#{replay_run_id}"][data-event-timeline-record-id="#{matching_event.event_id}"])
           )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-mission-timeline-managed-runtime",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-event-id",
                 matching_event.event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay contact interval event timeline DataLinks pass browser smoke",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-contact-interval-timeline-viewport",
        display_name: "Replay Contact Interval Timeline Viewport"
      )

    replay_run_id = "browser-contact-interval-replay-run"
    other_replay_run_id = "browser-contact-interval-other-replay-run"
    contact_id = "browser-replay-contact-alpha"
    other_contact_id = "browser-replay-contact-beta"
    source_endpoint_ref = "browser-replay-source-endpoint-alpha"
    starts_at = ~U[2026-06-30 12:01:00Z]
    ends_at = ~U[2026-06-30 12:04:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, starts_at)
    persist_replay_run!(mission, other_replay_run_id, starts_at)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: starts_at,
        ends_at: ends_at
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, matching_event} =
             contact_interval_operational_event(
               org.organization_id,
               mission.mission_id,
               contact_id,
               source_endpoint_ref,
               starts_at,
               ends_at,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_event} =
             contact_interval_operational_event(
               org.organization_id,
               mission.mission_id,
               other_contact_id,
               "browser-replay-source-endpoint-beta",
               starts_at,
               ends_at,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Contact Interval Timeline",
        widgets: [
          %{
            type: :event_timeline,
            title: "Replay Contact Events",
            binding: %{source: :events, observables: []},
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    dashboard =
      persist_dashboard_defaults!(org, mission, dashboard, %{
        "data" => %{
          "realm" => "replay",
          "source_mode" => "specific",
          "source_contexts" => %{
            "events" => %{
              "source_binding_id" => replay_sources.events_binding_id
            }
          }
        }
      })

    replay_query = %{
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      from: starts_at |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
      to: ends_at |> DateTime.add(60, :second) |> DateTime.to_iso8601()
    }

    conn = TestFixtures.member_conn(user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"
      )

    render_async(view, 5_000)

    assert has_element?(
             view,
             ~s([data-event-timeline-record-id="#{contact_id}"][data-event-timeline-replay-run-id="#{replay_run_id}"][data-event-timeline-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    refute has_element?(view, ~s([data-event-timeline-record-id="#{other_contact_id}"]))

    assert has_element?(
             view,
             ~s([data-event-timeline-row-link-target="contact"][data-event-timeline-row-link-id="#{contact_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    assert has_element?(
             view,
             ~s([data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{matching_event.event_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-contact-interval",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-contact-id",
                 contact_id,
                 "--expected-operational-event-id",
                 matching_event.event_id,
                 "--expected-source-endpoint-id",
                 source_endpoint_ref,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live contact no-data evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-no-data-viewport",
        display_name: "Contact No Data Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Contact Empty")
    binding_set = persist_binding_set!(org, mission)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-runtime-empty-contact",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: DateTime.from_unix!(1_700_000_080, :second),
        ends_at: DateTime.from_unix!(1_700_000_220, :second)
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-beta"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Empty Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "contact-no-data",
                 "--expected-contact-id",
                 scheduled_contact.scheduled_contact_id,
                 "--expected-source-endpoint-id",
                 "source-endpoint-alpha",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live contact phase state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-timeline-viewport",
        display_name: "Contact Phase Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    contact_id = "browser-contact-phase-alpha"
    realized_contact_id = "browser-contact-phase-alpha-run"
    source_endpoint_ref = "browser-contact-phase-source-endpoint-alpha"

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: realized_contact_id
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: contact_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-contact-phase-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-contact-phase-source-endpoint-beta"],
        paths: contact_paths("browser-contact-phase-source-endpoint-beta"),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert {:ok, _beta_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-timeline",
                 "--expected-contact-id",
                 contact_id,
                 "--expected-realized-contact-id",
                 realized_contact_id,
                 "--expected-source-endpoint-id",
                 source_endpoint_ref,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay contact phase state timeline preserves replay context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-replay-timeline-viewport",
        display_name: "Contact Phase Replay Timeline Viewport"
      )

    replay_run_id = "browser-contact-phase-replay-run"
    from_time = ~U[2026-06-30 12:00:00Z]
    to_time = ~U[2026-06-30 12:10:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)

    contact_id = "browser-contact-phase-replay-alpha"
    realized_contact_id = "browser-contact-phase-replay-alpha-run"
    source_endpoint_ref = "browser-contact-phase-replay-source-alpha"

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: realized_contact_id
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: contact_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-contact-phase-replay-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-contact-phase-replay-source-beta"],
        paths: contact_paths("browser-contact-phase-replay-source-beta"),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert {:ok, _beta_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Contact Phase Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    dashboard =
      persist_dashboard_defaults!(org, mission, dashboard, %{
        "data" => %{
          "realm" => "replay",
          "source_mode" => "specific",
          "source_contexts" => %{
            "operational_observables" => %{
              "data_source_id" => replay_sources.operational_data_source_id,
              "source_binding_id" => replay_sources.operational_binding_id,
              "dataset" => "operational_observables_replay"
            }
          }
        }
      })

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: contact_id, time_mode: "replay_run", replay_run_id: replay_run_id, realm: "replay", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-replay-timeline",
                 "--expected-contact-id",
                 contact_id,
                 "--expected-realized-contact-id",
                 realized_contact_id,
                 "--expected-source-endpoint-id",
                 source_endpoint_ref,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-data-source-id",
                 replay_sources.operational_data_source_id,
                 "--expected-source-binding-id",
                 replay_sources.operational_binding_id,
                 "--expected-dataset",
                 "operational_observables_replay",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-contact contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-contact-viewport",
        display_name: "Contact Phase Multi Contact Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_contact_id = "browser-contact-phase-multi-alpha"
    alpha_realized_contact_id = "browser-contact-phase-multi-alpha-run"
    beta_contact_id = "browser-contact-phase-multi-beta"
    gamma_contact_id = "browser-contact-phase-multi-gamma"

    alpha_endpoint_ref = "browser-contact-phase-multi-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-source-gamma"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, gamma_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Contact Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = Enum.join([alpha_contact_id, beta_contact_id], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-contact-timeline",
                 "--excluded-contact-id",
                 gamma_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live mission contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-mission-viewport",
        display_name: "Contact Phase Mission Viewport"
      )

    other_mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-other-mission-viewport",
        display_name: "Contact Phase Other Mission Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_contact_id = "browser-contact-phase-mission-alpha"
    alpha_realized_contact_id = "browser-contact-phase-mission-alpha-run"
    beta_contact_id = "browser-contact-phase-mission-beta"
    gamma_contact_id = "browser-contact-phase-mission-gamma"
    other_contact_id = "browser-contact-phase-mission-other"

    alpha_endpoint_ref = "browser-contact-phase-mission-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-mission-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-mission-source-gamma"
    other_endpoint_ref = "browser-contact-phase-mission-source-other"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    other_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: other_contact_id,
        mission_id: other_mission.mission_id,
        source_endpoint_refs: [other_endpoint_ref],
        paths: contact_paths(other_endpoint_ref),
        starts_at: ~U[2026-06-30 12:04:00Z],
        ends_at: ~U[2026-06-30 12:07:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, gamma_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, other_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Mission Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    contact_ids = Enum.join([alpha_contact_id, beta_contact_id, gamma_contact_id], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-mission-timeline",
                 "--expected-contact-ids",
                 contact_ids,
                 "--excluded-contact-id",
                 other_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live spacecraft contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-spacecraft-viewport",
        display_name: "Contact Phase Spacecraft Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_id: "browser-contact-phase-spacecraft-alpha",
        display_name: "Contact Phase Alpha"
      )

    beta_spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_id: "browser-contact-phase-spacecraft-beta",
        display_name: "Contact Phase Beta"
      )

    alpha_contact_id = "browser-contact-phase-spacecraft-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-spacecraft-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-spacecraft-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-spacecraft-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-spacecraft-source-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        spacecraft_id: alpha_spacecraft.spacecraft_id,
        display_name: "Contact Phase Spacecraft Source Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        spacecraft_id: beta_spacecraft.spacecraft_id,
        display_name: "Contact Phase Spacecraft Source Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Spacecraft Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: alpha_spacecraft.spacecraft_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-spacecraft-timeline",
                 "--expected-spacecraft-id",
                 alpha_spacecraft.spacecraft_id,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-source-endpoint-viewport",
        display_name: "Contact Phase Source Endpoint Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_contact_id = "browser-contact-phase-source-endpoint-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-source-endpoint-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-source-endpoint-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-source-endpoint-alpha"
    beta_endpoint_ref = "browser-contact-phase-source-endpoint-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Source Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Source Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Source Endpoint Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint_ref}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-source-endpoint-timeline",
                 "--expected-source-endpoint-id",
                 alpha_endpoint_ref,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live ground-station contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-ground-station-viewport",
        display_name: "Contact Phase Ground Station Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-ground-station-alpha",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Alpha",
        provider: "DSN",
        region: "Alpha"
      })

    beta_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-ground-station-beta",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Beta",
        provider: "DSN",
        region: "Beta"
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, alpha_station)

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, beta_station)

    alpha_contact_id = "browser-contact-phase-ground-station-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-ground-station-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-ground-station-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-ground-station-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-ground-station-source-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Source Alpha",
        metadata: %{"ground_station_id" => alpha_station.ground_station_id}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Source Beta",
        metadata: %{"ground_station_id" => beta_station.ground_station_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Ground Station Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: alpha_station.ground_station_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-ground-station-timeline",
                 "--expected-ground-station-id",
                 alpha_station.ground_station_id,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-source-endpoint contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-source-endpoint-viewport",
        display_name: "Contact Phase Multi Source Endpoint Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint_ref = "browser-contact-phase-multi-source-endpoint-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-source-endpoint-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-source-endpoint-gamma"

    for {endpoint_ref, display_name} <- [
          {alpha_endpoint_ref, "Contact Phase Multi Source Endpoint Alpha"},
          {beta_endpoint_ref, "Contact Phase Multi Source Endpoint Beta"},
          {gamma_endpoint_ref, "Contact Phase Multi Source Endpoint Gamma"}
        ] do
      endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: endpoint_ref,
          mission_id: mission.mission_id,
          display_name: display_name
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_contact_id = "browser-contact-phase-multi-source-endpoint-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-multi-source-endpoint-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-multi-source-endpoint-beta-contact"
    gamma_contact_id = "browser-contact-phase-multi-source-endpoint-gamma-contact"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    for contact <- [beta_contact, gamma_contact] do
      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, contact)
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Source Endpoint Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = Enum.join([alpha_endpoint_ref, beta_endpoint_ref], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-source-endpoint-timeline",
                 "--expected-contact-ids",
                 Enum.join([alpha_contact_id, beta_contact_id], ","),
                 "--excluded-contact-id",
                 gamma_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-ground-station contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-ground-station-viewport",
        display_name: "Contact Phase Multi Ground Station Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-alpha",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Alpha",
        provider: "DSN",
        region: "Alpha"
      })

    beta_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-beta",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Beta",
        provider: "DSN",
        region: "Beta"
      })

    gamma_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-gamma",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Gamma",
        provider: "DSN",
        region: "Gamma"
      })

    for station <- [alpha_station, beta_station, gamma_station] do
      assert {:ok, _ground_station} =
               Cadence.persist_ground_station(org.organization_id, station)
    end

    alpha_endpoint_ref = "browser-contact-phase-multi-ground-station-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-ground-station-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-ground-station-source-gamma"

    for {endpoint_ref, station, display_name} <- [
          {alpha_endpoint_ref, alpha_station, "Contact Phase Multi Ground Station Source Alpha"},
          {beta_endpoint_ref, beta_station, "Contact Phase Multi Ground Station Source Beta"},
          {gamma_endpoint_ref, gamma_station, "Contact Phase Multi Ground Station Source Gamma"}
        ] do
      endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: endpoint_ref,
          mission_id: mission.mission_id,
          display_name: display_name,
          metadata: %{"ground_station_id" => station.ground_station_id}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_contact_id = "browser-contact-phase-multi-ground-station-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-multi-ground-station-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-multi-ground-station-beta-contact"
    gamma_contact_id = "browser-contact-phase-multi-ground-station-gamma-contact"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    for contact <- [beta_contact, gamma_contact] do
      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, contact)
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Ground Station Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = Enum.join([alpha_station.ground_station_id, beta_station.ground_station_id], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-ground-station-timeline",
                 "--expected-contact-ids",
                 Enum.join([alpha_contact_id, beta_contact_id], ","),
                 "--excluded-contact-id",
                 gamma_contact_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint no-data evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-no-data-viewport",
        display_name: "Source Endpoint No Data Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Endpoint Empty")
    binding_set = persist_binding_set!(org, mission)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-runtime-empty-endpoint",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Endpoint",
        metadata: %{"ground_station_id" => "dss-browser-empty"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-beta"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Endpoint Empty Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          },
          %{
            type: :data_table,
            title: "Counter Rows",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 6, y: 0, w: 6, h: 3}
          },
          %{
            type: :status_matrix,
            title: "Counter Matrix",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 3, w: 6, h: 3}
          },
          %{
            type: :state_timeline,
            title: "Counter Limit State",
            binding: %{
              mode: :fixed,
              source: :limits,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 6, y: 3, w: 6, h: 3}
          },
          %{
            type: :event_timeline,
            title: "Endpoint Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 0, y: 6, w: 12, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: source_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-endpoint-no-data",
                 "--expected-source-endpoint-id",
                 source_endpoint.source_endpoint_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live partial telemetry time-series lifecycle passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-time-series-viewport",
        display_name: "Partial Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Series")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    sample_unix = DateTime.to_unix(sample_time, :second)

    assert {:ok, first_ingest_result} =
             ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, sample_unix)

    assert {:ok, second_ingest_result} =
             ingest!(mission, binding_set, spacecraft.spacecraft_id, 19, sample_unix + 1)

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Partial Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-partial-time-series",
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"partialTelemetryTimeSeries\""
  end

  test "live source-unavailable telemetry time-series blocks chart rendering in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [history_fun: &browser_source_unavailable_history/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-unavailable-telemetry-time-series-viewport",
        display_name: "Source Unavailable Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Series")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Unavailable Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-unavailable-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-source-unavailable-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"sourceUnavailableTelemetryTimeSeries\""
  end

  test "live source-degraded telemetry time-series preserves chart data in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous_source_execution
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:source_opts, %{
        telemetry: [watermark_fun: &browser_fresh_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)

      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-degraded-telemetry-time-series-viewport",
        display_name: "Source Degraded Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Degraded Series")

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               21,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               23,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "connection_test",
                   probe_message: "Telemetry source probe completed with warnings.",
                   connection_test_result: "degraded",
                   connection_test_kind: "questdb",
                   connection_test_message: "QuestDB responded with degraded health."
                 }
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Degraded Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-degraded-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Source Degraded Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-degraded-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-source-degraded-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"sourceDegradedTelemetryTimeSeries\""
  end

  test "live stale telemetry time-series preserves chart data and source evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_stale_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-telemetry-time-series-viewport",
        display_name: "Stale Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Stale Series")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               31,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               33,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Stale Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{
                health: %{
                  freshness_policy: %{stale_after_ms: 1000}
                }
              }
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-stale-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"staleTelemetryTimeSeries\""
  end

  test "live unknown-watermark telemetry time-series preserves chart data and source evidence in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_unknown_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "unknown-watermark-telemetry-time-series-viewport",
        display_name: "Unknown Watermark Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Unknown Watermark Series")

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               41,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               43,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unknown Watermark Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-unknown-watermark-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Unknown Watermark Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{
                health: %{
                  freshness_policy: %{stale_after_ms: 1000}
                }
              }
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "unknown-watermark-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-unknown-watermark-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"unknownWatermarkTelemetryTimeSeries\""
  end

  test "live retention-gap telemetry time-series preserves chart data and source evidence in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "retention-gap-telemetry-time-series-viewport",
        display_name: "Retention Gap Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Retention Gap Series")

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               51,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               53,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Retention Gap Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-gap-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Retention Gap Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "retention-gap-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-retention-gap-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"retentionGapTelemetryTimeSeries\""
  end

  test "live empty telemetry time-series preserves no-data source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_fresh_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "empty-telemetry-time-series-viewport",
        display_name: "Empty Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Empty Series")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Empty Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-empty-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Empty Voltage Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-empty-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"emptyTelemetryTimeSeries\""
  end

  test "live empty telemetry value tile preserves no-data source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "empty-telemetry-value-tile-viewport",
        display_name: "Empty Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Empty Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Empty Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-empty-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Empty Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-empty-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  test "live retention-gap telemetry value tile preserves blocking source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "retention-gap-telemetry-value-tile-viewport",
        display_name: "Retention Gap Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Retention Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Retention Gap Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-gap-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Retention Gap Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-retention-gap-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-widget-lifecycle-state",
                 "retention_gap",
                 "--expected-widget-lifecycle-severity",
                 "error",
                 "--expected-widget-warning-code",
                 "retention_gap",
                 "--expected-widget-source-state",
                 "retention_gap",
                 "--expected-widget-source-severity",
                 "error",
                 "--expected-widget-source-warning-code",
                 "retention_gap",
                 "--expected-widget-source-empty-reason",
                 "scope_no_data",
                 "--expected-widget-notice",
                 "This widget cannot load because the selected time range is outside available source retention.",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  test "live source-unavailable telemetry value tile preserves blocking source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [latest_fun: &browser_source_unavailable_latest/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-unavailable-telemetry-value-tile-viewport",
        display_name: "Source Unavailable Telemetry Value Tile Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_managed_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Unavailable Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-source-unavailable-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-widget-lifecycle-state",
                 "error",
                 "--expected-widget-lifecycle-severity",
                 "error",
                 "--expected-widget-warning-code",
                 "source_unavailable",
                 "--expected-widget-source-state",
                 "unavailable",
                 "--expected-widget-source-severity",
                 "error",
                 "--expected-widget-source-warning-code",
                 "source_unavailable",
                 "--expected-widget-source-empty-reason",
                 "",
                 "--expected-widget-notice",
                 "This widget cannot load because its source failed.",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  test "live stale telemetry value tile preserves sampled actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-telemetry-value-tile-viewport",
        display_name: "Stale Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Stale Tile")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Stale Counter Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-stale-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-id",
                 counter_sample.sample_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"staleTelemetryValueTile\""
  end

  test "live watermarked telemetry value tile renders fresh source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "fresh-telemetry-value-tile-viewport",
        display_name: "Fresh Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Fresh Tile")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    source_watermark_config =
      Application.get_env(:cadence, :dashboard_source_watermark_events, [])

    Application.put_env(
      :cadence,
      :dashboard_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_watermark_events, source_watermark_config)
    end)

    assert {:ok, _watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 complete_through: sample_time,
                 latest_receipt_time: sample_time,
                 retention_starts_at: sample_time,
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: DateTime.add(sample_time, 1, :second),
                 payload: %{write_id: "browser-fresh-value-tile-watermark"}
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Fresh Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-fresh-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Fresh Counter Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "fresh-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-fresh-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-id",
                 counter_sample.sample_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"freshTelemetryValueTile\""
  end

  test "live partial telemetry data table preserves returned row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-data-table-viewport",
        display_name: "Partial Telemetry Data Table Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Table")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-data-table",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              widget_type_version: 1,
              title: "Partial Counter Table",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-data-table",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-id",
                 counter_sample.sample_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"partialTelemetryDataTable\""
  end

  test "live partial telemetry status matrix preserves returned row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-status-matrix-viewport",
        display_name: "Partial Telemetry Status Matrix Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Matrix")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Status Matrix Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-status-matrix",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.status_matrix",
              widget_type_version: 1,
              title: "Partial Counter Matrix",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-status-matrix",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-id",
                 counter_sample.sample_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"partialTelemetryStatusMatrix\""
  end

  test "live source-unavailable telemetry row widgets preserve blocking source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [latest_fun: &browser_source_unavailable_latest/4]
      })
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-unavailable-telemetry-row-widgets-viewport",
        display_name: "Source Unavailable Telemetry Row Widgets Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Rows")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_managed_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Unavailable Telemetry Row Widgets Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-data-table",
            layout: %{x: 0, y: 0, w: 6, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Table",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          },
          %Placement{
            placement_id: "placement-source-unavailable-status-matrix",
            layout: %{x: 6, y: 0, w: 6, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.status_matrix",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Matrix",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-unavailable-telemetry-row-widgets",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-data-table-placement-id",
                 "placement-source-unavailable-data-table",
                 "--expected-status-matrix-placement-id",
                 "placement-source-unavailable-status-matrix",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"sourceUnavailableTelemetryRowWidgets\""
  end

  test "live operational command queue depth evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "command-queue-depth-viewport",
        display_name: "Command Queue Depth Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-pending-1",
      "browser-command-endpoint-alpha"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-pending-2",
      "browser-command-endpoint-beta"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-released",
      "browser-command-endpoint-alpha",
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-depth",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint scoped operational command queue depth passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-command-queue-depth-viewport",
        display_name: "Source Endpoint Command Queue Depth Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-depth",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-spacecraft operational command queue depth passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-spacecraft-command-queue-depth-viewport",
        display_name: "Multi Spacecraft Command Queue Depth Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-command-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Command Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-command-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Command Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, beta_spacecraft)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-alpha",
      "browser-spacecraft-command-endpoint-alpha",
      :pending,
      spacecraft_id: alpha_spacecraft.spacecraft_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-beta",
      "browser-spacecraft-command-endpoint-beta",
      :pending,
      spacecraft_id: beta_spacecraft.spacecraft_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-gamma",
      "browser-spacecraft-command-endpoint-gamma",
      :pending,
      spacecraft_id: "browser-command-spacecraft-gamma"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-released-alpha",
      "browser-spacecraft-command-endpoint-alpha",
      :released,
      spacecraft_id: alpha_spacecraft.spacecraft_id
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Spacecraft Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{alpha_spacecraft.spacecraft_id},#{beta_spacecraft.spacecraft_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-depth",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-command-queue-depth",
                 "2",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint scoped operational command queue value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-command-queue-value-tile-viewport",
        display_name: "Source Endpoint Command Queue Value Tile Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-value-tile-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Value Tile Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-value-tile-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Value Tile Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Command Queue Depth",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-value-tile",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational data table command queue evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "data-table-command-queue-viewport",
        display_name: "Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-pending-1",
      "browser-data-table-command-endpoint-alpha"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-pending-2",
      "browser-data-table-command-endpoint-beta"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-released",
      "browser-data-table-command-endpoint-alpha",
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint scoped operational data table command queue passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-data-table-command-queue-viewport",
        display_name: "Source Endpoint Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-data-table-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Data Table Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-data-table-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Data Table Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live mixed operational data table flattens multiple product rows in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mixed-operational-data-table-viewport",
        display_name: "Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-mixed-operational-table-spacecraft-alpha",
        receipt_time: ~U[2026-07-01 12:00:00Z],
        packet_value: 51,
        sequence_count: 51
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 52,
        sequence_count: 52
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Mixed Operational Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Mixed Operational Rows",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth", "ingress.processing_latency_ms"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live stale mixed operational data table preserves row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-mixed-operational-data-table-viewport",
        display_name: "Stale Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-stale-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-stale-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    stale_receipt_time =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-mixed-operational-table-spacecraft-alpha",
        receipt_time: stale_receipt_time,
        packet_value: 61,
        sequence_count: 61
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 62,
        sequence_count: 62
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Mixed Operational Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-mixed-operational-data-table",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              title: "Stale Mixed Operational Rows",
              binding: %{
                source: :operational_observables,
                observables: ["commanding.queue_depth", "ingress.processing_latency_ms"],
                scope_mode: :context,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{
                health: %{
                  freshness_policy: %{stale_after_ms: 1000}
                }
              }
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--expected-widget-lifecycle-state",
                 "stale",
                 "--expected-widget-warning-code",
                 "stale_data",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live degraded mixed operational data table preserves source-health handoffs in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    reset_runtime_health!()

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous_source_execution
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)

      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "degraded-mixed-operational-data-table-viewport",
        display_name: "Degraded Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-degraded-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Degraded Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-degraded-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-degraded-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Degraded Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-degraded-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-degraded-mixed-operational-table-spacecraft-alpha",
        receipt_time: ~U[2026-07-01 12:00:00Z],
        packet_value: 71,
        sequence_count: 71
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-degraded-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 72,
        sequence_count: 72
      )

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 realm: :flight,
                 dataset: "operational_observables",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "adapter",
                   probe_message: "Operational observables schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Operational observables adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Degraded Mixed Operational Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Degraded Mixed Operational Rows",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth", "ingress.processing_latency_ms"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--expected-widget-source-state",
                 "degraded",
                 "--expected-widget-source-warning-code",
                 "source_degraded",
                 "--expected-row-data-management-badge",
                 "degraded",
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--expected-command-supported-capability",
                 "operational_latest",
                 "--expected-ingress-supported-capability",
                 "operational_latest",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint scoped empty operational data table command queue passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-empty-data-table-command-queue-viewport",
        display_name: "Source Endpoint Empty Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-empty-data-table-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Data Table Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-empty-data-table-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Data Table Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-empty-data-table-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-empty-data-table-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Empty Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "0",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational ingress latency evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ingress-latency-viewport",
        display_name: "Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Alpha",
        metadata: %{"ground_station_id" => "dss-ingress-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Beta",
        metadata: %{"ground_station_id" => "dss-ingress-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:00Z],
        packet_value: 31,
        sequence_count: 1
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:00:01Z],
        packet_value: 32,
        sequence_count: 2
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live contact-scoped operational ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-ingress-latency-viewport",
        display_name: "Contact Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_contact_id = "browser-ingress-contact-alpha"
    beta_contact_id = "browser-ingress-contact-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-contact-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Contact Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-contact-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Contact Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint.source_endpoint_id],
        paths: contact_paths(alpha_endpoint.source_endpoint_id),
        starts_at: ~U[2026-06-30 12:00:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :scheduled
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint.source_endpoint_id],
        paths: contact_paths(beta_endpoint.source_endpoint_id),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:09:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        contact_id: alpha_contact_id,
        spacecraft_id: "browser-ingress-contact-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:03:00Z],
        packet_value: 51,
        sequence_count: 1
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        contact_id: beta_contact_id,
        spacecraft_id: "browser-ingress-contact-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:03:01Z],
        packet_value: 52,
        sequence_count: 2
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Contact Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: alpha_contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-contact",
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-spacecraft operational ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-spacecraft-ingress-latency-viewport",
        display_name: "Multi Spacecraft Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-ingress-scope-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-ingress-scope-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, beta_spacecraft)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Beta"
      })

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Gamma"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, gamma_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    _alpha_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: alpha_spacecraft.spacecraft_id,
        receipt_time: ~U[2026-06-30 12:02:00Z],
        packet_value: 41,
        sequence_count: 1
      )

    _beta_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: beta_spacecraft.spacecraft_id,
        receipt_time: ~U[2026-06-30 12:02:01Z],
        packet_value: 42,
        sequence_count: 2
      )

    _gamma_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        gamma_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-scope-spacecraft-gamma",
        receipt_time: ~U[2026-06-30 12:02:02Z],
        packet_value: 43,
        sequence_count: 3
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Spacecraft Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{alpha_spacecraft.spacecraft_id},#{beta_spacecraft.spacecraft_id}"

    source_endpoint_ids =
      "#{alpha_endpoint.source_endpoint_id},#{beta_endpoint.source_endpoint_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-multi-spacecraft",
                 "--expected-source-endpoint-ids",
                 source_endpoint_ids,
                 "--excluded-source-endpoint-id",
                 gamma_endpoint.source_endpoint_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational ingress latency time-series passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ingress-latency-timeseries-viewport",
        display_name: "Ingress Latency Time-Series Viewport"
      )

    from_time = ~U[2026-06-30 12:00:00Z]
    to_time = ~U[2026-06-30 12:01:00Z]

    flight_operational_source = %DataSource{
      DataSources.default_operational_observables_data_source()
      | data_source_id: "managed_operational_observables_ingress_time_series",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        metadata: %{bootstrap_default?: false}
    }

    flight_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "flight_operational_observables_ingress_time_series",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        data_source_id: flight_operational_source.data_source_id,
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, _source} = DataSources.persist_data_source(flight_operational_source)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(flight_operational_binding,
               occurred_at: from_time
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Alpha",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Beta",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-beta"}
      })

    empty_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-empty",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Empty",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-empty"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, empty_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    _alpha_first_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:05Z],
        packet_value: 51,
        sequence_count: 51
      )

    _alpha_second_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:25Z],
        packet_value: 52,
        sequence_count: 52
      )

    _beta_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:00:30Z],
        packet_value: 53,
        sequence_count: 53
      )

    ingress_evidence_binding_set =
      persist_application_binding_set!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        suffix: "ingress-timeseries-evidence"
      )

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               ingress_evidence_binding_set.binding_set_id,
               ingress_evidence_binding_set.version,
               activated_at: from_time
             )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ingress Latency Time-Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-ingress-latency-history",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            data_override: %{
              "realm" => "flight",
              "source_mode" => "specific",
              "source_contexts" => %{
                "operational_observables" => %{
                  "data_source_id" => flight_operational_source.data_source_id,
                  "source_binding_id" => flight_operational_binding.binding_id
                }
              }
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Ingress Latency History",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"],
                scope_mode: :context,
                sampling: :raw_series,
                overlays: []
              },
              options: %{legend: true}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: Enum.join([alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id], ","), time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-source-endpoint-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    partial_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: Enum.join([alpha_endpoint.source_endpoint_id, empty_endpoint.source_endpoint_id], ","), time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {partial_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-source-endpoint-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, empty_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-returned-source-endpoint-ids",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-missing-source-endpoint-ids",
                 empty_endpoint.source_endpoint_id,
                 "--expected-chart-target-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, alpha_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-widget-lifecycle-state",
                 "partial",
                 "--expected-widget-source-state",
                 "partial",
                 "--expected-widget-source-data-state",
                 "ready",
                 "--expected-widget-warning-code",
                 "partial_data",
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
                 "--url",
                 partial_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert partial_output =~ "dashboard_viewport_smoke passed"
  end

  test "live stale operational data table ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-data-table-ingress-latency-viewport",
        display_name: "Stale Data Table Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-ingress-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Ingress Alpha",
        metadata: %{"ground_station_id" => "dss-stale-ingress-alpha"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    stale_receipt_time =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        source_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-ingress-spacecraft-alpha",
        receipt_time: stale_receipt_time,
        packet_value: 41,
        sequence_count: 41
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Ingress Latency Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-data-table-ingress-latency",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              title: "Stale Ingress Latency",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"],
                scope_mode: :context,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{
                health: %{
                  freshness_policy: %{stale_after_ms: 1000}
                }
              }
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: source_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-operational-data-table-ingress-latency",
                 "--expected-source-endpoint-id",
                 source_endpoint.source_endpoint_id,
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 latency_sample.source_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-operational-resource-viewport",
        display_name: "Source Endpoint Operational Resource Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{"ground_station_id" => "dss-63"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "source-endpoint-transport-connected",
      "comms.transport.connection_state",
      "link-alpha",
      :connected,
      ~U[2026-06-17 12:00:30Z],
      resource_id: alpha_transport.transport_id,
      scope_kind: :transport,
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-endpoint-operational-resource",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-operational-event-id",
                 "operational_event:connection_state_snapshot:source-endpoint-transport-connected",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live ground-station operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ground-station-operational-resource-viewport",
        display_name: "Ground Station Operational Resource Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{"ground_station_id" => dss_14.ground_station_id}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{"ground_station_id" => dss_63.ground_station_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ground Station Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Connection State",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "ground-station-operational-resource",
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live link operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-operational-resource-viewport",
        display_name: "Link Operational Resource Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => "dss-14",
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14",
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-transport-connected",
      "comms.transport.connection_state",
      "link-alpha",
      :connected,
      ~U[2026-06-17 12:00:25Z],
      resource_id: alpha_transport.transport_id,
      scope_kind: :transport,
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-rf-lock-locked",
      "link.rf_lock_state",
      "link-alpha",
      :locked,
      ~U[2026-06-17 12:00:30Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-beta-rf-lock-unlocked",
      "link.rf_lock_state",
      "link-beta",
      :unlocked,
      ~U[2026-06-17 12:00:32Z],
      transport_id: beta_transport.transport_id,
      source_endpoint_id: beta_endpoint.source_endpoint_id,
      ground_station_id: "dss-63"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-frame-sync-synchronized",
      "link.frame_sync_state",
      "link-alpha",
      :synchronized,
      ~U[2026-06-17 12:00:35Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Link Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "RF State",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          },
          %{
            type: :data_table,
            title: "Operational State Rows",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "link.rf_lock_state",
                "link.frame_sync_state"
              ]
            },
            layout: %{x: 0, y: 3, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "link-alpha,link-beta"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "link-operational-resource",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 "dss-14",
                 "--expected-connection-operational-event-id",
                 "operational_event:connection_state_snapshot:link-transport-connected",
                 "--expected-operational-event-id",
                 "operational_event:link_rf_lock_state_snapshot:link-rf-lock-locked",
                 "--expected-frame-sync-operational-event-id",
                 "operational_event:link_frame_sync_state_snapshot:link-frame-sync-synchronized",
                 "--expected-beta-link-id",
                 "link-beta",
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:link_rf_lock_state_snapshot:link-beta-rf-lock-unlocked",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational RF state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_rf_state_timeline_source_execution_opts()
    )

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-rf-state-timeline-viewport",
        display_name: "Operational RF State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational RF State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "RF State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-rf-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational connection state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-connection-state-timeline-viewport",
        display_name: "Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"transport-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"ground-disconnected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z], [transport_id: nil]},
          {"ground-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:45Z], [transport_id: nil]},
          {"transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"ground-beta-connected", "ground.station.connection_state", dss_63.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live antenna pointing state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "antenna-pointing-state-timeline-viewport",
        display_name: "Antenna Pointing State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    for {snapshot_id, ground_station_id, source_endpoint_id, link_id, state, observed_at} <- [
          {"antenna-pointing-slewing", dss_14.ground_station_id,
           alpha_endpoint.source_endpoint_id, "link-alpha", :slewing, ~U[2026-06-17 12:00:30Z]},
          {"antenna-pointing-tracking", dss_14.ground_station_id,
           alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:01:30Z]},
          {"antenna-pointing-beta-tracking", dss_63.ground_station_id,
           beta_endpoint.source_endpoint_id, "link-beta", :tracking, ~U[2026-06-17 12:01:00Z]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        "ground.station.antenna_pointing_state",
        link_id,
        state,
        observed_at,
        resource_id: ground_station_id,
        scope_kind: :ground_station,
        transport_id: nil,
        source_endpoint_id: source_endpoint_id,
        ground_station_id: ground_station_id
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Antenna Pointing State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Antenna Pointing State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-antenna-pointing-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:antenna-pointing-tracking",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay antenna pointing state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-antenna-pointing-state-timeline-viewport",
        display_name: "Replay Antenna Pointing State Timeline Viewport"
      )

    replay_run_id = "browser-antenna-pointing-replay-run"
    other_replay_run_id = "browser-antenna-pointing-other-replay-run"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    _replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    for {snapshot_id, ground_station_id, source_endpoint_id, link_id, state, observed_at, opts} <-
          [
            {"antenna-pointing-live-tracking", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:00:10Z],
             []},
            {"antenna-pointing-replay-slewing", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :slewing, ~U[2026-06-17 12:00:30Z],
             [replay_run_id: replay_run_id]},
            {"antenna-pointing-beta-replay-tracking", dss_63.ground_station_id,
             beta_endpoint.source_endpoint_id, "link-beta", :tracking, ~U[2026-06-17 12:01:00Z],
             [replay_run_id: replay_run_id]},
            {"antenna-pointing-other-replay-stowed", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :stowed, ~U[2026-06-17 12:01:15Z],
             [replay_run_id: other_replay_run_id]},
            {"antenna-pointing-replay-tracking", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:01:30Z],
             [replay_run_id: replay_run_id]}
          ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        "ground.station.antenna_pointing_state",
        link_id,
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: ground_station_id,
            scope_kind: :ground_station,
            transport_id: nil,
            source_endpoint_id: source_endpoint_id,
            ground_station_id: ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Antenna Pointing State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Antenna Pointing State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-antenna-pointing-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:#{replay_run_id}:antenna-pointing-replay-tracking",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live transport scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "transport-operational-connection-state-timeline-viewport",
        display_name: "Transport Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"transport-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"transport-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           []},
          {"transport-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z], []},
          {"transport-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"transport-scope-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Transport Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "transport",
                 "--expected-scope-id",
                 alpha_transport.transport_id,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live source-endpoint scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-operational-connection-state-timeline-viewport",
        display_name: "Source Endpoint Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"source-endpoint-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"source-endpoint-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"source-endpoint-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"source-endpoint-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"source-endpoint-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"source-endpoint-scope-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "source_endpoint",
                 "--expected-scope-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-source-endpoint operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-source-endpoint-operational-connection-state-timeline-viewport",
        display_name: "Multi Source Endpoint Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    dss_43 =
      GroundStation.new(%{
        ground_station_id: "dss-43",
        mission_id: mission.mission_id,
        display_name: "Canberra DSS-43",
        provider: "DSN",
        region: "Canberra",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-gamma",
          "transport_id" => "browser-transport-gamma",
          "link_assignment_id" => "link-gamma"
        }
      })

    for station <- [dss_14, dss_63, dss_43] do
      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, station)
    end

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for endpoint <- [alpha_endpoint, beta_endpoint, gamma_endpoint] do
      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_transport =
      Transport.new(%{
        transport_id: "browser-transport-gamma",
        mission_id: mission.mission_id,
        display_name: "Gamma TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "gamma.ground.example",
          "port" => "5002",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for transport <- [alpha_transport, beta_transport, gamma_transport] do
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)
    end

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"multi-source-endpoint-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"multi-source-endpoint-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"multi-source-endpoint-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"multi-source-endpoint-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"multi-source-endpoint-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-source-endpoint-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-source-endpoint-gamma-connected", "comms.transport.connection_state",
           gamma_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:02:00Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]},
          {"multi-source-endpoint-ground-gamma-connected", "ground.station.connection_state",
           dss_43.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:02:15Z],
           [
             link_id: "link-gamma",
             transport_id: nil,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Source Endpoint Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{alpha_endpoint.source_endpoint_id},#{beta_endpoint.source_endpoint_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: scope_ids, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "source_endpoint",
                 "--expected-scope-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 gamma_transport.transport_id,
                 "--excluded-ground-station-id",
                 dss_43.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live link scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-operational-connection-state-timeline-viewport",
        display_name: "Link Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"link-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"link-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"link-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"link-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"link-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"link-scope-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Link Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live multi-transport operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-transport-operational-connection-state-timeline-viewport",
        display_name: "Multi Transport Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    dss_43 =
      GroundStation.new(%{
        ground_station_id: "dss-43",
        mission_id: mission.mission_id,
        display_name: "Canberra DSS-43",
        provider: "DSN",
        region: "Canberra",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-gamma",
          "transport_id" => "browser-transport-gamma",
          "link_assignment_id" => "link-gamma"
        }
      })

    for station <- [dss_14, dss_63, dss_43] do
      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, station)
    end

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for endpoint <- [alpha_endpoint, beta_endpoint, gamma_endpoint] do
      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_transport =
      Transport.new(%{
        transport_id: "browser-transport-gamma",
        mission_id: mission.mission_id,
        display_name: "Gamma TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "gamma.ground.example",
          "port" => "5002",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for transport <- [alpha_transport, beta_transport, gamma_transport] do
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)
    end

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"multi-transport-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"multi-transport-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"multi-transport-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           []},
          {"multi-transport-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z], []},
          {"multi-transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-transport-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-transport-gamma-connected", "comms.transport.connection_state",
           gamma_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:02:00Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]},
          {"multi-transport-ground-gamma-connected", "ground.station.connection_state",
           dss_43.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:02:15Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Transport Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          },
          %{
            type: :data_table,
            title: "Connection State Rows",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 4, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{alpha_transport.transport_id},#{beta_transport.transport_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_ids: scope_ids, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "transport",
                 "--expected-scope-id",
                 alpha_transport.transport_id,
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:connection_state_snapshot:multi-transport-beta-connected",
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 gamma_transport.transport_id,
                 "--excluded-ground-station-id",
                 dss_43.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live mission aggregate operational connection state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mission-operational-connection-state-timeline-viewport",
        display_name: "Mission Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"mission-transport-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"mission-transport-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"mission-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"mission-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"mission-transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"mission-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Mission Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mission-operational-connection-state-timeline",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-connection-state-timeline-viewport",
        display_name: "Replay Operational Connection State Timeline Viewport"
      )

    replay_run_id = "browser-connection-state-replay-run"
    other_replay_run_id = "browser-connection-state-other-replay-run"

    transport_connection_source_event_id =
      "operational_event:connection_state_snapshot:#{replay_run_id}:transport-replay-connected"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    _replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-live-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:00:10Z], []},
          {"transport-replay-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: replay_run_id]},
          {"transport-beta-replay-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:00:45Z],
           [
             link_id: "link-beta",
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"transport-other-replay-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [replay_run_id: other_replay_run_id]},
          {"transport-replay-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: replay_run_id]},
          {"ground-live-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:00:15Z], [transport_id: nil]},
          {"ground-replay-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"ground-beta-replay-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             replay_run_id: replay_run_id,
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"ground-other-replay-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [replay_run_id: other_replay_run_id, transport_id: nil]},
          {"ground-replay-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          },
          %{
            type: :data_table,
            title: "Replay Connection State Rows",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 4, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{dss_14.ground_station_id},#{dss_63.ground_station_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_ids: scope_ids, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "ground_station",
                 "--expected-scope-id",
                 dss_14.ground_station_id,
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_connection_source_event_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:connection_state_snapshot:#{replay_run_id}:transport-beta-replay-connected",
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 "browser-transport-excluded",
                 "--excluded-ground-station-id",
                 "dss-excluded",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay operational RF state timeline uses default event-backed reader in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-rf-state-timeline-viewport",
        display_name: "Replay Operational RF State Timeline Viewport"
      )

    replay_run_id = "browser-rf-state-replay-run"
    other_replay_run_id = "browser-rf-state-other-replay-run"

    rf_lock_source_event_id =
      "operational_event:link_rf_lock_state_snapshot:#{replay_run_id}:rf-lock-replay-acquiring"

    rf_lock_table_source_event_id =
      "operational_event:link_rf_lock_state_snapshot:#{replay_run_id}:rf-lock-replay-acquiring"

    frame_sync_table_source_event_id =
      "operational_event:link_frame_sync_state_snapshot:#{replay_run_id}:frame-sync-replay-acquiring"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    _replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, link_id, state, observed_at, opts} <- [
          {"rf-lock-live", "link.rf_lock_state", "link-alpha", :locked, ~U[2026-06-17 12:00:10Z],
           []},
          {"rf-lock-replay-acquiring", "link.rf_lock_state", "link-alpha", :acquiring,
           ~U[2026-06-17 12:00:30Z], [replay_run_id: replay_run_id]},
          {"rf-lock-beta-replay", "link.rf_lock_state", "link-beta", :unlocked,
           ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63"
           ]},
          {"rf-lock-other-replay", "link.rf_lock_state", "link-alpha", :degraded,
           ~U[2026-06-17 12:01:00Z], [replay_run_id: other_replay_run_id]},
          {"rf-lock-replay-locked", "link.rf_lock_state", "link-alpha", :locked,
           ~U[2026-06-17 12:01:30Z], [replay_run_id: replay_run_id]},
          {"frame-sync-live", "link.frame_sync_state", "link-alpha", :synchronized,
           ~U[2026-06-17 12:00:15Z], []},
          {"frame-sync-replay-acquiring", "link.frame_sync_state", "link-alpha", :acquiring,
           ~U[2026-06-17 12:00:45Z], [replay_run_id: replay_run_id]},
          {"frame-sync-beta-replay", "link.frame_sync_state", "link-beta", :lost,
           ~U[2026-06-17 12:01:00Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63"
           ]},
          {"frame-sync-other-replay", "link.frame_sync_state", "link-alpha", :lost,
           ~U[2026-06-17 12:01:15Z], [replay_run_id: other_replay_run_id]},
          {"frame-sync-replay-synchronized", "link.frame_sync_state", "link-alpha", :synchronized,
           ~U[2026-06-17 12:01:45Z], [replay_run_id: replay_run_id]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        link_id,
        state,
        observed_at,
        opts
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational RF State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "RF State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          },
          %{
            type: :data_table,
            title: "Replay RF State Rows",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 4, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-rf-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 rf_lock_source_event_id,
                 "--expected-rf-lock-table-operational-event-id",
                 rf_lock_table_source_event_id,
                 "--expected-rf-lock-table-state",
                 "Acquiring",
                 "--expected-frame-sync-table-operational-event-id",
                 frame_sync_table_source_event_id,
                 "--expected-frame-sync-table-state",
                 "Acquiring",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay operational metric time-series charts use default event-backed readers in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-metric-time-series-viewport",
        display_name: "Replay Operational Metric Time Series Viewport"
      )

    replay_run_id = "browser-operational-metric-replay-run"
    other_replay_run_id = "browser-operational-metric-other-replay-run"
    empty_replay_run_id = "browser-operational-metric-empty-replay-run"
    partial_replay_run_id = "browser-operational-metric-partial-replay-run"
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]
    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    source_watermark_config =
      Application.get_env(:cadence, :dashboard_source_watermark_events, [])

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    Application.put_env(
      :cadence,
      :dashboard_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
      Application.put_env(:cadence, :dashboard_source_watermark_events, source_watermark_config)
    end)

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)
    persist_replay_run!(mission, empty_replay_run_id, from_time)
    persist_replay_run!(mission, partial_replay_run_id, from_time)

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: ~U[2026-06-17 12:00:50Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Replay operational observable schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Replay operational observable adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, _watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 complete_through: ~U[2026-06-17 12:01:45Z],
                 latest_receipt_time: ~U[2026-06-17 12:01:45Z],
                 retention_starts_at: ~U[2026-06-17 11:00:00Z],
                 sample_count: 6,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-17 12:01:50Z],
                 payload: %{write_id: "browser-replay-operational-metric-watermark"}
               },
               invalidate_runtime_cache?: false
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    replay_metric_binding_set =
      persist_application_binding_set!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        suffix: "replay-operational-metric"
      )

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               replay_metric_binding_set.binding_set_id,
               replay_metric_binding_set.version,
               activated_at: from_time
             )

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {sample_id, observable_id, resource_id, value, observed_at, opts} <- [
          {"rf-live", "link.snr_db", "link-alpha", 9.0, ~U[2026-06-17 12:00:10Z], []},
          {"rf-replay-acquired", "link.snr_db", "link-alpha", 12.25, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: replay_run_id]},
          {"rf-beta-replay", "link.snr_db", "link-beta", 6.5, ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-other-replay", "link.snr_db", "link-alpha", 4.5, ~U[2026-06-17 12:01:00Z],
           [replay_run_id: other_replay_run_id]},
          {"rf-replay-locked", "link.snr_db", "link-alpha", 14.0, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: replay_run_id]},
          {"rf-partial-acquired", "link.snr_db", "link-alpha", 10.5, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: partial_replay_run_id]},
          {"rf-partial-locked", "link.snr_db", "link-alpha", 11.25, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: partial_replay_run_id]},
          {"rf-symbol-rate-live", "link.symbol_rate_sps", "link-alpha", 800_000.0,
           ~U[2026-06-17 12:00:14Z], []},
          {"rf-symbol-rate-replay-acquired", "link.symbol_rate_sps", "link-alpha", 1_024_000.0,
           ~U[2026-06-17 12:00:34Z], [replay_run_id: replay_run_id]},
          {"rf-symbol-rate-beta-replay", "link.symbol_rate_sps", "link-beta", 512_000.0,
           ~U[2026-06-17 12:00:49Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-symbol-rate-other-replay", "link.symbol_rate_sps", "link-alpha", 640_000.0,
           ~U[2026-06-17 12:01:04Z], [replay_run_id: other_replay_run_id]},
          {"rf-symbol-rate-replay-locked", "link.symbol_rate_sps", "link-alpha", 2_048_000.0,
           ~U[2026-06-17 12:01:34Z], [replay_run_id: replay_run_id]},
          {"rf-ebn0-live", "link.eb_n0_db", "link-alpha", 7.0, ~U[2026-06-17 12:00:12Z], []},
          {"rf-ebn0-replay-acquired", "link.eb_n0_db", "link-alpha", 8.25,
           ~U[2026-06-17 12:00:32Z], [replay_run_id: replay_run_id]},
          {"rf-ebn0-beta-replay", "link.eb_n0_db", "link-beta", 5.5, ~U[2026-06-17 12:00:47Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-ebn0-other-replay", "link.eb_n0_db", "link-alpha", 4.0, ~U[2026-06-17 12:01:02Z],
           [replay_run_id: other_replay_run_id]},
          {"rf-ebn0-replay-locked", "link.eb_n0_db", "link-alpha", 9.75, ~U[2026-06-17 12:01:32Z],
           [replay_run_id: replay_run_id]},
          {"bitrate-live", "comms.transport.downlink_bitrate", alpha_transport.transport_id,
           64_000.0, ~U[2026-06-17 12:00:15Z], []},
          {"uplink-bitrate-live", "comms.transport.uplink_bitrate", alpha_transport.transport_id,
           4_800.0, ~U[2026-06-17 12:00:20Z], []},
          {"bitrate-replay-acquired", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 72_000.0, ~U[2026-06-17 12:00:35Z],
           [replay_run_id: replay_run_id]},
          {"uplink-bitrate-replay-acquired", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 5_600.0, ~U[2026-06-17 12:00:40Z],
           [replay_run_id: replay_run_id]},
          {"bitrate-beta-replay", "comms.transport.downlink_bitrate", beta_transport.transport_id,
           48_000.0, ~U[2026-06-17 12:00:55Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id,
             link_id: "link-beta"
           ]},
          {"uplink-bitrate-beta-replay", "comms.transport.uplink_bitrate",
           beta_transport.transport_id, 3_200.0, ~U[2026-06-17 12:00:58Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id,
             link_id: "link-beta"
           ]},
          {"bitrate-other-replay", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 32_000.0, ~U[2026-06-17 12:01:05Z],
           [replay_run_id: other_replay_run_id]},
          {"uplink-bitrate-other-replay", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 2_400.0, ~U[2026-06-17 12:01:10Z],
           [replay_run_id: other_replay_run_id]},
          {"ingress-latency-replay-acquired", "ingress.processing_latency_ms",
           alpha_endpoint.source_endpoint_id, 18.5, ~U[2026-06-17 12:00:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"ingress-latency-replay-locked", "ingress.processing_latency_ms",
           alpha_endpoint.source_endpoint_id, 21.0, ~U[2026-06-17 12:01:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"bitrate-partial-acquired", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 88_000.0, ~U[2026-06-17 12:00:35Z],
           [replay_run_id: partial_replay_run_id]},
          {"bitrate-partial-locked", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 104_000.0, ~U[2026-06-17 12:01:35Z],
           [replay_run_id: partial_replay_run_id]},
          {"bitrate-replay-locked", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 96_000.0, ~U[2026-06-17 12:01:35Z],
           [replay_run_id: replay_run_id]},
          {"uplink-bitrate-replay-locked", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 8_400.0, ~U[2026-06-17 12:01:40Z],
           [replay_run_id: replay_run_id]}
        ] do
      persist_operational_observable_metric_event!(
        org.organization_id,
        mission.mission_id,
        sample_id,
        observable_id,
        resource_id,
        value,
        observed_at,
        opts
      )
    end

    dashboard =
      persist_replay_operational_metric_time_series_dashboard!(
        org,
        mission,
        alpha_transport.transport_id,
        source_endpoint_id: alpha_endpoint.source_endpoint_id,
        overlays: [:events]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-rf-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:rf-replay-acquired",
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:rf-replay-locked"
                 ]
                 |> Enum.join(","),
                 "--expected-bitrate-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:bitrate-replay-acquired",
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:bitrate-replay-locked"
                 ]
                 |> Enum.join(","),
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    partial_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: partial_replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {partial_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-partial",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 partial_replay_run_id,
                 "--expected-rf-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:rf-partial-acquired",
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:rf-partial-locked"
                 ]
                 |> Enum.join(","),
                 "--url",
                 partial_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert partial_output =~ "dashboard_viewport_smoke passed"

    assert {partial_bitrate_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-partial",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 partial_replay_run_id,
                 "--expected-placement-id",
                 "placement-transport-bitrate-history",
                 "--expected-returned-observable",
                 "comms.transport.downlink_bitrate",
                 "--expected-missing-observable",
                 "comms.transport.uplink_bitrate",
                 "--expected-returned-values",
                 "88000,104000",
                 "--expected-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:bitrate-partial-acquired",
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:bitrate-partial-locked"
                 ]
                 |> Enum.join(","),
                 "--url",
                 partial_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert partial_bitrate_output =~ "dashboard_viewport_smoke passed"

    empty_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: empty_replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {no_data_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-no-data",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 empty_replay_run_id,
                 "--url",
                 empty_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert no_data_output =~ "dashboard_viewport_smoke passed"
  end

  test "live archive operational metric time-series no-data widgets preserve source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "archive-operational-metric-no-data-viewport",
        display_name: "Archive Operational Metric No Data Viewport"
      )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    flight_operational_source = %DataSource{
      DataSources.default_operational_observables_data_source()
      | data_source_id: "managed_operational_observables_archive_no_data",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        metadata: %{bootstrap_default?: false}
    }

    flight_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "archive_operational_observables_no_data",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: flight_operational_source.data_source_id,
        dataset: "operational_observables",
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, _source} = DataSources.persist_data_source(flight_operational_source)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(flight_operational_binding,
               occurred_at: from_time
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)

    dashboard =
      persist_replay_operational_metric_time_series_dashboard!(
        org,
        mission,
        alpha_transport.transport_id,
        source_endpoint_id: alpha_endpoint.source_endpoint_id,
        data_override: %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "operational_observables" => %{
              "data_source_id" => flight_operational_source.data_source_id,
              "source_binding_id" => flight_operational_binding.binding_id
            }
          }
        }
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-archive-time-series-no-data",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous_source_execution
      |> Keyword.put(:runtime_cache, false)
      |> Keyword.put(:source_result_cache?, false)
      |> Keyword.put(:frame_cache?, false)
      |> Keyword.put(:source_opts, %{
        operational_observables: [
          ingress_processing_latency_history_snapshots_fun:
            &browser_ingress_latency_history_source_unavailable/3
        ]
      })
    )

    assert {unavailable_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series-source-unavailable",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert unavailable_output =~ "dashboard_viewport_smoke passed"
    assert unavailable_output =~ "\"operationalIngressLatencyTimeSeriesSourceUnavailable\""
  end

  test "live operational transport execution state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_execution_opts()
    )

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end

      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-transport-execution-timeline-viewport",
        display_name: "Operational Transport Execution Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, gamma_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    gamma_transport =
      Transport.new(%{
        transport_id: "browser-transport-gamma",
        mission_id: mission.mission_id,
        display_name: "Gamma TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "gamma.ground.example",
          "port" => "5002",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, gamma_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Transport Execution Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Transport Execution Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-scope-ids",
                 "link-alpha,link-beta",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-beta-link-id",
                 "link-beta",
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    no_data_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-gamma"}}"

    assert {no_data_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-no-data",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-gamma",
                 "--expected-link-id",
                 "link-gamma",
                 "--expected-transport-id",
                 gamma_transport.transport_id,
                 "--url",
                 no_data_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert no_data_output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_unavailable_opts()
    )

    unavailable_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha"}}"

    assert {unavailable_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-unavailable",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--url",
                 unavailable_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert unavailable_output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_execution_opts()
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 realm: :flight,
                 dataset: "operational_observables",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: ~U[2026-06-17 12:00:45Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Transport execution state schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Transport execution state adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Cadence.reset_runtime_health()

    assert {degraded_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-degraded",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--url",
                 unavailable_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert degraded_output =~ "dashboard_viewport_smoke passed"
  end

  test "live replay operational transport execution state timeline DataLinks pass browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-transport-execution-timeline-viewport",
        display_name: "Replay Operational Transport Execution Timeline Viewport"
      )

    replay_run_id = "browser-transport-execution-replay-run"
    other_replay_run_id = "browser-transport-execution-other-replay-run"

    transport_execution_source_event_id =
      "transport-capability-record:transport-execution-replay-alpha-1:#{replay_run_id}"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end

      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
    end)

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {record_id, transport_id, event_kind, recorded_at, opts} <- [
          {"transport-execution-live-alpha", alpha_transport.transport_id, :initialized,
           ~U[2026-06-17 12:00:05Z], []},
          {"transport-execution-replay-alpha-1", alpha_transport.transport_id, :initialized,
           ~U[2026-06-17 12:00:10Z], [replay_run_id: replay_run_id]},
          {"transport-execution-replay-beta", beta_transport.transport_id, :timer_handled,
           ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63",
             link_id: "link-beta",
             contact_id: "browser-contact-beta",
             path_id: "browser-uplink-beta"
           ]},
          {"transport-execution-other-replay-alpha", alpha_transport.transport_id, :timer_handled,
           ~U[2026-06-17 12:01:00Z], [replay_run_id: other_replay_run_id]},
          {"transport-execution-replay-alpha-2", alpha_transport.transport_id,
           :transport_event_handled, ~U[2026-06-17 12:01:30Z], [replay_run_id: replay_run_id]}
        ] do
      persist_transport_capability_event!(
        org.organization_id,
        mission.mission_id,
        record_id,
        transport_id,
        event_kind,
        recorded_at,
        Keyword.merge(
          [
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id,
            link_id: "link-alpha",
            contact_id: "browser-contact-alpha",
            path_id: "browser-uplink-alpha"
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational Transport Execution Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Transport Execution Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_execution_source_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: ~U[2026-06-17 12:00:45Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Replay transport execution state schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Replay transport execution state adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      (previous_source_execution || [])
      |> Keyword.put(:runtime_cache, false)
      |> Keyword.put(:source_result_cache?, false)
      |> Keyword.put(:frame_cache?, false)
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    Cadence.reset_runtime_health()

    assert {degraded_output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-degraded",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_execution_source_event_id,
                 "--expected-data-source-id",
                 replay_sources.operational_data_source_id,
                 "--expected-source-binding-id",
                 replay_sources.operational_binding_id,
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert degraded_output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational metric value tile DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-metric-value-tile-viewport",
        display_name: "Operational Metric Value Tile Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {sample_id, observable_id, value, observed_at} <- [
          {"bitrate-live", "comms.transport.downlink_bitrate", 64_000.0,
           ~U[2026-06-17 12:00:15Z]},
          {"uplink-bitrate-live", "comms.transport.uplink_bitrate", 4_800.0,
           ~U[2026-06-17 12:00:20Z]}
        ] do
      persist_operational_observable_metric_event!(
        org.organization_id,
        mission.mission_id,
        sample_id,
        observable_id,
        alpha_transport.transport_id,
        value,
        observed_at,
        []
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Metric Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Uplink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.uplink_bitrate"]
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-value-tile",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:bitrate-live",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live unsupported operational observable scope value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-unsupported-scope-value-tile-viewport",
        display_name: "Operational Unsupported Scope Value Tile Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unsupported Operational Scope Browser",
        widgets: [
          %{
            placement_id: "placement-unsupported-bitrate",
            type: :value_tile,
            title: "Unsupported Mission Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-unsupported-scope-value-tile",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-placement-id",
                 "placement-unsupported-bitrate",
                 "--expected-observable-id",
                 "comms.transport.downlink_bitrate",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live unsupported operational observable scope time-series passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-unsupported-scope-time-series-viewport",
        display_name: "Operational Unsupported Scope Time Series Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unsupported Operational Scope Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-unsupported-bitrate-history",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Unsupported Mission Bitrate History",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.downlink_bitrate"],
                scope_mode: :context,
                sampling: :raw_series,
                overlays: []
              },
              options: %{legend: true}
            }
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-unsupported-scope-time-series",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-placement-id",
                 "placement-unsupported-bitrate-history",
                 "--expected-observable-id",
                 "comms.transport.downlink_bitrate",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational RF metric value tile DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-rf-metric-value-tile-viewport",
        display_name: "Operational RF Metric Value Tile Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-snr-value-1",
      "link.snr_db",
      "link-alpha",
      11.75,
      ~U[2026-06-17 12:00:00Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-ebn0-value-1",
      "link.eb_n0_db",
      "link-alpha",
      8.5,
      ~U[2026-06-17 12:00:15Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-symbol-rate-value-1",
      "link.symbol_rate_sps",
      "link-alpha",
      1_024_000.0,
      ~U[2026-06-17 12:00:30Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-doppler-value-1",
      "link.doppler_hz",
      "link-alpha",
      -42.5,
      ~U[2026-06-17 12:00:45Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational RF Metric Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "RF SNR",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Eb/N0",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"]
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Symbol Rate",
            binding: %{
              source: :operational_observables,
              observables: ["link.symbol_rate_sps"]
            },
            layout: %{x: 8, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Doppler",
            binding: %{
              source: :operational_observables,
              observables: ["link.doppler_hz"]
            },
            layout: %{x: 0, y: 2, w: 4, h: 2}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-rf-metric-value-tile",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live operational metric missing snapshot value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-metric-missing-snapshot-viewport",
        display_name: "Operational Metric Missing Snapshot Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Metric Missing Snapshot Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: beta_transport.transport_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-missing-snapshot-value-tile",
                 "--expected-link-id",
                 "link-beta",
                 "--expected-source-endpoint-id",
                 beta_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 beta_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_63.ground_station_id,
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  test "live authenticated dashboard route renders repeated placements through browser grid smoke",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "repeat-render-viewport",
        display_name: "Repeat Render Viewport"
      )

    spacecraft_alpha = TestFixtures.persist_spacecraft!(mission, display_name: "SC Repeat Alpha")
    spacecraft_beta = TestFixtures.persist_spacecraft!(mission, display_name: "SC Repeat Beta")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft_alpha.spacecraft_id, 31, 1_700_000_290)
    ingest!(mission, binding_set, spacecraft_beta.spacecraft_id, 41, 1_700_000_300)

    dashboard =
      persist_repeated_dashboard_document!(org, mission, [
        spacecraft_alpha.spacecraft_id,
        spacecraft_beta.spacecraft_id
      ])

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <> ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    expected_repeat_ids =
      [
        repeated_placement_id("placement-repeat", spacecraft_alpha.spacecraft_id),
        repeated_placement_id("placement-repeat", spacecraft_beta.spacecraft_id)
      ]
      |> Enum.sort()
      |> Enum.join(",")

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             System.cmd(
               "node",
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "repeat-render",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password(),
                 "--expected-repeat-ids",
                 expected_repeat_ids
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-browser-viewport-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)

    assert {:ok, _events_source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    assert {:ok, _events_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_events_binding())

    persisted
  end

  defp persist_application_binding_set!(org, mission, source_endpoint_ref, opts) do
    suffix = Keyword.get(opts, :suffix, "browser-application-binding")
    binding_set_id = "#{mission.mission_id}-#{suffix}-binding-set"

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: binding_set_id,
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "#{binding_set_id}-packet-counter",
            family_key: :packet_counter,
            target_scope: :source_endpoint,
            source_endpoint_ref: source_endpoint_ref,
            capability_config:
              CapabilityConfig.inline(%{
                "metric_name" => "browser_replay_packets",
                "flush_interval_ms" => 25
              })
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "#{binding_set_id}-packet-counter-rule",
            capability_instance_id: "#{binding_set_id}-packet-counter",
            selector: %{
              scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            priority: 10,
            fanout_mode: :multi
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)

    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    {:ok, result} =
      Cadence.process_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )

    Cadence.Persistence.persist_processing_result(result, opts)
  end

  defp browser_retention_gap_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:30:00Z],
       latest_receipt_time: ~U[2026-06-16 00:30:00Z],
       retention_starts_at: ~U[2026-06-16 00:20:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  defp browser_source_unavailable_latest(_organization_id, _mission_id, _point_id, _opts) do
    raise "browser source unavailable latest failure"
  end

  defp browser_source_unavailable_history(_organization_id, _mission_id, _point_id, _opts) do
    {:error, :browser_source_unavailable_history_failure}
  end

  defp browser_ingress_latency_history_source_unavailable(_organization_id, _mission_id, _opts) do
    raise "browser ingress latency history source unavailable"
  end

  defp browser_fresh_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:40:00Z],
       latest_receipt_time: ~U[2026-06-16 00:30:00Z],
       retention_starts_at: ~U[2026-06-16 00:00:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  defp browser_stale_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:00:01Z],
       latest_receipt_time: ~U[2026-06-16 00:00:01Z],
       retention_starts_at: ~U[2026-06-15 00:00:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  defp browser_unknown_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:error, :browser_watermark_unknown_failure}
  end

  defp contact_paths(source_endpoint_ref) do
    [
      ContactPath.new(%{
        path_id: "browser-dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      ContactPath.new(%{
        path_id: "browser-dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  defp seed_limit_definition!(mission) do
    limit_definition =
      LimitDefinition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "browser-viewport-counter-limits",
        point_id: "HK.counter",
        limit_set_name: "browser-smoke",
        thresholds: %{"yellow_high" => 20, "red_high" => 30}
      })

    assert {:ok, ^limit_definition} = Cadence.persist_limit_definition(limit_definition)
  end

  defp seed_catalog_revision_event!(org, mission, %DateTime{} = occurred_at) do
    catalog_revision_id = "browser-viewport-catalog-revision"

    revision =
      Revision.new(%{
        catalog_revision_id: catalog_revision_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        catalog_database_id: "browser-viewport-catalog",
        revision_number: 1,
        revision_label: "Browser Viewport Catalog",
        catalog_family: :telemetry,
        artifact_id: "#{catalog_revision_id}-artifact",
        import_run_id: "#{catalog_revision_id}-import-run",
        telemetry_snapshot_id: "#{catalog_revision_id}-telemetry-snapshot",
        command_snapshot_id: nil,
        content_sha256: "#{catalog_revision_id}-sha",
        created_by: %{"service_identity_id" => "dashboard-browser-smoke"},
        metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
      })

    assert {:ok, _event} =
             revision
             |> Event.from_catalog_revision(occurred_at)
             |> OperationalEvents.persist_event()

    catalog_revision_id
  end

  defp evaluate_limit_events!(org, mission, spacecraft) do
    assert {:ok, run} =
             Cadence.evaluate_telemetry_limits(org.organization_id, mission.mission_id,
               spacecraft_id: spacecraft.spacecraft_id
             )

    assert run.status == :completed
    assert run.emitted_event_count >= 1
  end

  defp persist_replay_dashboard_sources!(organization_id, mission_id) do
    replay_telemetry_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "managed_questdb_replay",
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: :mission_isolated,
        metadata: %{storage: :postgres_replay, bootstrap_default?: false}
    }

    replay_telemetry_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
      | binding_id: "replay_telemetry",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        data_source_id: "managed_questdb_replay",
        dataset: "replay",
        metadata: %{bootstrap_default?: false}
    }

    replay_limits_binding = %DataBinding{
      DataSources.default_flight_limits_binding()
      | binding_id: "replay_limits",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "telemetry_limit_events",
        metadata: %{bootstrap_default?: false}
    }

    replay_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "replay_operational_observables",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "operational_observables_replay",
        metadata: %{bootstrap_default?: false}
    }

    replay_events_binding = %DataBinding{
      DataSources.default_flight_events_binding()
      | binding_id: "replay_events",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "mission_events_replay",
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, persisted_source} = DataSources.persist_data_source(replay_telemetry_source)
    assert persisted_source.data_source_id == "managed_questdb_replay"
    assert persisted_source.isolation_level == :mission_isolated

    assert {:ok, persisted_telemetry_binding} =
             DataSources.persist_data_binding(replay_telemetry_binding)

    assert persisted_telemetry_binding.binding_id == "replay_telemetry"
    assert persisted_telemetry_binding.realm == :replay

    assert {:ok, persisted_limits_source} =
             DataSources.persist_data_source(DataSources.default_limits_data_source())

    assert persisted_limits_source.data_source_id == "managed_limits_projection"

    assert {:ok, persisted_operational_source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert persisted_operational_source.data_source_id == "managed_operational_observables"

    assert {:ok, persisted_events_source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    assert persisted_events_source.data_source_id == "managed_events_projection"

    assert {:ok, persisted_limits_binding} =
             DataSources.persist_data_binding(replay_limits_binding)

    assert persisted_limits_binding.binding_id == "replay_limits"
    assert persisted_limits_binding.realm == :replay

    assert {:ok, persisted_operational_binding} =
             DataSources.persist_data_binding(replay_operational_binding)

    assert persisted_operational_binding.binding_id == "replay_operational_observables"
    assert persisted_operational_binding.realm == :replay

    assert {:ok, persisted_events_binding} =
             DataSources.persist_data_binding(replay_events_binding)

    assert persisted_events_binding.binding_id == "replay_events"
    assert persisted_events_binding.realm == :replay

    %{
      telemetry_data_source_id: replay_telemetry_source.data_source_id,
      telemetry_binding_id: replay_telemetry_binding.binding_id,
      limits_data_source_id: DataSources.default_limits_data_source().data_source_id,
      limits_binding_id: replay_limits_binding.binding_id,
      operational_data_source_id:
        DataSources.default_operational_observables_data_source().data_source_id,
      operational_binding_id: replay_operational_binding.binding_id,
      events_data_source_id: DataSources.default_events_data_source().data_source_id,
      events_binding_id: replay_events_binding.binding_id
    }
  end

  defp persist_replay_run!(mission, replay_run_id, event_time) do
    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: "#{mission.mission_id}-#{replay_run_id}-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 1,
        replayed_sample_count: 0,
        started_at: DateTime.add(event_time, -60, :second),
        completed_at: DateTime.add(event_time, 60, :second)
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
  end

  defp persist_transport_capability_event!(
         organization_id,
         mission_id,
         transport_record_id,
         transport_id,
         event_kind,
         recorded_at,
         opts
       ) do
    replay_run_id = Keyword.get(opts, :replay_run_id)

    payload =
      %{
        transport_record_id: transport_record_id,
        contact_id: Keyword.get(opts, :contact_id),
        realized_contact_id: Keyword.get(opts, :contact_id),
        path_id: Keyword.get(opts, :path_id),
        capability_instance_id: transport_id,
        binding_set_id: Keyword.get(opts, :binding_set_id, "browser-binding-set-alpha"),
        binding_set_version: Keyword.get(opts, :binding_set_version, 1),
        activation_id: Keyword.get(opts, :activation_id, "browser-activation-alpha"),
        family_key: Keyword.get(opts, :family_key, :heartbeat_monitor),
        partition_affinity: :source_endpoint,
        partition_value: Keyword.fetch!(opts, :source_endpoint_id),
        event_kind: event_kind,
        timer_key: Keyword.get(opts, :timer_key),
        emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
        emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
        action_request_count: Keyword.get(opts, :action_request_count, 0),
        state_snapshot: Keyword.get(opts, :state_snapshot, %{active?: true}),
        recorded_at: recorded_at,
        source_endpoint_id: Keyword.fetch!(opts, :source_endpoint_id),
        ground_station_id: Keyword.fetch!(opts, :ground_station_id),
        link_id: Keyword.fetch!(opts, :link_id),
        replay_run_id: replay_run_id
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    event =
      Event.new(%{
        event_id:
          [
            "transport-capability-record",
            transport_record_id,
            replay_run_id
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(":"),
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: recorded_at,
        recorded_at: recorded_at,
        effective_at: recorded_at,
        category: :comms,
        kind: transport_capability_event_kind(event_kind),
        severity: :info,
        actor: if(replay_run_id, do: %{kind: :replay, id: replay_run_id}, else: %{kind: :system}),
        subject: %{kind: :transport, id: transport_id},
        scope:
          %{
            contact_id: Keyword.get(opts, :contact_id),
            realized_contact_id: Keyword.get(opts, :contact_id),
            path_id: Keyword.get(opts, :path_id),
            capability_instance_id: transport_id,
            binding_set_id: payload.binding_set_id,
            activation_id: payload.activation_id,
            timer_key: Keyword.get(opts, :timer_key),
            replay_run_id: replay_run_id
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(),
        causality:
          %{
            correlation_id: transport_id,
            source_record_kind: :transport_capability_record,
            source_record_id: transport_record_id,
            replay_run_id: replay_run_id
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(),
        payload: payload,
        current: payload,
        metadata:
          %{replay_run_id: replay_run_id}
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  defp transport_capability_event_kind(:initialized), do: :transport_initialized

  defp transport_capability_event_kind(:transport_event_handled),
    do: :transport_event_handled

  defp transport_capability_event_kind(:control_input_handled),
    do: :transport_control_input_handled

  defp transport_capability_event_kind(:timer_handled), do: :transport_timer_handled

  defp persist_operational_observable_state_event!(
         organization_id,
         mission_id,
         snapshot_id,
         observable_id,
         link_id,
         state,
         observed_at,
         opts
       ) do
    resource_id = Keyword.get(opts, :resource_id, link_id)

    event =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: snapshot_id,
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: observable_id,
        resource_id: resource_id,
        scope_kind: Keyword.get(opts, :scope_kind, :link),
        transport_id: Keyword.get(opts, :transport_id, "browser-transport-alpha"),
        source_endpoint_id:
          Keyword.get(opts, :source_endpoint_id, "browser-source-endpoint-alpha"),
        ground_station_id: Keyword.get(opts, :ground_station_id, "dss-14"),
        link_id: link_id,
        adapter_key: :tcp_socket,
        connection_state: connection_state(observable_id, state),
        state: operational_observable_state(observable_id, state),
        replay_run_id: Keyword.get(opts, :replay_run_id),
        observed_at: observed_at
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  defp connection_state(observable_id, state)
       when observable_id in [
              "comms.transport.connection_state",
              "ground.station.connection_state"
            ],
       do: state

  defp connection_state(_observable_id, _state), do: nil

  defp operational_observable_state(observable_id, state)
       when observable_id in [
              "link.rf_lock_state",
              "link.frame_sync_state",
              "ground.station.antenna_pointing_state"
            ],
       do: state

  defp operational_observable_state(_observable_id, _state), do: nil

  defp persist_operational_observable_metric_event!(
         organization_id,
         mission_id,
         sample_id,
         observable_id,
         resource_id,
         value,
         observed_at,
         opts
       ) do
    metric_attrs = %{
      sample_id: sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: operational_observable_metric_scope_kind(observable_id),
      transport_id: Keyword.get(opts, :transport_id, "browser-transport-alpha"),
      source_endpoint_id: Keyword.get(opts, :source_endpoint_id, "browser-source-endpoint-alpha"),
      ground_station_id: Keyword.get(opts, :ground_station_id, "dss-14"),
      link_id:
        Keyword.get(
          opts,
          :link_id,
          operational_observable_metric_link_id(observable_id, resource_id)
        ),
      adapter_key: :tcp_socket,
      unit: operational_observable_metric_unit(observable_id),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    }

    event =
      metric_attrs
      |> Map.put(operational_observable_metric_value_key(observable_id), value)
      |> Event.from_operational_observable_metric_sample()

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  defp operational_observable_metric_scope_kind(observable_id)
       when observable_id in [
              "link.snr_db",
              "link.eb_n0_db",
              "link.symbol_rate_sps",
              "link.doppler_hz"
            ],
       do: :link

  defp operational_observable_metric_scope_kind("ingress.processing_latency_ms"),
    do: :source_endpoint

  defp operational_observable_metric_scope_kind(_observable_id), do: :transport

  defp operational_observable_metric_link_id(observable_id, resource_id)
       when observable_id in [
              "link.snr_db",
              "link.eb_n0_db",
              "link.symbol_rate_sps",
              "link.doppler_hz"
            ],
       do: resource_id

  defp operational_observable_metric_link_id(_observable_id, _resource_id), do: "link-alpha"

  defp operational_observable_metric_value_key("link.snr_db"), do: :snr_db
  defp operational_observable_metric_value_key("link.eb_n0_db"), do: :eb_n0_db
  defp operational_observable_metric_value_key("link.symbol_rate_sps"), do: :symbol_rate_sps
  defp operational_observable_metric_value_key("link.doppler_hz"), do: :doppler_hz

  defp operational_observable_metric_value_key("ingress.processing_latency_ms"), do: :value

  defp operational_observable_metric_value_key("comms.transport.uplink_bitrate"),
    do: :uplink_bitrate

  defp operational_observable_metric_value_key(_observable_id), do: :downlink_bitrate

  defp operational_observable_metric_unit("link.snr_db"), do: "dB"
  defp operational_observable_metric_unit("link.eb_n0_db"), do: "dB"
  defp operational_observable_metric_unit("link.symbol_rate_sps"), do: "sym/s"
  defp operational_observable_metric_unit("link.doppler_hz"), do: "Hz"
  defp operational_observable_metric_unit("ingress.processing_latency_ms"), do: "ms"
  defp operational_observable_metric_unit("comms.transport.downlink_bitrate"), do: "bit/s"
  defp operational_observable_metric_unit("comms.transport.uplink_bitrate"), do: "bit/s"
  defp operational_observable_metric_unit(_observable_id), do: nil

  defp managed_action_operational_event(
         organization_id,
         mission_id,
         suffix,
         occurred_at,
         replay_run_id
       ) do
    %ManagedActionRequest{
      action_request_id: "browser-managed-action-#{suffix}",
      mission_id: mission_id,
      capability_instance_id: "browser-packet-counter-#{suffix}",
      family_key: :packet_counter,
      activation_id: "activation-#{suffix}",
      binding_set_id: "binding-set-#{suffix}",
      binding_set_version: 7,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-#{suffix}",
      action_kind: :schedule_timer,
      packet_id: "packet-#{suffix}",
      evidence_id: "evidence-#{suffix}",
      request_document: %{"timer_key" => "flush"},
      requested_at: occurred_at
    }
    |> Event.from_managed_action_request(replay_run_id)
    |> Map.put(:organization_id, organization_id)
  end

  defp contact_interval_operational_event(
         organization_id,
         mission_id,
         contact_id,
         source_endpoint_ref,
         starts_at,
         ends_at,
         replay_run_id
       ) do
    Event.new(%{
      event_id: "operational_event:scheduled_contact_interval:#{contact_id}:#{replay_run_id}",
      organization_id: organization_id,
      mission_id: mission_id,
      occurred_at: starts_at,
      recorded_at: starts_at,
      effective_at: starts_at,
      category: :contact,
      kind: :scheduled_contact_interval,
      severity: :info,
      actor: %{kind: :replay, id: replay_run_id},
      subject: %{kind: :contact, id: contact_id},
      scope: %{
        replay_run_id: replay_run_id,
        source_endpoint_ref: source_endpoint_ref
      },
      causality: %{
        correlation_id: contact_id,
        replay_run_id: replay_run_id
      },
      payload: %{
        scheduled_contact_id: contact_id,
        starts_at: starts_at,
        ends_at: ends_at,
        status: :scheduled,
        source_endpoint_refs: [source_endpoint_ref]
      }
    })
  end

  defp insert_replay_telemetry_samples!(samples, replay_run_id) do
    sample_ids = Enum.map(samples, & &1.sample_id)
    provenance = replay_storage_provenance(replay_run_id)

    {count, _rows} =
      TelemetrySampleRow
      |> where([row], row.sample_id in ^sample_ids)
      |> Repo.update_all(set: [provenance: provenance])

    assert count == length(sample_ids)

    Enum.each(samples, fn sample ->
      replay_sample = %{sample | provenance: provenance}

      assert {:ok, _row} =
               Repo.insert(ReplayTelemetrySampleRow.changeset(replay_run_id, replay_sample))
    end)
  end

  defp insert_replay_persisted_telemetry_samples!(sample_ids, replay_run_id) do
    rows =
      TelemetrySampleRow
      |> where([row], row.sample_id in ^sample_ids)
      |> Repo.all()

    assert length(rows) == length(sample_ids)

    rows
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
    |> Enum.each(fn sample ->
      assert {:ok, _row} =
               Repo.insert(ReplayTelemetrySampleRow.changeset(replay_run_id, sample))
    end)
  end

  defp insert_replay_limit_events!(mission, spacecraft, samples, replay_run_id) do
    samples
    |> Enum.with_index(1)
    |> Enum.each(fn {sample, index} ->
      value = if index == 1, do: 25, else: 35

      event = %LimitEvent{
        limit_event_id: "browser-smoke-replay-limit-#{index}",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        point_id: "HK.counter",
        point_name: "HK.counter",
        source_sample_type: :telemetry_sample,
        sample_id: sample.sample_id,
        limit_definition_id: "browser-viewport-counter-limits",
        limit_definition_version: 1,
        limit_set_name: "browser-smoke",
        evaluated_value: value,
        limit_state: if(value >= 30, do: :red_high, else: :yellow_high),
        normalized_state: if(value >= 30, do: :red, else: :yellow),
        violation: true,
        generation_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        provenance: replay_storage_provenance(replay_run_id)
      }

      assert {:ok, _row} = Repo.insert(TelemetryLimitEventRow.changeset(event))
    end)
  end

  defp replay_storage_provenance(replay_run_id) do
    %{
      "storage" => %{
        "realm" => "replay",
        "data_source_id" => "managed_questdb_replay",
        "binding_id" => "replay_telemetry",
        "replay_run_id" => replay_run_id,
        "dataset" => "replay"
      }
    }
  end

  defp record_completed_late_data_policy_source_event!(
         org,
         mission,
         dashboard,
         spacecraft,
         samples,
         limit_mode,
         opts \\ []
       ) do
    [first_sample | _rest] = samples
    last_sample = List.last(samples)

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "completed",
               %{
                 backfill_run_id: "browser-smoke-late-data-policy-#{limit_mode}",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 spacecraft_id: spacecraft.spacecraft_id,
                 source_from: sample_observed_at(first_sample),
                 source_to: sample_observed_at(last_sample),
                 receipt_from: first_sample.receipt_time,
                 receipt_to: last_sample.receipt_time,
                 sample_count: length(samples),
                 authority: :authoritative,
                 reason: "historical_data_job_completed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "workflow_job_status" => "completed",
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_limit_mode" => limit_mode,
                     "dashboard_data_view" => "canonical",
                     "dashboard_time_mode" => Keyword.get(opts, :dashboard_time_mode, "live"),
                     "dashboard_replay_run_id" => Keyword.get(opts, :dashboard_replay_run_id)
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    event
  end

  defp sample_observed_at(%{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp sample_observed_at(%{receipt_time: %DateTime{} = receipt_time}), do: receipt_time

  defp record_backfill_workflow_event!(org, mission, stage, attrs) do
    run_id = Map.fetch!(attrs, :run_id)
    point_id = Map.get(attrs, :point_id)
    request_group_id = Map.fetch!(attrs, :request_group_id)
    item_index = Map.fetch!(attrs, :item_index)
    item_count = Map.fetch!(attrs, :item_count)
    payload_overrides = Map.get(attrs, :payload, %{})

    event_attrs =
      %{
        backfill_run_id: run_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        source_from: ~U[2023-11-14 22:12:00Z],
        source_to: ~U[2023-11-14 22:15:00Z],
        authority: :advisory,
        reason: "browser_smoke_closure_fixture_#{stage}",
        actor_id: "system",
        actor_kind: "system",
        payload:
          Map.merge(
            %{
              "request_source" => "dashboard_direct_request",
              "request_mode" => "bulk_points",
              "request_group_id" => request_group_id,
              "request_item_index" => item_index,
              "request_item_count" => item_count,
              "request_item_run_id" => run_id
            },
            payload_overrides
          )
      }
      |> Map.merge(maybe_event_point_attrs(point_id))

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               stage,
               event_attrs,
               dashboard_runtime_invalidation?: false
             )

    event
  end

  defp historical_workflow_item_attrs(
         org,
         mission,
         run_id,
         point_id,
         request_group_id,
         item_index,
         item_count,
         opts
       ) do
    dashboard_context = Keyword.fetch!(opts, :dashboard_context)
    comparison_review_origin = Keyword.get(opts, :comparison_review_origin)

    %{
      backfill_run_id: run_id,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2023-11-14 22:12:00Z],
      source_to: ~U[2023-11-14 22:15:00Z],
      authority: :advisory,
      reason: "browser_smoke_real_group_job",
      actor_id: "system",
      actor_kind: "system",
      run_id: run_id,
      point_id: point_id,
      request_group_id: request_group_id,
      item_index: item_index,
      item_count: item_count,
      payload:
        %{
          "request_source" => "dashboard_direct_request",
          "request_mode" => "bulk_points",
          "request_group_id" => request_group_id,
          "request_item_index" => item_index,
          "request_item_count" => item_count,
          "request_item_run_id" => run_id,
          "dashboard_context" => dashboard_context
        }
        |> maybe_put("comparison_review_origin", comparison_review_origin)
    }
    |> maybe_domain_point_attrs(point_id)
  end

  defp maybe_event_point_attrs(point_id) when is_binary(point_id) and point_id != "" do
    %{observable_id: point_id, point_id: point_id}
  end

  defp maybe_event_point_attrs(_point_id), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_domain_point_attrs(attrs, point_id) when is_binary(point_id) and point_id != "" do
    attrs
    |> Map.put(:observable_id, point_id)
    |> Map.put(:point_id, point_id)
  end

  defp maybe_domain_point_attrs(attrs, _point_id), do: attrs

  defp enqueue_failed_historical_workflow_job!(mission, run_id, reason) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, reason)
    assert failed_job.status == :failed
    failed_job
  end

  defp enqueue_completed_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    background_job_row = Repo.get!(BackgroundJobRow, job.job_id)
    completed_job = %{job | status: :completed, completed_at: DateTime.utc_now()}

    assert {:ok, updated_row} =
             background_job_row
             |> BackgroundJobRow.changeset(completed_job)
             |> Repo.update()

    BackgroundJobRow.to_domain(updated_row)
  end

  defp enqueue_stale_running_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, running_job} = Cadence.Jobs.fetch_job(job.job_id)

    stale_job = %{
      running_job
      | started_at: DateTime.add(DateTime.utc_now(), -1_200, :second)
    }

    assert {:ok, updated_row} =
             job.job_id
             |> then(&Repo.get!(BackgroundJobRow, &1))
             |> BackgroundJobRow.changeset(stale_job)
             |> Repo.update()

    BackgroundJobRow.to_domain(updated_row)
  end

  defp enqueue_historical_workflow_job(mission, run_id) do
    Cadence.Jobs.enqueue(
      :telemetry_historical_data_workflow,
      mission.mission_id,
      run_id,
      %{
        "workflow" => "backfill",
        "attrs" => %{"backfill_run_id" => run_id}
      }
    )
  end

  defp operational_rf_state_timeline_source_execution_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          link_rf_lock_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-link-rf-lock-state-revision"
          end,
          link_rf_frame_sync_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-link-rf-frame-sync-state-revision"
          end,
          link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
            [
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                lock_state: :acquiring,
                observed_at: ~U[2026-06-17 12:00:30Z]
              },
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                lock_state: :locked,
                observed_at: ~U[2026-06-17 12:01:30Z]
              },
              %{
                transport_id: "browser-transport-beta",
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_assignment_id: "link-beta",
                adapter_key: :tcp_socket,
                lock_state: :unlocked,
                observed_at: ~U[2026-06-17 12:01:30Z]
              }
            ]
          end,
          link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
            [
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                frame_sync_state: :acquiring,
                observed_at: ~U[2026-06-17 12:00:45Z]
              },
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                frame_sync_state: :synchronized,
                observed_at: ~U[2026-06-17 12:02:00Z]
              },
              %{
                transport_id: "browser-transport-beta",
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_assignment_id: "link-beta",
                adapter_key: :tcp_socket,
                frame_sync_state: :lost,
                observed_at: ~U[2026-06-17 12:02:00Z]
              }
            ]
          end
        ]
      }
    ]
  end

  defp operational_transport_execution_state_timeline_source_execution_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-transport-execution-state-revision"
          end,
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            [
              transport_execution_interval(
                "browser-transport-execution-alpha-1",
                "browser-transport-alpha",
                :initialized,
                ~U[2026-06-17 12:00:10Z],
                ~U[2026-06-17 12:01:30Z],
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_id: "link-alpha",
                source_event_id: "browser-transport-execution-event-alpha-1"
              ),
              transport_execution_interval(
                "browser-transport-execution-alpha-2",
                "browser-transport-alpha",
                :transport_event_handled,
                ~U[2026-06-17 12:01:30Z],
                ~U[2026-06-17 12:03:30Z],
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_id: "link-alpha",
                source_event_id: "browser-transport-execution-event-alpha-2"
              ),
              transport_execution_interval(
                "browser-transport-execution-beta-1",
                "browser-transport-beta",
                :timer_handled,
                ~U[2026-06-17 12:02:00Z],
                ~U[2026-06-17 12:03:00Z],
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_id: "link-beta",
                contact_id: "browser-contact-beta",
                path_id: "browser-uplink-beta",
                source_event_id: "browser-transport-execution-event-beta-1"
              )
            ]
          end
        ]
      }
    ]
  end

  defp operational_transport_execution_state_timeline_source_unavailable_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-transport-execution-state-unavailable-revision"
          end,
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            raise "browser transport execution source unavailable"
          end
        ]
      }
    ]
  end

  defp transport_execution_interval(
         interval_id,
         transport_id,
         event_kind,
         starts_at,
         ends_at,
         opts
       ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "browser-org",
      mission_id: "browser-mission",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.fetch!(opts, :source_event_id),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" => "record-#{interval_id}",
        "source_endpoint_id" => Keyword.get(opts, :source_endpoint_id),
        "ground_station_id" => Keyword.get(opts, :ground_station_id),
        "link_assignment_id" => Keyword.get(opts, :link_id),
        "contact_id" => Keyword.get(opts, :contact_id, "browser-contact-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "browser-uplink-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
    }
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp persist_dashboard_defaults!(org, mission, dashboard, defaults) do
    %Document{} = document = fetch_dashboard_document!(org, mission, dashboard)
    updated_document = %Document{document | defaults: defaults}

    assert {:ok, %Document{} = draft_document} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               updated_document,
               expected_version: Document.version(document)
             )

    draft_version = Document.version(draft_document)

    assert {:ok, %Cadence.Dashboards.Version{document: %Document{} = published_document}} =
             Cadence.Dashboards.publish_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               draft_version,
               expected_version: draft_version
             )

    published_document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp placement_by_id!(%Document{} = document, placement_id) do
    Enum.find(document.placements, &(&1.placement_id == placement_id))
  end

  defp persist_repeated_dashboard_document!(org, mission, spacecraft_ids) do
    [primary_spacecraft_id | _] = spacecraft_ids

    document = %Document{
      dashboard_id: "dashboard-repeat-render-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Repeat Render Browser",
      defaults: %{
        "scope" => %{
          "primary" => %{
            "kind" => "spacecraft",
            "mode" => "many",
            "ids" => spacecraft_ids
          }
        },
        "time" => %{
          "mode" => "live",
          "axis" => "generation_time",
          "range" => %{"kind" => "relative", "duration_ms" => 300_000}
        },
        "data" => %{
          "realm" => "flight",
          "source_mode" => "primary",
          "allowed_realms" => ["flight"]
        }
      },
      placements: [
        %Placement{
          placement_id: "placement-repeat",
          layout: %{x: 0, y: 0, w: 4, h: 3},
          repeat: %{axis: :scope, over: :spacecraft, layout: :wrap_grid, max_instances: 12},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.status_matrix",
            widget_type_version: 1,
            title: "Repeated Status",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              scope_mode: :repeat,
              sampling: :latest,
              overlays: []
            },
            options: %{}
          }
        },
        %Placement{
          placement_id: "placement-trend",
          layout: %{x: 0, y: 3, w: 6, h: 3},
          scope_override: %{
            primary: %{kind: "spacecraft", mode: "one", ids: [primary_spacecraft_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Counter Trend",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: []
            },
            options: %{}
          }
        }
      ]
    }

    assert {:ok, persisted} = Cadence.Dashboards.persist_document(org.organization_id, document)
    persisted
  end

  defp persist_replay_operational_metric_time_series_dashboard!(
         org,
         mission,
         transport_id,
         opts
       ) do
    data_override = Keyword.get(opts, :data_override)
    overlays = Keyword.get(opts, :overlays, [])
    source_endpoint_id = Keyword.fetch!(opts, :source_endpoint_id)

    document = %Document{
      dashboard_id: "dashboard-replay-operational-metric-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Replay Operational Metric Time Series Browser",
      placements: [
        %Placement{
          placement_id: "placement-rf-snr-history",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-transport-bitrate-history",
          layout: %{x: 6, y: 0, w: 6, h: 3},
          data_override: data_override,
          scope_override: %{
            primary: %{kind: "transport", mode: "one", ids: [transport_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Transport Bitrate Replay",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.downlink_bitrate",
                "comms.transport.uplink_bitrate"
              ],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-rf-ebn0-history",
          layout: %{x: 0, y: 3, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF Eb/N0 Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-rf-mixed-history",
          layout: %{x: 6, y: 3, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF Mixed Metric Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db", "link.symbol_rate_sps"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-ingress-latency-history",
          layout: %{x: 0, y: 6, w: 6, h: 3},
          data_override: data_override,
          scope_override: %{
            primary: %{kind: "source_endpoint", mode: "one", ids: [source_endpoint_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Ingress Latency Replay",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, persisted} = Cadence.Dashboards.persist_document(org.organization_id, document)
    persisted
  end

  defp repeated_placement_id(placement_id, spacecraft_id) do
    "#{placement_id}__repeat__spacecraft__#{spacecraft_id}"
  end

  defp ensure_assets_built!(app_root) do
    assert {output, 0} =
             System.cmd("mix", ["assets.build"],
               cd: app_root,
               env: [{"MIX_ENV", "test"}],
               stderr_to_stdout: true
             )

    assert output =~ "tailwindcss"
    assert File.exists?(Path.join(app_root, "priv/static/assets/app.css"))
    assert File.exists?(Path.join(app_root, "priv/static/assets/app.js"))
  end

  defp free_tcp_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp start_browser_endpoint!(port, sandbox_owner) do
    previous_owner = Application.get_env(:cadence_web, :browser_test_sandbox_owner)
    sandbox_owner_key = "browser-sandbox-#{System.unique_integer([:positive])}"

    Application.put_env(:cadence_web, :browser_test_sandbox_owner, %{
      owner: sandbox_owner,
      key: sandbox_owner_key
    })

    on_exit(fn ->
      case previous_owner do
        nil -> Application.delete_env(:cadence_web, :browser_test_sandbox_owner)
        owner -> Application.put_env(:cadence_web, :browser_test_sandbox_owner, owner)
      end
    end)

    start_supervised!(
      {Bandit,
       plug: {__MODULE__, sandbox_owner: sandbox_owner},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: port}
    )
  end

  def init(opts), do: opts

  def call(conn, opts) do
    opts
    |> Keyword.fetch!(:sandbox_owner)
    |> then(&Sandbox.allow(Cadence.Repo, &1, self()))

    CadenceWeb.Endpoint.call(conn, [])
  end

  defp rendered_dashboard_artifact!(html, app_root) do
    path =
      Path.join(System.tmp_dir!(), "cadence-rendered-dashboard-#{System.unique_integer()}.html")

    File.write!(path, rendered_dashboard_document(html, app_root))
    path
  end

  defp rendered_dashboard_document(html, app_root) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Rendered dashboard viewport smoke</title>
        <link rel="stylesheet" href="#{asset_file_url(app_root, "app.css")}" />
        <style>
          #{rendered_dashboard_smoke_css()}
        </style>
      </head>
      <body>
        #{html}
      </body>
    </html>
    """
  end

  defp asset_file_url(app_root, filename) do
    app_root
    |> Path.join("priv/static/assets/#{filename}")
    |> Path.expand()
    |> then(&"file://#{&1}")
  end

  defp rendered_dashboard_smoke_css do
    """
    :root {
      color-scheme: dark;
      --bg: #10131d;
      --panel: #171b28;
      --panel-strong: #202638;
      --line: rgba(114, 211, 255, 0.28);
      --line-strong: rgba(114, 211, 255, 0.52);
      --text: #d9e4f1;
      --muted: #8c9bb2;
      --accent: #f04f9c;
      --cell: 88px;
    }

    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--text); }
    body { font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    button, a { color: inherit; font: inherit; }
    .hidden { display: none !important; }

    #ops-dashboard-show-page {
      min-height: 900px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      padding: 12px 392px 12px 12px;
      overflow: hidden;
    }

    #ops-dashboard-show-page > div:first-child {
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 38px;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      padding: 6px 8px;
    }

    #ops-dashboard-show-page h1,
    #ops-dashboard-show-page h2,
    #dashboard-panel h2 {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
      font-size: 0.95rem;
      line-height: 1.2;
    }

    #ops-dashboard-show-page button,
    #ops-dashboard-show-page a,
    #dashboard-panel button {
      max-width: 100%;
      overflow-wrap: anywhere;
    }

    #dashboard-menu {
      flex: 0 0 auto;
    }

    .grid-stack {
      position: relative;
      min-height: 540px;
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 6px;
    }

    .grid-stack > .grid-stack-item {
      position: absolute;
      padding: 0;
      min-height: 80px;
    }

    .grid-stack > .grid-stack-item[gs-y="0"] { top: 0; }
    .grid-stack > .grid-stack-item[gs-y="1"] { top: calc(var(--cell) * 1); }
    .grid-stack > .grid-stack-item[gs-y="2"] { top: calc(var(--cell) * 2); }
    .grid-stack > .grid-stack-item[gs-y="3"] { top: calc(var(--cell) * 3); }
    .grid-stack > .grid-stack-item[gs-x="0"] { left: 0; }
    .grid-stack > .grid-stack-item[gs-x="4"] { left: 33.333%; }
    .grid-stack > .grid-stack-item[gs-w="4"] { width: 33.333%; }
    .grid-stack > .grid-stack-item[gs-w="6"] { width: 50%; }
    .grid-stack > .grid-stack-item[gs-h="2"] { height: calc(var(--cell) * 2); }
    .grid-stack > .grid-stack-item[gs-h="3"] { height: calc(var(--cell) * 3); }

    .grid-stack-item-content {
      position: absolute;
      inset: 0;
      display: flex;
      min-width: 0;
      min-height: 0;
      flex-direction: column;
      gap: 8px;
      overflow: hidden;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      padding: 10px;
    }

    [phx-hook="TelemetryChart"] {
      display: block;
      flex: 1 1 auto;
      min-height: 132px;
      width: 100%;
      border: 1px solid var(--line-strong);
      border-radius: 4px;
      background:
        linear-gradient(to right, rgba(114, 211, 255, 0.14) 1px, transparent 1px) 0 0 / 48px 100%,
        linear-gradient(to bottom, rgba(114, 211, 255, 0.10) 1px, transparent 1px) 0 0 / 100% 36px,
        #111827;
    }

    #dashboard-panel {
      position: fixed;
      top: 0;
      right: 0;
      bottom: 0;
      z-index: 2;
      width: 360px;
      max-width: calc(100vw - 24px);
      display: flex;
      flex-direction: column;
      gap: 10px;
      overflow: auto;
      border-left: 1px solid var(--line-strong);
      background: var(--panel);
      padding: 12px;
    }

    #dashboard-data-link-inspector,
    #dashboard-evidence-inspector {
      display: grid;
      gap: 10px;
      min-width: 0;
    }

    #dashboard-panel dl {
      display: grid;
      grid-template-columns: minmax(84px, 7rem) minmax(0, 1fr);
      gap: 4px 8px;
    }

    #dashboard-panel dd,
    #dashboard-panel dt {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
    }

    @media (max-width: 720px) {
      #ops-dashboard-show-page {
        min-height: 0;
        padding: 12px;
      }

      #ops-dashboard-show-page > div:first-child {
        align-items: stretch;
        flex-direction: column;
      }

      .grid-stack {
        min-height: 0;
        border: 0;
      }

      .grid-stack > .grid-stack-item {
        position: relative;
        top: auto !important;
        left: auto !important;
        width: 100% !important;
        height: auto !important;
        margin-bottom: 12px;
      }

      .grid-stack-item-content {
        position: relative;
        min-height: 140px;
      }

      .grid-stack > .grid-stack-item > .grid-stack-item-content {
        position: relative;
        min-height: 140px;
      }

      #dashboard-panel {
        position: relative;
        width: auto;
        max-width: none;
        margin-top: 12px;
      }
    }
    """
  end
end
