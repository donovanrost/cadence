defmodule CadenceWeb.OpsAwarenessLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsNavTestSupport
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
    assert has_element?(view, "#ops-context-rail-component")
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
    receipt_time = %{~U[2026-08-01 12:00:00Z] | microsecond: {0, 6}}

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
    persist_command_evidence!(org, mission, "command-1")

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands")

    assert has_element?(view, "#ops-commands-component.contents")
    assert has_element?(view, "#ops-context-rail-component")
    refute has_element?(view, "#ops-commands-page")

    initial_vue = ops_commands_vue(view)
    initial_observed = initial_vue.props["summary"]["observed"]
    [initial_row] = command_upserts(initial_vue)
    age_display = initial_row["age"]["display"]
    unfocused_row = command_row(age_display, false)

    assert initial_vue.component == "OpsCommands"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false
    assert initial_vue.slots == %{}

    assert initial_vue.handlers == %{
             "clear_command_focus" => Phoenix.LiveView.JS.push("clear_command_focus"),
             "filter" => Phoenix.LiveView.JS.push("filter"),
             "follow_command" => Phoenix.LiveView.JS.push("follow_command"),
             "reset_filters" => Phoenix.LiveView.JS.push("reset_filters")
           }

    assert initial_vue.props == command_props(initial_observed, default_command_filters(), nil)

    assert initial_observed =~
             ~r/^Projection observed \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$/

    assert age_display =~ ~r/^\d+[smhd]$/
    assert initial_row == unfocused_row

    initial_stream_mutations = command_stream_mutations(initial_vue)
    assert ["replace", "/commands", []] in initial_stream_mutations
    assert ["upsert", "/commands/-", unfocused_row] in initial_stream_mutations

    assert initial_row["evidence"]["queue_entry"]["record_id"] == "queue-command-1"

    assert initial_row["evidence"]["release_attempt"]["record_id"] ==
             "release-command-1"

    assert initial_row["evidence"]["verification"]["state"] == "pending"

    assert initial_row["focus"]["action"] == %{
             "id" => "follow-command-command-1",
             "icon" => "hero-eye",
             "label" => "Follow",
             "payload" => %{"command-request-id" => "command-1"}
           }

    refute Map.has_key?(initial_vue.handlers, "release_command")
    refute Map.has_key?(initial_row["focus"], "release")
    assert_json_safe_command_vue(initial_vue)

    filtered_values = %{
      "status" => "in_flight",
      "target" => "uplink-primary",
      "query" => "operation"
    }

    render_hook(view, "filter", %{"filters" => filtered_values})

    filtered_path =
      ~p"/missions/#{mission.mission_id}/ops/commands?#{filtered_values}"

    assert_patch(view, filtered_path)

    filtered_vue = ops_commands_vue(view)
    filtered_observed = filtered_vue.props["summary"]["observed"]
    [filtered_row] = command_upserts(filtered_vue)

    assert filtered_vue.props == command_props(filtered_observed, filtered_values, nil)
    assert filtered_row == command_row(filtered_row["age"]["display"], false)

    assert command_stream_mutations(filtered_vue) == [
             ["replace", "/commands", []],
             ["upsert", "/commands/-", filtered_row]
           ]

    assert_json_safe_command_vue(filtered_vue)

    render_hook(view, "follow_command", %{"command-request-id" => "command-1"})

    focused_path =
      ~p"/missions/#{mission.mission_id}/ops/commands?#{Map.put(filtered_values, "focus_command_id", "command-1")}"

    assert_patch(view, focused_path)

    focused_vue = ops_commands_vue(view)
    focused_observed = focused_vue.props["summary"]["observed"]
    [focused_row] = command_upserts(focused_vue)

    assert focused_vue.props ==
             command_props(focused_observed, filtered_values, "command-1")

    assert focused_row == command_row(focused_row["age"]["display"], true)

    assert command_stream_mutations(focused_vue) == [
             ["replace", "/commands", []],
             ["upsert", "/commands/-", focused_row]
           ]

    assert_json_safe_command_vue(focused_vue)

    assert ops_context_followed_command(view)["command_request_id"] == "command-1"

    assert ops_nav_item(ops_nav_vue(view), "planning")["href"] ==
             "/missions/#{mission.mission_id}/ops/planning?focus_command_id=command-1"

    {:ok, planning_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning?#{%{focus_command_id: "command-1"}}"
      )

    assert ops_context_followed_command(planning_view)["command_request_id"] == "command-1"

    assert ops_nav_item(ops_nav_vue(planning_view), "commands")["href"] ==
             "/missions/#{mission.mission_id}/ops/commands?focus_command_id=command-1"

    render_hook(view, "clear_command_focus", %{})
    assert_patch(view, filtered_path)

    cleared_vue = ops_commands_vue(view)
    cleared_observed = cleared_vue.props["summary"]["observed"]
    [cleared_row] = command_upserts(cleared_vue)

    assert cleared_vue.props == command_props(cleared_observed, filtered_values, nil)
    assert cleared_row == command_row(cleared_row["age"]["display"], false)
    assert_json_safe_command_vue(cleared_vue)

    render_hook(view, "follow_command", %{"command-request-id" => "command-1"})
    assert_patch(view, focused_path)

    render_hook(view, "reset_filters", %{})

    reset_path =
      ~p"/missions/#{mission.mission_id}/ops/commands?#{%{focus_command_id: "command-1"}}"

    assert_patch(view, reset_path)

    reset_vue = ops_commands_vue(view)
    reset_observed = reset_vue.props["summary"]["observed"]
    [reset_row] = command_upserts(reset_vue)

    assert reset_vue.props ==
             command_props(reset_observed, default_command_filters(), "command-1")

    assert reset_row == command_row(reset_row["age"]["display"], true)

    assert command_stream_mutations(reset_vue) == [
             ["replace", "/commands", []],
             ["upsert", "/commands/-", reset_row]
           ]

    assert_json_safe_command_vue(reset_vue)
  end

  defp ops_commands_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-commands-component")
  end

  defp ops_context_followed_command(view) do
    view
    |> LiveVue.Test.get_vue(id: "ops-context-rail-component")
    |> Map.fetch!(:props)
    |> Map.fetch!("sections")
    |> Enum.find(&(&1["key"] == "commands"))
    |> get_in(["content", "followed_command"])
  end

  defp command_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/commands/" <> _index, _command] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, command] -> command end)
  end

  defp command_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_command_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp command_props(observed, filter_values, focus_command_id) do
    %{
      "page" => command_page_props(),
      "summary" => command_summary_props(observed),
      "filters" => command_filter_props(filter_values),
      "reset" => %{
        "id" => "command-filter-reset",
        "label" => "Reset filters",
        "payload" => %{}
      },
      "focus_banner" => command_focus_banner_props(focus_command_id),
      "empty" => %{
        "id" => "command-rows-empty",
        "icon" => "hero-command-line",
        "heading" => "No matching commands",
        "copy" => "Empty and unavailable projections are reported separately by the context rail."
      }
    }
  end

  defp command_page_props do
    %{
      "id" => "ops-commands-page",
      "header" => %{
        "eyebrow" => "Mission operations / command posture",
        "heading" => "Commands",
        "copy" =>
          "Read-only request, queue, release, transport, and verification state. Command creation, approval, and release remain outside this operator-readable surface."
      },
      "rows_id" => "command-rows"
    }
  end

  defp command_summary_props(observed) do
    %{
      "id" => "command-summary",
      "active_count" => 1,
      "observed" => observed,
      "metrics" => [
        %{"label" => "Queued", "value" => 0, "value_class" => "text-base-content/35"},
        %{
          "label" => "Release pending",
          "value" => 0,
          "value_class" => "text-base-content/35"
        },
        %{"label" => "In flight", "value" => 1, "value_class" => "text-info"},
        %{"label" => "Failed", "value" => 0, "value_class" => "text-base-content/35"}
      ]
    }
  end

  defp command_filter_props(values) do
    %{
      "id" => "command-filter-form",
      "values" => values,
      "fields" => %{
        "status" => %{
          "id" => "filters_status",
          "name" => "filters[status]",
          "type" => "select",
          "label" => "State",
          "options" => [
            %{"label" => "All states", "value" => "all"},
            %{"label" => "Failed", "value" => "failed"},
            %{"label" => "Release pending", "value" => "release_pending"},
            %{"label" => "In flight", "value" => "in_flight"},
            %{"label" => "Queued", "value" => "queued"},
            %{"label" => "Released", "value" => "released"},
            %{"label" => "Approval pending", "value" => "approval_pending"}
          ]
        },
        "target" => %{
          "id" => "filters_target",
          "name" => "filters[target]",
          "type" => "select",
          "label" => "Target",
          "options" => [
            %{"label" => "All targets", "value" => "all"},
            %{"label" => "uplink-primary", "value" => "uplink-primary"}
          ]
        },
        "query" => %{
          "id" => "filters_query",
          "name" => "filters[query]",
          "type" => "search",
          "label" => "Command or requester",
          "placeholder" => "NOOP, request id, endpoint",
          "debounce_ms" => 250
        }
      }
    }
  end

  defp default_command_filters do
    %{"status" => "all", "target" => "all", "query" => ""}
  end

  defp command_focus_banner_props(nil), do: nil

  defp command_focus_banner_props(command_request_id) do
    %{
      "id" => "followed-command-banner",
      "command_request_id" => command_request_id,
      "icon" => "hero-eye",
      "prefix" => "Following",
      "suffix" => "across Ops pages",
      "clear" => %{
        "id" => "clear-command-focus",
        "label" => "Stop following",
        "payload" => %{}
      }
    }
  end

  defp command_row(age_display, following) do
    %{
      "id" => "command-1",
      "__dom_id" => "command-row-command-1",
      "command_request_id" => "command-1",
      "command_name" => "No operation",
      "status" => %{
        "value" => "in_flight",
        "label" => "in flight",
        "class" => "badge badge-info badge-sm"
      },
      "target" => %{"label" => "Target", "display" => "uplink-primary"},
      "requester" => %{"label" => "Requested by", "display" => "Flight Director"},
      "age" => %{"label" => "Age", "display" => age_display},
      "focus" => %{
        "following" => following,
        "label" => "Following",
        "class" => "badge badge-info badge-outline badge-sm",
        "action" => %{
          "id" => "follow-command-command-1",
          "label" => "Follow",
          "icon" => "hero-eye",
          "payload" => %{"command-request-id" => "command-1"}
        }
      },
      "evidence" => %{
        "summary" => "Queue, release, and verifier evidence",
        "request_state" => %{"label" => "Request state", "display" => "approved"},
        "queue_entry" => %{
          "label" => "Queue entry",
          "record_id" => "queue-command-1",
          "display" => "queue-command-1"
        },
        "release_attempt" => %{
          "label" => "Release attempt",
          "record_id" => "release-command-1",
          "display" => "release-command-1"
        },
        "verification" => %{
          "label" => "Verification",
          "state" => "pending",
          "display" => "pending"
        }
      }
    }
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

  defp persist_command_evidence!(org, mission, command_request_id) do
    queue_entry = %Cadence.Commanding.CommandQueueEntry{
      command_queue_entry_id: "queue-#{command_request_id}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      command_request_id: command_request_id,
      source_endpoint_ref: "uplink-primary",
      queue_lane_key: "uplink-primary",
      queue_sequence: 1,
      lifecycle_state: :released,
      enqueued_at: ~U[2026-08-01 12:01:00Z]
    }

    queue_entry
    |> Cadence.Commanding.CommandQueueEntryRow.changeset()
    |> Repo.insert!()

    release_attempt = %Cadence.Commanding.CommandReleaseAttempt{
      command_release_attempt_id: "release-#{command_request_id}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      command_queue_entry_id: queue_entry.command_queue_entry_id,
      command_request_id: command_request_id,
      source_endpoint_ref: "uplink-primary",
      realized_contact_id: "contact-1",
      mission_model_revision_id: "mission-model-1",
      command_id: "NOOP",
      command_name: "NOOP",
      lifecycle_state: :released,
      verification_state: :pending,
      attempted_at: ~U[2026-08-01 12:02:00Z],
      released_at: ~U[2026-08-01 12:03:00Z]
    }

    release_attempt
    |> Cadence.Commanding.CommandReleaseAttemptRow.changeset()
    |> Repo.insert!()
  end
end
