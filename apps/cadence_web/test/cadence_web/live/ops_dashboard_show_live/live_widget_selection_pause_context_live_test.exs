defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetSelectionPauseContextLiveTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp value_tile(point_id, mode \\ :context, spacecraft_id \\ nil) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-telemetry-selection-pause",
        packet_name: "HK",
        apid: 48,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-telemetry-selection-pause-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 48,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(48, 1, <<value::16>>)
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

  defp chart_backfill(html, widget_id) do
    html
    |> chart_attribute(widget_id, "data-backfill")
    |> chart_backfill_points()
  end

  defp chart_backfill_points(%{"series" => [%{"points" => points} | _rest]}), do: points
  defp chart_backfill_points(points) when is_list(points), do: points
  defp chart_backfill_points(_payload), do: []

  defp chart_limit_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-limit-markers")
  end

  defp chart_attribute(html, widget_id, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  defp chart_optional_attribute(html, widget_id, attribute) do
    case html
         |> LazyHTML.from_fragment()
         |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
         |> LazyHTML.attribute(attribute) do
      [value] -> Jason.decode!(value)
      [] -> nil
    end
  end

  defp chart_dom_id(html, widget_id) do
    [id] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute("id")

    id
  end

  defp centered_archive_range(timestamp_ms) do
    {:ok, center} = DateTime.from_unix(timestamp_ms, :millisecond)

    {
      center |> DateTime.add(-150, :second) |> DateTime.to_iso8601(),
      center |> DateTime.add(150, :second) |> DateTime.to_iso8601()
    }
  end

  defp point_meta([_timestamp, _value, metadata]) when is_map(metadata), do: metadata
  defp point_meta(_point), do: %{}

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

  describe "live widget telemetry selection pause context" do
    test "pauses a selected telemetry sample into archive context and resumes live" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      evaluate_limits!(mission)

      assert [older_sample, _latest_sample] =
               TelemetryReads.sample_history(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: spacecraft.spacecraft_id,
                 order: :asc
               )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            value_tile("HK.counter"),
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
              type: :time_series,
              title: "Counter Mirror",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 4, y: 3, w: 6, h: 3}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget
      mirror_widget = render_item_by_title(document, "Counter Mirror").widget
      trend_widget_id = trend_widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      older_point = html |> chart_backfill(trend_widget.widget_id) |> Enum.at(0)
      older_meta = point_meta(older_point)
      older_link_id = older_meta["link_id"]
      older_timestamp_ms = List.first(older_point)
      older_sample_id = older_sample.sample_id

      assert older_meta["sample_id"] == older_sample_id
      assert is_binary(older_link_id)

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => older_link_id,
        "placement-id" => trend_widget_id,
        "target" => "telemetry_sample",
        "target-id" => older_sample_id,
        "timestamp-ms" => older_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^older_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "telemetry_sample",
            "target_id" => ^older_sample_id,
            "timestamp_ms" => ^older_timestamp_ms
          }
        },
        1_000
      )

      selected_path = assert_patch(view)
      assert selected_path =~ "panel=data_link"
      assert selected_path =~ "selected_target=telemetry_sample"

      assert has_element?(view, "#dashboard-pause-at-selection:not([disabled])")

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 25, 1_700_000_500)
      evaluate_limits!(mission)
      render_dashboard_async(view)

      future_sample =
        org.organization_id
        |> TelemetryReads.sample_history(mission.mission_id, "HK.counter",
          spacecraft_id: spacecraft.spacecraft_id,
          order: :asc
        )
        |> List.last()

      assert future_sample.raw_value == 25
      future_sample_id = future_sample.sample_id

      {expected_from, expected_to} = centered_archive_range(older_timestamp_ms)

      view |> element("#dashboard-pause-at-selection") |> render_click()

      paused_path = assert_patch(view)
      assert paused_path =~ "time_mode=archive"
      assert paused_path =~ URI.encode_www_form(expected_from)
      assert paused_path =~ URI.encode_www_form(expected_to)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-dashboard-time-from="#{expected_from}"][data-dashboard-time-to="#{expected_to}"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-time-mode="archive"][data-engine-snapshot="true"][data-engine-live-append-eligible="false"])
             )

      selected_ref = chart_optional_attribute(render(view), trend_widget_id, "data-selected-ref")
      assert selected_ref["placement_id"] == trend_widget_id
      assert selected_ref["target"] == "telemetry_sample"
      assert selected_ref["target_id"] == older_sample_id
      assert selected_ref["timestamp_ms"] == older_timestamp_ms

      assert chart_optional_attribute(render(view), mirror_widget.widget_id, "data-selected-ref") ==
               nil

      paused_markers = chart_limit_markers(render(view), trend_widget.widget_id)
      refute Enum.any?(paused_markers, &(&1["sample_id"] == future_sample_id))

      view |> element("#context-search-form") |> render_change(%{"q" => "alpha"})

      view
      |> element(~s(button[phx-value-spacecraft-id="#{spacecraft.spacecraft_id}"]))
      |> render_click()

      assert_patch(view)
      render_dashboard_async(view)
      paused_html = render(view)
      assert paused_html =~ "15"
      assert paused_html =~ "Yellow"
      refute paused_html =~ "Pick a spacecraft context"

      assert has_element?(view, "#dashboard-time-preset-live:not([disabled])")

      view |> element("#dashboard-time-preset-live") |> render_click()

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-time-mode="live"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
             )

      assert chart_optional_attribute(render(view), mirror_widget.widget_id, "data-selected-ref") ==
               nil

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      html = render(view)
      assert html =~ "25"
      assert html =~ "Red"
      refute html =~ "Pick a spacecraft context"
    end
  end
end
