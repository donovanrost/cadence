defmodule CadenceWeb.OpsAwarenessLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  test "read-only alarm filters link each condition to evidence and its definition" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:ok, _rows} =
             Store.persist_latest_states(Repo, [
               limit_event(mission, "red", :red, true, "EPS.voltage"),
               limit_event(mission, "green", :green, false, "EPS.current")
             ])

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/alarms")

    assert has_element?(view, "#ops-alarms-component.contents")
    assert has_element?(view, "#ops-context-rail")
    refute has_element?(view, "#ops-alarms-page")

    initial_vue = ops_alarms_vue(view)
    initial_observed = initial_vue.props["summary"]["observed"]
    red_row = alarm_row(mission, "red", "critical", "red", "EPS.voltage")

    assert initial_vue.component == "OpsAlarms"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false
    assert initial_vue.slots == %{}

    assert initial_vue.handlers == %{
             "filter" => Phoenix.LiveView.JS.push("filter"),
             "reset_filters" => Phoenix.LiveView.JS.push("reset_filters")
           }

    assert initial_vue.props == %{
             "page" => alarm_page_props(),
             "summary" => alarm_summary_props(initial_observed),
             "filters" => alarm_filter_props("active"),
             "reset" => alarm_reset_props(),
             "empty" => alarm_empty_props()
           }

    assert initial_observed =~
             ~r/^Projection observed \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$/

    assert alarm_upserts(initial_vue) == [red_row]
    refute Enum.any?(alarm_upserts(initial_vue), &(&1["limit_event_id"] == "green"))
    assert red_row["evidence"]["id"] == "alarm-open-sample-red"
    assert red_row["definition"]["id"] == "alarm-open-definition-red"
    assert_json_safe_alarm_vue(initial_vue)

    render_hook(view, "filter", %{
      "filters" => %{
        "severity" => "all",
        "state" => "nominal",
        "spacecraft_id" => "all",
        "query" => ""
      }
    })

    nominal_path = ~p"/missions/#{mission.mission_id}/ops/alarms?#{%{state: "nominal"}}"
    assert_patch(view, nominal_path)

    filter_event_vue = ops_alarms_vue(view)
    assert alarm_stream_mutations(filter_event_vue) == []

    render_patch(view, nominal_path)

    nominal_vue = ops_alarms_vue(view)
    nominal_observed = nominal_vue.props["summary"]["observed"]
    green_row = alarm_row(mission, "green", "nominal", "green", "EPS.current")

    assert nominal_vue.props == %{
             "page" => alarm_page_props(),
             "summary" => alarm_summary_props(nominal_observed),
             "filters" => alarm_filter_props("nominal"),
             "reset" => alarm_reset_props(),
             "empty" => alarm_empty_props()
           }

    assert alarm_stream_mutations(nominal_vue) == [
             ["replace", "/alarms", []],
             ["upsert", "/alarms/-", green_row]
           ]

    assert alarm_upserts(nominal_vue) == [green_row]
    refute Enum.any?(alarm_upserts(nominal_vue), &(&1["limit_event_id"] == "red"))
    assert_json_safe_alarm_vue(nominal_vue)

    render_hook(view, "reset_filters", %{})

    reset_path = ~p"/missions/#{mission.mission_id}/ops/alarms"
    assert_patch(view, reset_path)

    reset_event_vue = ops_alarms_vue(view)
    assert alarm_stream_mutations(reset_event_vue) == []

    render_patch(view, reset_path)

    reset_vue = ops_alarms_vue(view)
    reset_observed = reset_vue.props["summary"]["observed"]

    assert reset_vue.props == %{
             "page" => alarm_page_props(),
             "summary" => alarm_summary_props(reset_observed),
             "filters" => alarm_filter_props("active"),
             "reset" => alarm_reset_props(),
             "empty" => alarm_empty_props()
           }

    assert alarm_stream_mutations(reset_vue) == [
             ["replace", "/alarms", []],
             ["upsert", "/alarms/-", red_row]
           ]

    assert_json_safe_alarm_vue(reset_vue)
  end

  defp ops_alarms_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-alarms-component")
  end

  defp alarm_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/alarms/" <> _index, _alarm] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, alarm] -> alarm end)
  end

  defp alarm_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_alarm_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp alarm_page_props do
    %{
      "id" => "ops-alarms-page",
      "header" => %{
        "eyebrow" => "Mission operations / live conditions",
        "heading" => "Alarms",
        "copy" =>
          "The latest evaluated limit state for every mission point. This surface is read-only; definitions and lifecycle changes remain in the Limits application."
      },
      "conditions_id" => "alarm-conditions"
    }
  end

  defp alarm_summary_props(observed) do
    %{
      "id" => "alarm-summary",
      "active_count" => 1,
      "observed" => observed,
      "badges" => [
        %{"severity" => "critical", "count" => 1, "label" => "Critical"},
        %{"severity" => "warning", "count" => 0, "label" => "Warning"},
        %{"severity" => "info", "count" => 0, "label" => "Info"}
      ]
    }
  end

  defp alarm_filter_props(state) do
    %{
      "id" => "alarm-filter-form",
      "values" => %{
        "severity" => "all",
        "state" => state,
        "spacecraft_id" => "all",
        "query" => ""
      },
      "fields" => %{
        "severity" => %{
          "id" => "filters_severity",
          "name" => "filters[severity]",
          "type" => "select",
          "label" => "Severity",
          "options" => [
            %{"label" => "All", "value" => "all"},
            %{"label" => "Critical", "value" => "critical"},
            %{"label" => "Warning", "value" => "warning"},
            %{"label" => "Info", "value" => "info"},
            %{"label" => "Nominal", "value" => "nominal"}
          ]
        },
        "state" => %{
          "id" => "filters_state",
          "name" => "filters[state]",
          "type" => "select",
          "label" => "State",
          "options" => [
            %{"label" => "Active conditions", "value" => "active"},
            %{"label" => "All states", "value" => "all"},
            %{"label" => "Nominal only", "value" => "nominal"}
          ]
        },
        "spacecraft_id" => %{
          "id" => "filters_spacecraft_id",
          "name" => "filters[spacecraft_id]",
          "type" => "select",
          "label" => "Spacecraft",
          "options" => [%{"label" => "All spacecraft", "value" => "all"}]
        },
        "query" => %{
          "id" => "filters_query",
          "name" => "filters[query]",
          "type" => "search",
          "label" => "Subsystem or point",
          "placeholder" => "EPS, voltage, HK.temp",
          "debounce_ms" => 250
        }
      }
    }
  end

  defp alarm_reset_props do
    %{"id" => "alarm-filter-reset", "label" => "Reset filters"}
  end

  defp alarm_empty_props do
    %{
      "id" => "alarm-conditions-empty",
      "icon" => "hero-check-circle",
      "heading" => "No matching conditions",
      "copy" => "The current projection is available; no rows match this filter."
    }
  end

  defp alarm_row(mission, id, severity, limit_state, point_id) do
    receipt_time = ~U[2026-08-01 12:00:00Z]

    %{
      "id" => id,
      "__dom_id" => "alarm-condition-#{id}",
      "limit_event_id" => id,
      "severity" => severity,
      "limit_state" => limit_state,
      "state_label" => limit_state,
      "point_name" => point_id,
      "context" => "Mission · EPS · #{point_id}",
      "value" => %{"label" => "Value", "display" => "42"},
      "observed" => %{"label" => "Observed", "display" => "2026-08-01 12:00:00 UTC"},
      "evidence" => %{
        "id" => "alarm-open-sample-#{id}",
        "href" =>
          ~p"/missions/#{mission.mission_id}/ops/explore?#{%{point_id: point_id, spacecraft_id: nil, sample_id: "sample-#{id}", selected_time: DateTime.to_iso8601(receipt_time)}}",
        "title" => "Open exact sample and evidence",
        "icon" => "hero-magnifying-glass",
        "label" => "Evidence"
      },
      "definition" => %{
        "id" => "alarm-open-definition-#{id}",
        "href" =>
          ~p"/missions/#{mission.mission_id}/applications/limits/activity?#{%{limit_definition_id: "definition-#{id}", limit_definition_version: 1, point_id: point_id}}",
        "title" => "Open limit definition and activation history",
        "icon" => "hero-document-magnifying-glass",
        "label" => "Definition"
      }
    }
  end

  test "a followed command is URL-scoped and remains visible on another Ops page" do
    {conn, org, mission} = signed_in_org_and_mission()
    persist_command_request!(org, mission, "command-1")

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands")

    assert has_element?(view, "#ops-commands-page")
    assert has_element?(view, ~s([data-command-request="command-1"]))
    refute has_element?(view, ~s(button[phx-click="release_command"]))

    view
    |> element("#follow-command-command-1")
    |> render_click()

    assert has_element?(view, ~s(#followed-command-banner[data-followed-command="command-1"]))

    assert has_element?(
             view,
             ~s(#ops-context-rail [data-ops-context-followed-command="command-1"])
           )

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href*="/ops/planning"][href*="focus_command_id=command-1"])
           )

    {:ok, planning_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning?#{%{focus_command_id: "command-1"}}"
      )

    assert has_element?(
             planning_view,
             ~s(#ops-context-rail [data-ops-context-followed-command="command-1"])
           )

    assert has_element?(
             planning_view,
             ~s(#ops-nav-rail a[href*="/ops/commands"][href*="focus_command_id=command-1"])
           )
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp limit_event(mission, id, normalized_state, violation, point_id) do
    %Event{
      limit_event_id: id,
      mission_id: mission.mission_id,
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-#{id}",
      limit_definition_id: "definition-#{id}",
      limit_definition_version: 1,
      limit_set_name: "DEFAULT",
      evaluated_value: 42,
      limit_state: normalized_state,
      normalized_state: normalized_state,
      violation: violation,
      receipt_time: ~U[2026-08-01 12:00:00Z],
      provenance: %{}
    }
  end

  defp persist_command_request!(org, mission, command_request_id) do
    request = %CommandRequest{
      command_request_id: command_request_id,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      source_endpoint_ref: "uplink-primary",
      mission_model_revision_id: "mission-model-1",
      command_id: "NOOP",
      command_name: "NOOP",
      command_display_name: "No operation",
      lifecycle_state: :approved,
      requested_by: %{display_name: "Flight Director"},
      requested_at: ~U[2026-08-01 12:00:00Z]
    }

    request
    |> CommandRequestRow.changeset()
    |> Repo.insert!()
  end
end
