defmodule CadenceWeb.OpsDashboardShowLive.TelemetryWidgetRenderingLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp persist_matrix_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-matrix",
        packet_name: "HK",
        apid: 43,
        fields: [
          %{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint},
          %{name: "voltage", offset_bits: 16, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-matrix-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 43,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest_matrix!(mission, binding_set, spacecraft_id, counter, voltage, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(43, 1, <<counter::16, voltage::16>>)
      })

    {:ok, _result} =
      Cadence.process_and_persist_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp evaluate_limits!(mission) do
    limit_definition =
      Definition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    {:ok, _definition} = Cadence.Limits.persist_limit_definition(limit_definition)
    {:ok, _run} = Cadence.Limits.evaluate(mission.mission_id)
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
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

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp disable_telemetry_storage_runtime_invalidation! do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      Keyword.put(previous_config, :dashboard_runtime_invalidation?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_config)
    end)
  end

  describe "telemetry widget rendering" do
    test "renders status matrix rows from latest telemetry and limit overlays" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Matrix")
      binding_set = persist_matrix_binding_set!(org, mission)

      ingest_matrix!(mission, binding_set, spacecraft.spacecraft_id, 15, 28, 1_700_000_100)
      evaluate_limits!(mission)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Matrix",
          widgets: [
            %{
              type: :status_matrix,
              title: "Counter Matrix",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_ids: ["HK.counter", "HK.voltage"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Counter Matrix").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix][data-engine-backed="true"])
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="quality"]),
               "Good"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="limit"]),
               "Yellow"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.voltage"] [data-status-matrix-field="value"]),
               "28"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.voltage"] [data-status-matrix-field="limit"]),
               "None"
             )

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-evidence="HK.counter"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Observable"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-link-target="limit event"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="HK.counter"][data-status-matrix-row-link-target="limit event"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Normalized state"]),
               "yellow"
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="HK.voltage"][data-status-matrix-row-link-target="telemetry sample"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.voltage"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Raw"]),
               "28"
             )
    end

    test "renders data table rows from latest telemetry and limit overlays" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Table")
      binding_set = persist_matrix_binding_set!(org, mission)

      ingest_matrix!(mission, binding_set, spacecraft.spacecraft_id, 15, 28, 1_700_000_100)
      evaluate_limits!(mission)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Table",
          widgets: [
            %{
              type: :data_table,
              title: "HK Table",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_ids: ["HK.counter", "HK.voltage"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      table_widget = render_item_by_title(document, "HK Table").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table][data-engine-backed="true"])
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="quality"]),
               "Good"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="state"]),
               "Yellow"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.voltage"] [data-data-table-field="value"]),
               "28"
             )

      view
      |> element(
        ~s(#widget-#{table_widget.widget_id} [data-data-table-row-link="HK.voltage"][data-data-table-row-link-target="telemetry sample"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.voltage"
             )
    end
  end
end
