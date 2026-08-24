defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowComparisonReviewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp value_tile(point_id, mode, spacecraft_id) do
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
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
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

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      RuntimePersistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  describe "historical workflow comparison-review surfaces" do
    test "requests comparison reviews from the rollup and resolves them from activity" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Review")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Review Rollup",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?data_view=all_revisions&compare_data_view=canonical"
        )

      render_dashboard_async(view)

      assert ["dashboard-comparison-toggle-component"] =
               view
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-comparison-toggle-component")
               |> LazyHTML.attribute("id")

      comparison_toggle =
        LiveVue.Test.get_vue(view, id: "dashboard-comparison-toggle-component")

      assert comparison_toggle.props["presentation"]["root"]["attrs"]["id"] ==
               "dashboard-comparison-toggle"

      render_click(
        view,
        comparison_toggle.props["presentation"]["root"]["attrs"]["phx-click"]
      )

      comparison_inspector =
        LiveVue.Test.get_vue(view, id: "dashboard-comparison-inspector-component")

      comparison_presentation = comparison_inspector.props["presentation"]

      assert comparison_presentation["inspector"]["root"]["attrs"]["id"] ==
               "dashboard-comparison-inspector"

      assert comparison_presentation["rollup"]["root"]["attrs"][
               "data-dashboard-comparison-open"
             ] == "1"

      review_form = comparison_presentation["rollup"]["review_form"]
      assert review_form["root"]["attrs"]["phx-submit"] == "request_comparison_review"

      render_submit(view, "request_comparison_review", %{
        "review" => %{"open_findings" => review_form["payload"]["attrs"]["value"]}
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "panel=versions"
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert request_event.event_type == :comparison_review_requested
      assert request_event.actor_id == user.user_id
      assert request_event.payload["source"] == "dashboard_comparison_rollup"
      assert request_event.payload["open_count"] == 1

      request_event_id = request_event.dashboard_lifecycle_event_id

      request_presentation =
        comparison_presentation(view, "request", request_event_id)

      assert %{
               "data-dashboard-comparison-review-request" => ^request_event_id,
               "data-dashboard-comparison-review-status" => "open"
             } = request_presentation["root"]["attrs"]

      activity_controls =
        view
        |> activity_timeline_presentation()
        |> Map.fetch!("controls")

      open_reviews_filter =
        Enum.find(
          activity_controls["controls"]["filters"],
          &(&1["id"] == "dashboard-activity-filter-open-reviews")
        )

      filter_attrs = Map.fetch!(open_reviews_filter, "attrs")

      render_click(
        view,
        Map.fetch!(filter_attrs, "phx-click"),
        %{"filter" => Map.fetch!(filter_attrs, "phx-value-filter")}
      )

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=open_comparison_reviews"

      assert %{
               "data-dashboard-activity-mode" => "open_comparison_reviews",
               "data-dashboard-comparison-review-open-count" => "1",
               "data-dashboard-comparison-review-work-queue-count" => "1"
             } = activity_timeline_presentation(view)["root"]["attrs"]

      resolve_form = request_presentation["actions"]["resolve_form"]

      render_submit(
        view,
        resolve_form["attrs"]["phx-submit"],
        form_payload(resolve_form, %{"resolution_reason" => "Resolved from rollup request"})
      )

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.event_type == :comparison_review_resolved
      assert resolution_event.actor_id == user.user_id

      assert resolution_event.payload["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert resolution_event.payload["resolution_reason"] == "Resolved from rollup request"

      assert resolution_event.payload["workflow_intent"] ==
               request_event.payload["workflow_intent"]

      assert resolution_event.payload["open_findings"] == request_event.payload["open_findings"]
      assert resolution_event.payload["source_open_count"] == request_event.payload["open_count"]

      assert resolution_event.payload["source_open_placement_ids"] ==
               request_event.payload["open_placement_ids"]

      resolution_event_id = resolution_event.dashboard_lifecycle_event_id

      request_presentation =
        comparison_presentation(view, "request", request_event_id)

      assert %{
               "data-dashboard-comparison-review-request" => ^request_event_id,
               "data-dashboard-comparison-review-status" => "resolved",
               "data-dashboard-comparison-review-resolution-event" => ^resolution_event_id
             } = request_presentation["root"]["attrs"]

      resolution_presentation =
        comparison_presentation(view, "resolution", resolution_event_id)

      assert %{
               "data-dashboard-comparison-review-resolution" => ^resolution_event_id,
               "data-dashboard-comparison-review-resolution-workflow-kind" =>
                 "bulk_correction_authority_review",
               "data-dashboard-comparison-review-resolution-workflow-action" =>
                 "request_comparison_review",
               "data-dashboard-comparison-review-resolution-workflow-selection-count" => "1",
               "data-dashboard-comparison-review-resolution-source-open-count" => "1"
             } = resolution_presentation["root"]["attrs"]
    end

    test "resolves mixed comparison reviews with bulk decision audit context" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-untracked"],
                   "workflow_intent" => %{
                     "kind" => "bulk_correction_authority_review",
                     "action" => "request_comparison_review",
                     "selection_count" => 2
                   },
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "runtime_query" => source_context,
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => "identity-counter",
                         "scope_kind" => "transport",
                         "scope_ids" => ["transport-alpha", "transport-beta"],
                         "resource_id" => "transport-alpha",
                         "contact_ids" => ["contact-alpha", "contact-beta"],
                         "transport_id" => "transport-alpha",
                         "source_endpoint_id" => "endpoint-alpha",
                         "ground_station_id" => "dss-14",
                         "scope_link_id" => "link-alpha",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       },
                       %{
                         "placement_id" => "placement-untracked",
                         "title" => "Untracked finding",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      request_event_id = request_event.dashboard_lifecycle_event_id

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      request_presentation =
        comparison_presentation(view, "request", request_event_id)

      resolve_form = request_presentation["actions"]["resolve_form"]

      render_submit(
        view,
        resolve_form["attrs"]["phx-submit"],
        form_payload(resolve_form, %{"resolution_reason" => "Mixed request reviewed"})
      )

      assert_patch(view)

      [_request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.payload["source_bulk_decision_actionable_count"] == 1

      assert resolution_event.payload["source_bulk_decision_actionable_placement_ids"] == [
               "placement-counter"
             ]

      assert resolution_event.payload["source_bulk_decision_skipped_count"] == 1

      assert resolution_event.payload["source_bulk_decision_skipped_placement_ids"] == [
               "placement-untracked"
             ]

      assert resolution_event.payload["source_bulk_decision_skipped_reasons"] == [
               "missing_observation_identity"
             ]

      assert resolution_event.payload["source_scope_kind"] == "transport"
      assert resolution_event.payload["source_scope_ids"] == ["transport-alpha", "transport-beta"]
      assert resolution_event.payload["source_contact_ids"] == ["contact-alpha", "contact-beta"]
      assert resolution_event.payload["source_resource_ids"] == ["transport-alpha"]
      assert resolution_event.payload["source_transport_ids"] == ["transport-alpha"]
      assert resolution_event.payload["source_endpoint_ids"] == ["endpoint-alpha"]
      assert resolution_event.payload["source_ground_station_ids"] == ["dss-14"]
      assert resolution_event.payload["source_scope_link_ids"] == ["link-alpha"]

      resolution_event_id = resolution_event.dashboard_lifecycle_event_id

      resolution_presentation =
        comparison_presentation(view, "resolution", resolution_event_id)

      assert {
               %{
                 "data-dashboard-comparison-review-resolution" => ^resolution_event_id,
                 "data-dashboard-comparison-review-resolution-source-actionable-count" => "1",
                 "data-dashboard-comparison-review-resolution-source-actionable-placements" =>
                   "placement-counter",
                 "data-dashboard-comparison-review-resolution-source-skipped-count" => "1",
                 "data-dashboard-comparison-review-resolution-source-skipped-placements" =>
                   "placement-untracked",
                 "data-dashboard-comparison-review-resolution-source-skipped-reasons" =>
                   "missing_observation_identity",
                 "data-dashboard-comparison-review-resolution-source-scope-kind" => "transport",
                 "data-dashboard-comparison-review-resolution-source-scope-ids" =>
                   "transport-alpha,transport-beta",
                 "data-dashboard-comparison-review-resolution-source-contact-ids" =>
                   "contact-alpha,contact-beta",
                 "data-dashboard-comparison-review-resolution-source-resource-ids" =>
                   "transport-alpha",
                 "data-dashboard-comparison-review-resolution-source-transport-ids" =>
                   "transport-alpha",
                 "data-dashboard-comparison-review-resolution-source-endpoint-ids" =>
                   "endpoint-alpha",
                 "data-dashboard-comparison-review-resolution-source-ground-station-ids" =>
                   "dss-14",
                 "data-dashboard-comparison-review-resolution-source-scope-link-ids" =>
                   "link-alpha"
               },
               "1 actionable / 1 skipped"
             } = {
               resolution_presentation["root"]["attrs"],
               detail_value(resolution_presentation, "bulk-action")
             }
    end

    test "resolves comparison reviews from the versions activity queue" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-1", "placement-2"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "findings" => [
                       %{
                         "placement_id" => "placement-1",
                         "title" => "Bus voltage",
                         "state" => "increased",
                         "decision_status" => "unhandled"
                       },
                       %{
                         "placement_id" => "placement-2",
                         "title" => "Current",
                         "state" => "missing",
                         "decision_status" => "unhandled"
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      request_event_id = request_event.dashboard_lifecycle_event_id

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=comparison_reviews&activity_event=#{request_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      request_presentation =
        comparison_presentation(view, "request", request_event_id)

      assert %{
               "data-dashboard-comparison-review-request" => ^request_event_id,
               "data-dashboard-comparison-review-status" => "open",
               "data-dashboard-comparison-review-target-event-id" => ^request_event_id
             } = request_presentation["root"]["attrs"]

      resolve_form = request_presentation["actions"]["resolve_form"]

      render_submit(
        view,
        resolve_form["attrs"]["phx-submit"],
        form_payload(resolve_form, %{"resolution_reason" => "Reviewed by dashboard operator"})
      )

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.event_type == :comparison_review_resolved

      assert resolution_event.payload["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert resolution_event.payload["resolution_reason"] == "Reviewed by dashboard operator"

      resolution_event_id = resolution_event.dashboard_lifecycle_event_id

      request_presentation =
        comparison_presentation(view, "request", request_event_id)

      assert %{
               "data-dashboard-comparison-review-request" => ^request_event_id,
               "data-dashboard-comparison-review-status" => "resolved",
               "data-dashboard-comparison-review-resolution-event" => ^resolution_event_id,
               "data-dashboard-comparison-review-result-event-id" => ^resolution_event_id,
               "data-dashboard-comparison-review-target-event-id" => ^request_event_id
             } = request_presentation["root"]["attrs"]

      resolution_presentation =
        comparison_presentation(view, "resolution", resolution_event_id)

      assert {
               %{
                 "data-dashboard-comparison-review-resolution" => ^resolution_event_id,
                 "data-dashboard-comparison-review-resolution-result-event-id" =>
                   ^resolution_event_id,
                 "data-dashboard-comparison-review-resolution-target-event-id" =>
                   ^resolution_event_id,
                 "data-dashboard-comparison-review-resolution-source" => ^request_event_id,
                 "data-dashboard-comparison-review-resolution-disposition" => "review_completed",
                 "data-dashboard-comparison-review-resolution-affected-placements" =>
                   "placement-1,placement-2"
               },
               "Reviewed by dashboard operator"
             } = {
               resolution_presentation["root"]["attrs"],
               detail_value(resolution_presentation, "reason")
             }
    end
  end

  defp comparison_presentation(rendered, kind, event_id) do
    row =
      rendered
      |> activity_timeline_presentation()
      |> get_in(["list", "rows"])
      |> Enum.find(&(&1["key"] == event_id))

    expected_id = "dashboard-activity-#{event_id}"

    assert %{
             "key" => ^event_id,
             "order" => order,
             "presentation" => %{"root" => %{"id" => ^expected_id}}
           } = row

    assert is_integer(order)
    assert row["presentation"] == Jason.decode!(Jason.encode!(row["presentation"]))

    child = row["presentation"]["comparison_review"][kind]
    assert child["id"] == "dashboard-comparison-review-#{kind}-#{event_id}-component"
    assert child["attrs"] == %{"data-name" => "ComparisonReviewActivityDetails"}
    assert child["presentation"]["kind"] == kind
    child["presentation"]
  end

  defp activity_timeline_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-version-history-panel-component")

    assert Map.take(vue, [:component, :ssr, :class, :handlers]) == %{
             component: "VersionHistoryPanel",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    panel = vue.props["presentation"]

    assert panel["activity_timeline"]["root"]["attrs"] == %{
             "id" => "dashboard-activity-timeline-component",
             "class" => "contents"
           }

    panel["activity_timeline"]["presentation"]
  end

  defp form_payload(form, overrides) do
    hidden_params =
      Map.new(form["hidden_fields"], fn field ->
        name = field["attrs"]["name"]
        key = name |> String.trim_leading("review[") |> String.trim_trailing("]")
        {key, field["attrs"]["value"]}
      end)

    %{"review" => Map.merge(hidden_params, overrides)}
  end

  defp detail_value(presentation, key) do
    presentation["details"]["rows"]
    |> Enum.find(&(&1["key"] == key))
    |> Map.fetch!("value")
  end
end
