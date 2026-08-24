defmodule CadenceWeb.OpsDataOperationsHandoffLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: role)
    mission = TestFixtures.persist_mission!(organization)

    {TestFixtures.member_conn(user), user, organization, mission}
  end

  test "dashboard context prefills a request that can be followed independently" do
    {conn, user, organization, mission} = signed_in(:member)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        dashboard_id: "historical-gap-dashboard",
        name: "Historical Gap"
      )

    path =
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{dashboard_id: dashboard.dashboard_id, dashboard_version: "3", dashboard_time_mode: "absolute", dashboard_data_view: "all_revisions", dashboard_limit_mode: "observed", realm: "flight", data_source_id: "flight-telemetry", source_binding_id: "flight-telemetry-binding", point_id: "HK.counter", point_ids: "HK.counter, HK.voltage", source_from: "2026-08-01T10:00:00Z", source_to: "2026-08-01T11:00:00Z", comparison_review_request_event_id: "review-request-1", comparison_review_request_kind: "operator_review", comparison_review_open_count: "2", comparison_review_open_placement_ids: "power-tile,thermal-chart"}}"

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "#ops-data-operations-component")
    assert has_element?(view, "#ops-context-rail-component")

    initial_vue = data_operations_vue(view)
    request_form = initial_vue.props["request_form"]

    assert initial_vue.props["page"] == %{
             "id" => "ops-data-operations-page",
             "selected_group_id" => nil,
             "groups_empty" => true,
             "navigation" => %{}
           }

    assert request_form["values"]["dashboard_id"] == dashboard.dashboard_id
    assert request_form["values"]["point_ids"] == "HK.counter, HK.voltage"

    assert Enum.find(request_form["hidden_fields"], &(&1["value_key"] == "dashboard_id")) ==
             %{
               "name" => "historical_workflow_request[dashboard_id]",
               "value_key" => "dashboard_id"
             }

    assert request_form["fields"]["point_ids"]["name"] ==
             "historical_workflow_request[point_ids]"

    assert_json_safe(initial_vue)
    assert_sensitive_data_absent(initial_vue, user, organization)
    assert_single_stream(initial_vue)
    assert stream_rows(initial_vue) == []

    request_values =
      Map.merge(request_form["values"], %{
        "workflow" => "backfill",
        "run_id" => "data-operation-handoff-1",
        "realm" => "flight",
        "data_source_id" => "flight-telemetry",
        "source_binding_id" => "flight-telemetry-binding",
        "point_ids" => "HK.counter, HK.voltage",
        "source_from" => "2026-08-01T10:00:00Z",
        "source_to" => "2026-08-01T11:00:00Z",
        "dashboard_id" => dashboard.dashboard_id,
        "dashboard_version" => "3",
        "dashboard_time_mode" => "absolute",
        "dashboard_data_view" => "all_revisions",
        "dashboard_limit_mode" => "observed",
        "comparison_review_request_event_id" => "review-request-1",
        "comparison_review_request_kind" => "operator_review",
        "comparison_review_open_count" => "2",
        "comparison_review_open_placement_ids" => "power-tile,thermal-chart",
        "reason" => "dashboard_historical_data_gap",
        "confirmed" => "true"
      })

    assert Enum.all?(request_values, fn {key, value} -> is_binary(key) and is_binary(value) end)

    render_hook(view, "record_historical_workflow_request", %{
      "historical_workflow_request" => request_values
    })

    assert_patch(
      view,
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "data-operation-handoff-1"}}"
    )

    recorded_vue = data_operations_vue(view)
    [group_row] = stream_rows(recorded_vue)

    assert group_row == %{
             "__dom_id" => "data-operation-data-operation-handoff-1",
             "href" =>
               ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "data-operation-handoff-1"}}",
             "id" => "data-operation-handoff-1",
             "progress" => "0/2 completed, 0 failed",
             "size" => 2,
             "state" => "requested",
             "workflow" => "backfill"
           }

    selected_group = recorded_vue.props["selected_group"]

    assert selected_group |> Map.keys() |> Enum.sort() ==
             ~w(affected_dashboards audit_events comparison_reviews context id progress state workflow)

    assert selected_group["id"] == "data-operation-handoff-1"
    assert selected_group["state"] == "requested"
    refute Map.has_key?(selected_group, "recovery")

    assert [dashboard_link] = selected_group["affected_dashboards"]
    assert dashboard_link["id"] == "data-operation-dashboard-#{dashboard.dashboard_id}"

    dashboard_uri = URI.parse(dashboard_link["href"])

    assert dashboard_uri.path ==
             "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    assert URI.decode_query(dashboard_uri.query)["selected_data_view"] == "all_revisions"

    assert [comparison_review] = selected_group["comparison_reviews"]

    assert comparison_review == %{
             "id" => "data-operation-comparison-review-request-1",
             "open_count" => "2",
             "open_placement_ids" => "power-tile,thermal-chart",
             "request_event_id" => "review-request-1",
             "request_kind" => "operator_review"
           }

    assert Enum.all?(selected_group["audit_events"], fn audit_event ->
             audit_event |> Map.keys() |> Enum.sort() == ~w(event_type id occurred_at reason)
           end)

    assert_json_safe(recorded_vue)
    assert_sensitive_data_absent(recorded_vue, user, organization)
    assert_single_stream(recorded_vue)

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id
      )

    assert length(events) == 2
    assert Enum.all?(events, &(&1.payload["request_group_id"] == "data-operation-handoff-1"))

    assert Enum.all?(
             events,
             &(&1.payload["dashboard_context"]["dashboard_id"] == dashboard.dashboard_id)
           )

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "data-operation-handoff-1"}}"
             )
  end

  test "organization administrators complete a group through the dedicated management route" do
    {conn, user, organization, mission} = signed_in(:organization_admin)

    assert {:ok, [_event]} =
             Cadence.record_telemetry_historical_data_workflow_request(
               :backfill,
               %{
                 backfill_run_id: "managed-operation-1",
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "flight-telemetry",
                 binding_id: "flight-telemetry-binding",
                 actor_id: user.user_id,
                 actor_kind: "operator",
                 reason: "operator_requested_backfill"
               },
               ["HK.counter"]
             )

    {:ok, reader, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "managed-operation-1"}}"
      )

    reader_vue = data_operations_vue(reader)

    assert reader_vue.props["page"]["navigation"]["manage"]["id"] ==
             "data-operations-manage-link"

    refute Map.has_key?(reader_vue.props["selected_group"], "recovery")
    assert_json_safe(reader_vue)

    {:ok, manager, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "managed-operation-1"}}"
      )

    manager_vue = data_operations_vue(manager)

    assert manager_vue.props["page"]["navigation"]["reader"]["id"] ==
             "data-operations-reader-link"

    recovery = manager_vue.props["selected_group"]["recovery"]
    approved = action_by_id(recovery["transitions"], "data-operation-transition-approved")

    assert approved == %{
             "confirm" => "Record the approved transition for this request group?",
             "id" => "data-operation-transition-approved",
             "label" => "Approve (1)",
             "payload" => %{"group-id" => "managed-operation-1", "stage" => "approved"}
           }

    render_hook(manager, "transition_group", approved["payload"])

    approved_vue = data_operations_vue(manager)
    assert stream_row(approved_vue, "managed-operation-1")["state"] == "approved"

    started =
      approved_vue.props["selected_group"]["recovery"]["transitions"]
      |> action_by_id("data-operation-transition-started")

    assert started["payload"] == %{"group-id" => "managed-operation-1", "stage" => "started"}
    render_hook(manager, "transition_group", started["payload"])

    started_vue = data_operations_vue(manager)

    completed =
      started_vue.props["selected_group"]["recovery"]["transitions"]
      |> action_by_id("data-operation-transition-completed")

    assert completed["payload"] == %{
             "group-id" => "managed-operation-1",
             "stage" => "completed"
           }

    render_hook(manager, "transition_group", completed["payload"])

    completed_vue = data_operations_vue(manager)
    assert stream_row(completed_vue, "managed-operation-1")["state"] == "completed"

    assert Enum.map(completed_vue.props["selected_group"]["audit_events"], & &1["event_type"]) ==
             ~w(backfill_completed backfill_started backfill_approved backfill_requested)

    assert_json_safe(completed_vue)
    assert_sensitive_data_absent(completed_vue, user, organization)

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id,
        backfill_run_id: "managed-operation-1"
      )

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_completed
           ]
  end

  test "grouped imports retain their workflow identity and independent progress" do
    {conn, _user, organization, mission} = signed_in(:member)

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-operations")

    request_values =
      view
      |> data_operations_vue()
      |> then(
        &Map.merge(&1.props["request_form"]["values"], %{
          "workflow" => "import",
          "run_id" => "managed-import-1",
          "realm" => "backfill",
          "data_source_id" => "customer-archive",
          "source_binding_id" => "archive-import",
          "point_ids" => "HK.counter, HK.voltage",
          "source_from" => "2026-08-01T10:00:00Z",
          "source_to" => "2026-08-01T11:00:00Z",
          "reason" => "operator_requested_import",
          "confirmed" => "true"
        })
      )

    render_hook(view, "record_historical_workflow_request", %{
      "historical_workflow_request" => request_values
    })

    assert_patch(
      view,
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "managed-import-1"}}"
    )

    vue = data_operations_vue(view)
    import_row = stream_row(vue, "managed-import-1")

    assert import_row["state"] == "requested"
    assert import_row["workflow"] == "import"
    assert import_row["progress"] == "0/2 completed, 0 failed"
    assert vue.props["selected_group"]["workflow"] == "import"

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id
      )

    assert Enum.map(events, & &1.event_type) == [:import_requested, :import_requested]
  end

  test "failed groups expose retry and correction posture only on the management route" do
    {conn, user, organization, mission} = signed_in(:organization_admin)

    seed_failed_item!(
      organization,
      mission,
      user,
      "failed-group-1",
      "retryable",
      true,
      "retry_job"
    )

    correction_event =
      seed_failed_item!(
        organization,
        mission,
        user,
        "failed-group-1",
        "correction",
        false,
        "correct_workflow_request"
      )

    {:ok, reader, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "failed-group-1"}}"
      )

    reader_vue = data_operations_vue(reader)
    refute Map.has_key?(reader_vue.props["selected_group"], "recovery")

    event_count = lifecycle_event_count(organization, mission)

    render_hook(reader, "transition_group", %{
      "group-id" => "failed-group-1",
      "stage" => "completed"
    })

    render_hook(reader, "retry_group", %{"group-id" => "failed-group-1"})

    render_hook(reader, "request_correction", %{
      "group-id" => "failed-group-1",
      "event-id" => correction_event.backfill_lifecycle_event_id
    })

    assert lifecycle_event_count(organization, mission) == event_count

    {:ok, manager, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "failed-group-1"}}"
      )

    manager_vue = data_operations_vue(manager)
    selected_group = manager_vue.props["selected_group"]
    recovery = selected_group["recovery"]

    assert recovery["retry"] == %{
             "confirm" => "Retry every eligible failed job in this request group?",
             "id" => "data-operation-retry-group",
             "label" => "Retry eligible failures",
             "payload" => %{"group-id" => "failed-group-1"}
           }

    correction =
      recovery["failures"]
      |> Enum.find_value(& &1["correction"])

    assert correction == %{
             "confirm" => "Create a corrected request that supersedes this failed item?",
             "id" => "data-operation-correct-#{correction_event.backfill_lifecycle_event_id}",
             "label" => "Request correction",
             "payload" => %{
               "event-id" => correction_event.backfill_lifecycle_event_id,
               "group-id" => "failed-group-1"
             }
           }

    assert selected_group["audit_events"] != []
    assert_json_safe(manager_vue)
    assert_sensitive_data_absent(manager_vue, user, organization)
  end

  test "request validation resynchronizes canonical string values and rejects forged value types" do
    {conn, user, organization, mission} = signed_in(:member)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{time_mode: "replay", replay_run_id: "replay-7", data_view: "latest_revisions", limit_mode: "requested", point_id: "HK.counter"}}"
      )

    initial_vue = data_operations_vue(view)
    initial_values = initial_vue.props["request_form"]["values"]

    assert initial_values["workflow"] == "backfill"
    assert String.starts_with?(initial_values["run_id"], "telemetry_backfill_run_")
    assert initial_values["reason"] == "operator_requested_backfill"
    assert initial_values["dashboard_time_mode"] == "replay"
    assert initial_values["dashboard_replay_run_id"] == "replay-7"
    assert initial_values["dashboard_data_view"] == "latest_revisions"
    assert initial_values["dashboard_limit_mode"] == "requested"
    assert initial_values["point_ids"] == "HK.counter"
    assert Enum.all?(initial_values, fn {key, value} -> is_binary(key) and is_binary(value) end)

    validated_values =
      initial_values
      |> Map.put("run_id", "local-request-9")
      |> Map.put("confirmed", "false")

    render_hook(view, "validate_request", %{
      "historical_workflow_request" => validated_values
    })

    validated_vue = data_operations_vue(view)
    assert validated_vue.props["request_form"]["values"] == validated_values

    render_hook(view, "validate_request", %{
      "historical_workflow_request" => Map.put(validated_values, "confirmed", true)
    })

    invalid_vue = data_operations_vue(view)

    assert invalid_vue.props["request_form"]["error"] == %{
             "id" => "data-operation-request-error",
             "message" => "Historical request parameters are invalid."
           }

    patched_path =
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{realm: "archive", point_ids: "EPS.voltage, EPS.current"}}"

    render_patch(view, patched_path)
    patched_vue = data_operations_vue(view)

    assert patched_vue.props["request_form"]["values"]["realm"] == "archive"

    assert patched_vue.props["request_form"]["values"]["point_ids"] ==
             "EPS.voltage, EPS.current"

    assert_json_safe(patched_vue)
    assert_sensitive_data_absent(patched_vue, user, organization)
  end

  test "query-selected groups use one stable JSON-safe stream and canonical patch links" do
    {conn, user, organization, mission} = signed_in(:member)

    for group_id <- ~w(group-alpha group-bravo) do
      assert {:ok, [_event]} =
               Cadence.record_telemetry_historical_data_workflow_request(
                 :backfill,
                 %{
                   backfill_run_id: group_id,
                   organization_id: organization.organization_id,
                   mission_id: mission.mission_id,
                   realm: :flight,
                   data_source_id: "flight-telemetry",
                   binding_id: "flight-telemetry-binding",
                   actor_id: user.user_id,
                   actor_kind: "operator",
                   reason: "operator_requested_backfill"
                 },
                 ["HK.counter"]
               )
    end

    alpha_path =
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "group-alpha"}}"

    {:ok, view, _html} = live(conn, alpha_path)
    alpha_vue = data_operations_vue(view)

    assert alpha_vue.props["page"]["selected_group_id"] == "group-alpha"
    assert alpha_vue.props["selected_group"]["id"] == "group-alpha"

    assert Enum.sort(Enum.map(stream_rows(alpha_vue), & &1["__dom_id"])) ==
             ~w(data-operation-group-alpha data-operation-group-bravo)

    assert Enum.all?(stream_rows(alpha_vue), fn row ->
             row["href"] ==
               ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: row["id"]}}"
           end)

    bravo_path =
      ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "group-bravo"}}"

    render_patch(view, bravo_path)
    bravo_vue = data_operations_vue(view)

    assert bravo_vue.props["page"]["selected_group_id"] == "group-bravo"
    assert bravo_vue.props["selected_group"]["id"] == "group-bravo"
    assert_single_stream(bravo_vue)
    assert_json_safe(bravo_vue)
  end

  defp data_operations_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-data-operations-component")
  end

  defp stream_rows(vue) do
    vue.streams_diff
    |> Enum.flat_map(fn
      ["upsert", "/data_operation_groups/-", row] -> [row]
      _operation -> []
    end)
  end

  defp stream_row(vue, group_id) do
    Enum.find(stream_rows(vue), &(&1["id"] == group_id))
  end

  defp action_by_id(actions, id), do: Enum.find(actions, &(&1["id"] == id))

  defp assert_single_stream(vue) do
    assert Enum.all?(vue.streams_diff, fn
             [_operation, path | _rest] ->
               path == "/data_operation_groups" or
                 String.starts_with?(path, "/data_operation_groups/")

             _operation ->
               false
           end)
  end

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp assert_sensitive_data_absent(vue, user, organization) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    encoded = Jason.encode!(contract)
    keys = json_keys(contract)

    refute String.contains?(encoded, user.user_id)
    refute String.contains?(encoded, organization.organization_id)

    for forbidden <-
          ~w(current_scope current_user user socket form metadata credentials credential token secret) do
      refute forbidden in keys
    end
  end

  defp json_keys(map) when is_map(map) do
    Enum.flat_map(map, fn {key, value} -> [to_string(key) | json_keys(value)] end)
  end

  defp json_keys(list) when is_list(list), do: Enum.flat_map(list, &json_keys/1)
  defp json_keys(_value), do: []

  defp lifecycle_event_count(organization, mission) do
    mission.mission_id
    |> Cadence.list_telemetry_backfill_lifecycle_events(
      organization_id: organization.organization_id
    )
    |> length()
  end

  defp seed_failed_item!(organization, mission, user, group_id, suffix, retryable?, action) do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: "#{group_id}-#{suffix}",
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed-archive",
                 binding_id: "archive-binding",
                 observable_id: "HK.#{suffix}",
                 point_id: "HK.#{suffix}",
                 source_from: ~U[2026-08-01 10:00:00Z],
                 source_to: ~U[2026-08-01 11:00:00Z],
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: user.user_id,
                 actor_kind: "operator",
                 payload: %{
                   "request_group_id" => group_id,
                   "source" => %{
                     "failure" => %{
                       "code" => "source_window_unavailable",
                       "retryable" => retryable?,
                       "recovery_action" => action
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    event
  end
end
