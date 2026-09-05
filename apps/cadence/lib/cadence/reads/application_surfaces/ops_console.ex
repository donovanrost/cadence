defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole do
  @moduledoc "Phoenix-owned query provider for every route-level Ops surface."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, JSONBoundary, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole, as: OpsDefinition
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.Alarms
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation
  alias Cadence.Reads.Commands
  alias Cadence.Reads.MissionTimeline

  @application_key "ops_console"
  @application_version 1
  @surface_version 1
  @subject_param_keys %{
    "contact_requirement_show" => "contact_requirement_id",
    "contact_plan_show" => "contact_plan_id",
    "contact_detail" => "provider_reservation_id",
    "contact_record" => "contact_id",
    "dashboard_settings" => "dashboard_id",
    "dashboard_show" => "dashboard_id",
    "dashboard_editor" => "dashboard_id",
    "dashboard_activity" => "dashboard_id",
    "dashboard_share" => "share_id",
    "dashboard_snapshot" => "snapshot_id",
    "dashboard_diagnostics" => "dashboard_id",
    "dashboard_playlist_present" => "playlist_id",
    "fleet_planning_run" => "fleet_planning_run_id"
  }

  @impl true
  def application_key, do: @application_key

  @impl true
  def load(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: @application_key,
          application_version: @application_version,
          surface_id: surface_id,
          surface_version: @surface_version,
          query_id: query_id,
          query_version: 1,
          params: params
        }
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(surface_id) and is_map(params) do
    with {:ok, spec} <- spec(surface_id),
         true <- query_id == Map.get(spec, :query_id, "cadence.ops.#{surface_id}"),
         :ok <- validate_params(spec, params),
         :ok <- validate_mission_param(mission_id, params),
         :ok <- validate_scope_mission(scope, mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Cadence.Missions.fetch_mission(organization_id, mission_id),
         :ok <- validate_subject(spec.id, organization_id, mission_id, params),
         payload = dispatch(spec.id, scope, mission, params),
         {:ok, safe_payload} <- JSONBoundary.safe(payload) do
      {:ok, safe_payload}
    else
      false -> {:error, :unsupported_application_surface_query}
      {:error, :mission_not_found} -> {:error, :unsupported_application_surface_query}
      {:error, _reason} -> {:error, :unsupported_application_surface_query}
    end
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp spec(surface_id) do
    case Enum.find(OpsDefinition.surface_specs(), &(&1.id == surface_id)) do
      %{id: _id} = spec -> {:ok, spec}
      nil -> {:error, :unsupported_application_surface_query}
    end
  end

  defp validate_params(spec, params) do
    allowed =
      MapSet.new([
        "mission_id",
        "dashboard_id",
        "version",
        "panel",
        "activity_filter",
        "activity_event",
        "selected_publish_issue",
        "share_id",
        "snapshot_id",
        "playlist_id",
        "contact_requirement_id",
        "contact_plan_id",
        "provider_reservation_id",
        "contact_id",
        "fleet_planning_run_id",
        "data_source_id",
        "source_binding_id",
        "point_id",
        "spacecraft_id",
        "query",
        "severity",
        "state",
        "category",
        "kind",
        "from",
        "to",
        "limit",
        "index",
        "status",
        "target",
        "selected_time",
        "time_mode",
        "realm",
        "logical_source",
        "scope_id",
        "scope_kind",
        "sample_id",
        "replay_run_id",
        "selection_view",
        "time_axis",
        "validity_state",
        "question",
        "order",
        "limit_mode",
        "group"
      ])

    with true <- Enum.all?(Map.keys(params), &is_binary/1),
         true <- Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)),
         :ok <- JSONBoundary.validate(params),
         :ok <- validate_subject_param(spec.id, params) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_subject_param(surface_id, params) do
    key = Map.get(@subject_param_keys, surface_id)

    if is_nil(key) or valid_text?(Map.get(params, key)),
      do: :ok,
      else: {:error, :subject_required}
  end

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp validate_scope_mission(%Scope{mission_id: nil}, _mission_id), do: :ok
  defp validate_scope_mission(%Scope{mission_id: mission_id}, mission_id), do: :ok
  defp validate_scope_mission(%Scope{}, _mission_id), do: {:error, :scope_mismatch}

  defp validate_subject("contact_requirement_show", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.ContactPlanning.ContactRequirements, :fetch, [
        organization_id,
        mission_id,
        params["contact_requirement_id"]
      ])

  defp validate_subject("contact_plan_show", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Management.Contacts, :fetch_plan, [
        organization_id,
        mission_id,
        params["contact_plan_id"]
      ])

  defp validate_subject("contact_detail", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Contacts.ProviderReservations, :fetch, [
        organization_id,
        mission_id,
        params["provider_reservation_id"]
      ])

  defp validate_subject("contact_record", organization_id, mission_id, params) do
    contact_id = params["contact_id"]

    case {Cadence.Contacts.fetch_scheduled_contact(organization_id, mission_id, contact_id),
          Cadence.Contacts.fetch_realized_contact(organization_id, mission_id, contact_id)} do
      {{:ok, _contact}, _other} -> :ok
      {_other, {:ok, _contact}} -> :ok
      _missing -> {:error, :subject_not_found}
    end
  end

  defp validate_subject(surface_id, organization_id, mission_id, params)
       when surface_id in [
              "dashboard_settings",
              "dashboard_diagnostics",
              "dashboard_show",
              "dashboard_editor",
              "dashboard_activity"
            ] do
    fetch_subject(Cadence.Dashboards, :fetch_document, [
      organization_id,
      mission_id,
      params["dashboard_id"]
    ])
  end

  defp validate_subject("dashboard_share", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Dashboards.Management, :fetch_active_share, [
        organization_id,
        mission_id,
        params["share_id"]
      ])

  defp validate_subject("dashboard_snapshot", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Dashboards.Management, :fetch_snapshot, [
        organization_id,
        mission_id,
        params["snapshot_id"]
      ])

  defp validate_subject("dashboard_playlist_present", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Dashboards.Management, :fetch_playlist, [
        organization_id,
        mission_id,
        params["playlist_id"]
      ])

  defp validate_subject("fleet_planning_run", organization_id, mission_id, params),
    do:
      fetch_subject(Cadence.Management.Contacts.PlanningResults, :fetch_run, [
        organization_id,
        mission_id,
        params["fleet_planning_run_id"]
      ])

  defp validate_subject(surface_id, organization_id, mission_id, params)
       when surface_id in ["data_sources", "data_source_settings"] do
    case params["data_source_id"] do
      nil ->
        :ok

      source_id ->
        fetch_scoped_subject(
          Cadence.Reads.DataSources,
          :fetch_data_source,
          [source_id],
          organization_id,
          mission_id
        )
    end
  end

  defp validate_subject(_surface_id, _organization_id, _mission_id, _params), do: :ok

  defp fetch_subject(module, function, arguments) do
    case apply(module, function, arguments) do
      {:ok, _subject} -> :ok
      _missing -> {:error, :subject_not_found}
    end
  rescue
    _exception -> {:error, :subject_not_found}
  end

  defp fetch_scoped_subject(module, function, arguments, organization_id, mission_id) do
    case apply(module, function, arguments) do
      {:ok, subject} -> scope_subject(subject, organization_id, mission_id)
      _missing -> {:error, :subject_not_found}
    end
  rescue
    _exception -> {:error, :subject_not_found}
  end

  defp scope_subject(subject, organization_id, mission_id) do
    if Map.get(subject, :organization_id) in [nil, organization_id] and
         Map.get(subject, :mission_id) in [nil, mission_id],
       do: :ok,
       else: {:error, :subject_not_found}
  end

  defp dispatch("workspace", _scope, mission, _params), do: landing(mission, "Ops Console")
  defp dispatch("alarms", scope, mission, params), do: alarms(scope, mission, params)
  defp dispatch("timeline", scope, mission, params), do: timeline(scope, mission, params)
  defp dispatch("commands", scope, mission, params), do: commands(scope, mission, params)

  defp dispatch("dashboard_directory", scope, mission, params),
    do: dashboard_directory(scope, mission, params)

  defp dispatch("dashboard_show", scope, mission, params),
    do: envelope("OpsDashboardShow", Presentation.dashboard(scope, mission, params, :view))

  defp dispatch("dashboard_editor", scope, mission, params),
    do: envelope("OpsDashboardShow", Presentation.dashboard(scope, mission, params, :edit))

  defp dispatch("dashboard_activity", scope, mission, params),
    do:
      envelope(
        "OpsDashboardActivitySurface",
        Presentation.dashboard_activity(scope, mission, params)
      )

  defp dispatch("data_sources", scope, mission, params),
    do: envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :reader))

  defp dispatch("data_source_registration", scope, mission, params),
    do:
      envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :registration))

  defp dispatch("data_source_settings", scope, mission, params),
    do: envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :settings))

  defp dispatch("data_operations", scope, mission, params),
    do:
      envelope("OpsDataOperations", Presentation.data_operations(scope, mission, params, :reader))

  defp dispatch("data_operations_manage", scope, mission, params),
    do:
      envelope("OpsDataOperations", Presentation.data_operations(scope, mission, params, :manage))

  defp dispatch(surface_id, _scope, mission, params), do: generic(surface_id, mission, params)

  defp landing(mission, title) do
    envelope("OpsConsoleLanding", %{
      "missionId" => mission.mission_id,
      "missionName" => mission.display_name,
      "componentCount" => 90,
      "title" => title
    })
  end

  defp envelope(component, props),
    do: %{
      "navigation" => %{},
      "data" => %{
        "queryVersion" => 1,
        "presentation" => %{"component" => component, "props" => props}
      }
    }

  defp generic(surface_id, mission, params) do
    id = "ops-#{surface_id}-page"
    page = page(id, title(surface_id), mission, params)

    props = generic_props(surface_id, page, params)

    envelope(component_name(surface_id), props)
  end

  defp generic_props("contact_requirement_list", page, _params),
    do: %{"page" => page, "requirements" => []}

  defp generic_props("contact_requirement_new", page, _params),
    do: %{
      "page" => page,
      "journey" => journey(),
      "form" =>
        form("contact-requirement-form", "Declare requirement", [
          "spacecraft_id",
          "contact_intent",
          "earliest_start",
          "latest_end",
          "success_measure",
          "minimum_duration_seconds",
          "preferred_duration_seconds",
          "minimum_separation_seconds",
          "minimum_data_volume_bytes",
          "contact_count",
          "priority",
          "rationale",
          "allowed_providers",
          "excluded_providers",
          "allowed_stations",
          "excluded_stations"
        ]),
      "actions" => form_actions()
    }

  defp generic_props("contact_requirement_show", page, _params),
    do: %{
      "page" => page,
      "requirement_versions" => [],
      "planning_searches" => [],
      "opportunities" => []
    }

  defp generic_props("contact_requirement_template", page, _params),
    do: requirement_template_props(page)

  defp generic_props("contact_schedule", page, _params), do: schedule_props(page)
  defp generic_props("contact_plan_show", page, _params), do: plan_props(page)

  defp generic_props("contact_detail", page, _params),
    do: %{"page" => page, "provider_changes" => [], "provider_audit_entries" => []}

  defp generic_props("contact_record", page, params),
    do: %{"record" => record_props(page, params["contact_id"])}

  defp generic_props("dashboard_directory", page, _params),
    do: %{
      "page" => page,
      "filters" => filters("dashboard-directory-filters", ["query", "status"]),
      "dashboard_directory" => []
    }

  defp generic_props("dashboard_new", page, _params),
    do: %{"page" => page, "form" => dashboard_form()}

  defp generic_props("dashboard_library", page, _params), do: library_props(page)

  defp generic_props("dashboard_playlists", page, _params),
    do: %{
      "page" => page,
      "form" => playlist_form(),
      "options" => [],
      "dashboard_playlists" => []
    }

  defp generic_props("dashboard_playlist_present", page, _params),
    do: %{
      "page" => Map.put(page, "wallboard_mode", true),
      "current_dashboard" => current_dashboard()
    }

  defp generic_props("dashboard_settings", page, _params), do: settings_props(page)

  defp generic_props("dashboard_share", page, params),
    do: %{"share" => share_props(page, params["share_id"])}

  defp generic_props("dashboard_snapshot", page, params),
    do: %{"snapshot" => snapshot_props(page, params["snapshot_id"])}

  defp generic_props("dashboard_diagnostics", page, _params),
    do: %{"presentation" => diagnostics_presentation(page), "diagnostic_rows" => []}

  defp generic_props("fleet_planning", page, _params), do: planning_props(page)
  defp generic_props("fleet_planning_new", page, _params), do: fleet_new_props(page)
  defp generic_props("fleet_planning_policy", page, _params), do: fleet_policy_props(page)

  defp generic_props("fleet_planning_run", page, params),
    do: fleet_run_props(page, params["fleet_planning_run_id"])

  defp generic_props("activation_requests", page, _params), do: activation_props(page)
  defp generic_props("telemetry_explore", page, params), do: telemetry_props(page, params)
  defp generic_props("data_operations", page, _params), do: data_operations_props(page)

  defp alarms(scope, mission, params) do
    snapshot =
      Alarms.snapshot(scope.organization_id, mission.mission_id, filters: params)

    rows = Enum.map(snapshot.rows, &alarm_row/1)

    envelope("OpsAlarms", %{
      "page" => page("ops-alarms-page", "Alarms", mission, params),
      "summary" => %{
        "id" => "alarm-summary",
        "active_count" => snapshot.summary.active_count,
        "observed" => iso(snapshot.observed_at),
        "badges" => []
      },
      "filters" => filters("alarm-filters", ["severity", "state", "spacecraft_id", "query"]),
      "reset" => %{"id" => "reset-alarm-filters", "label" => "Reset filters", "payload" => %{}},
      "empty" => %{
        "id" => "alarms-empty",
        "heading" => "No alarm conditions",
        "copy" => "No conditions match the mission-scoped filters.",
        "icon" => "hero-check-circle"
      },
      "alarms" => rows
    })
  end

  defp timeline(scope, mission, params) do
    events =
      MissionTimeline.list_for_mission(scope.organization_id, mission.mission_id, limit: 100)

    envelope("OpsTimeline", %{
      "presentation" => timeline_presentation(mission, params),
      "timeline_events" => Enum.map(events, &timeline_event/1)
    })
  end

  defp commands(scope, mission, params) do
    snapshot =
      Commands.snapshot(scope.organization_id, mission.mission_id, filters: params)

    envelope("OpsCommands", %{
      "page" => page("ops-commands-page", "Commands", mission, params),
      "summary" => %{
        "id" => "command-summary",
        "active_count" => length(snapshot.rows),
        "observed" => iso(snapshot.observed_at),
        "metrics" => []
      },
      "filters" => filters("command-filters", ["status", "target", "query"]),
      "reset" => %{"id" => "reset-command-filters", "label" => "Reset filters", "payload" => %{}},
      "focus_banner" => nil,
      "empty" => %{
        "id" => "commands-empty",
        "heading" => "No commands",
        "copy" => "No command requests match the mission-scoped filters.",
        "icon" => "hero-command-line"
      },
      "commands" => Enum.map(snapshot.rows, &command_row/1)
    })
  end

  defp dashboard_directory(scope, mission, _params) do
    dashboard_author? =
      Policy.authorize(scope, :author_dashboards, %{
        organization_id: scope.organization_id,
        mission_id: mission.mission_id
      }) == :ok

    rows =
      scope.organization_id
      |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
      |> Enum.map(&dashboard_row(&1, mission.mission_id, dashboard_author?))

    tags = rows |> Enum.flat_map(& &1["tags"]) |> Enum.uniq() |> Enum.sort()

    envelope("OpsDashboardDirectory", %{
      "page" => directory_page_dto(mission.mission_id, dashboard_author?, length(rows)),
      "filters" => directory_filters_dto(tags),
      "dashboard_directory" => rows
    })
  end

  defp directory_page_dto(mission_id, dashboard_author?, count) do
    %{
      "id" => "ops-dashboards-page",
      "header" => %{
        "eyebrow" => "Observe / Dashboards",
        "heading" => "Dashboard Directory",
        "copy" =>
          "Find mission telemetry workspaces without crowding the navigation rail. Stars and recents are personal; dashboard definitions and tags remain mission shared.",
        "count" => %{
          "id" => "dashboard-directory-count",
          "value" => count,
          "suffix" => "matching"
        },
        "author_actions" => dashboard_author_actions_dto(mission_id, dashboard_author?)
      },
      "list" => %{
        "id" => "dashboard-directory-list",
        "empty" => %{
          "id" => "dashboard-directory-empty",
          "icon" => "hero-magnifying-glass",
          "heading" => "No matching dashboards",
          "copy" =>
            "Change the search, tag, or lifecycle filter. The filter state is preserved in the URL."
        }
      }
    }
  end

  defp dashboard_author_actions_dto(_mission_id, false), do: []

  defp dashboard_author_actions_dto(mission_id, true) do
    [
      %{
        "id" => "dashboard-directory-new",
        "label" => "New Dashboard",
        "href" => "/missions/#{mission_id}/ops/dashboards/new",
        "icon" => "hero-plus",
        "icon_class" => "h-4 w-4",
        "class" => "btn btn-primary btn-sm"
      },
      %{
        "id" => "dashboard-directory-import",
        "label" => "Import",
        "icon" => "hero-arrow-down-tray",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/new?mode=import",
        "class" => "btn btn-outline btn-sm"
      },
      %{
        "id" => "dashboard-directory-library",
        "label" => "Library",
        "icon" => "hero-squares-plus",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/library",
        "class" => "btn btn-ghost btn-sm"
      },
      %{
        "id" => "dashboard-directory-playlists",
        "label" => "Playlists",
        "icon" => "hero-play-circle",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/playlists",
        "class" => "btn btn-ghost btn-sm"
      }
    ]
  end

  defp directory_filters_dto(tags) do
    %{
      "id" => "dashboard-directory-filter-form",
      "values" => %{
        "query" => "",
        "lifecycle" => "active",
        "tag" => "all",
        "sort" => "updated"
      },
      "fields" => %{
        "query" => %{
          "id" => "directory_query",
          "name" => "directory[query]",
          "type" => "search",
          "label" => "Search",
          "placeholder" => "Name, description, or tag",
          "debounce_ms" => 250
        },
        "lifecycle" => %{
          "id" => "directory_lifecycle",
          "name" => "directory[lifecycle]",
          "type" => "select",
          "label" => "Lifecycle",
          "options" => [
            %{"label" => "Active", "value" => "active"},
            %{"label" => "Archived", "value" => "archived"},
            %{"label" => "All", "value" => "all"}
          ]
        },
        "tag" => %{
          "id" => "directory_tag",
          "name" => "directory[tag]",
          "type" => "select",
          "label" => "Tag",
          "options" =>
            [%{"label" => "All tags", "value" => "all"}] ++
              Enum.map(tags, &%{"label" => &1, "value" => &1})
        },
        "sort" => %{
          "id" => "directory_sort",
          "name" => "directory[sort]",
          "type" => "select",
          "label" => "Sort",
          "options" => [
            %{"label" => "Recently updated", "value" => "updated"},
            %{"label" => "Name", "value" => "name"},
            %{"label" => "Widget count", "value" => "widgets"}
          ]
        }
      }
    }
  end

  defp page(id, title, mission, params),
    do: %{
      "id" => id,
      "mission_id" => mission.mission_id,
      "header" => %{
        "eyebrow" => "Mission operations",
        "title" => title,
        "heading" => title,
        "description" => "Phoenix-owned mission-scoped #{title} data and controls.",
        "copy" => "Phoenix remains authoritative for this route-level surface."
      },
      "subject" => Map.values(params) |> Enum.find(&is_binary/1)
    }

  defp component_name("contact_requirement_list"), do: "OpsContactRequirementList"
  defp component_name("workspace"), do: "OpsConsoleLanding"
  defp component_name("contact_requirement_new"), do: "OpsContactRequirementNew"
  defp component_name("contact_requirement_show"), do: "OpsContactRequirementShow"
  defp component_name("contact_requirement_template"), do: "OpsContactRequirementTemplate"
  defp component_name("contact_schedule"), do: "OpsContactSchedule"
  defp component_name("contact_plan_show"), do: "OpsContactPlanShow"
  defp component_name("contact_detail"), do: "OpsContactDetail"
  defp component_name("contact_record"), do: "OpsContactRecord"
  defp component_name("dashboard_directory"), do: "OpsDashboardDirectory"
  defp component_name("dashboard_show"), do: "OpsDashboardShow"
  defp component_name("dashboard_editor"), do: "OpsDashboardShow"
  defp component_name("dashboard_activity"), do: "OpsDashboardActivitySurface"
  defp component_name("dashboard_new"), do: "OpsDashboardNew"
  defp component_name("dashboard_library"), do: "OpsDashboardLibrary"
  defp component_name("dashboard_playlists"), do: "OpsDashboardPlaylists"
  defp component_name("dashboard_playlist_present"), do: "OpsDashboardPlaylistPresent"
  defp component_name("dashboard_settings"), do: "OpsDashboardSettings"
  defp component_name("dashboard_share"), do: "OpsDashboardShare"
  defp component_name("dashboard_snapshot"), do: "OpsDashboardSnapshot"
  defp component_name("dashboard_diagnostics"), do: "OpsDashboardDiagnostics"
  defp component_name("fleet_planning"), do: "OpsFleetPlanning"
  defp component_name("fleet_planning_new"), do: "OpsFleetPlanningNew"
  defp component_name("fleet_planning_policy"), do: "OpsFleetPlanningPolicy"
  defp component_name("fleet_planning_run"), do: "OpsFleetPlanningRun"
  defp component_name("activation_requests"), do: "OpsActivationRequests"
  defp component_name("commands"), do: "OpsCommands"
  defp component_name("telemetry_explore"), do: "OpsTelemetryExplore"
  defp component_name("data_operations"), do: "OpsDataOperations"
  defp component_name("data_operations_manage"), do: "OpsDataOperationsManage"
  defp component_name("data_sources"), do: "OpsDataSources"
  defp component_name("data_source_registration"), do: "OpsDataSourceRegistration"
  defp component_name("data_source_settings"), do: "OpsDataSourceSettings"
  defp component_name("alarms"), do: "OpsAlarms"
  defp component_name("timeline"), do: "OpsTimeline"

  defp filters(id, keys),
    do: %{
      "id" => id,
      "values" => Map.new(keys, &{&1, ""}),
      "fields" =>
        Enum.map(
          keys,
          &%{
            "key" => &1,
            "name" => &1,
            "id" => "#{id}-#{&1}",
            "label" => String.capitalize(String.replace(&1, "_", " ")),
            "type" => "text",
            "options" => [],
            "placeholder" => "",
            "debounce_ms" => 250
          }
        )
    }

  defp form(id, submit_label, keys),
    do: %{
      "id" => id,
      "fields" =>
        Map.new(
          keys,
          &{&1,
           %{
             "id" => "#{id}-#{&1}",
             "name" => &1,
             "label" => String.capitalize(String.replace(&1, "_", " ")),
             "type" => "text",
             "value" => "",
             "required" => false,
             "options" => [],
             "errors" => []
           }}
        ),
      "submit" => %{"id" => "#{id}-submit", "label" => submit_label},
      "error" => nil
    }

  defp form_actions,
    do: %{
      "back" => link("ops-back", "Back", "#"),
      "cancel" => link("ops-cancel", "Cancel", "#"),
      "submit" => %{"id" => "ops-submit", "label" => "Save"}
    }

  defp link(id, label, href),
    do: %{"id" => id, "label" => label, "href" => href, "icon" => "hero-arrow-left"}

  defp journey,
    do: %{
      "steps" => [
        %{"number" => "01", "label" => "Need", "detail" => "Mission outcome", "active" => true},
        %{
          "number" => "02",
          "label" => "Plan",
          "detail" => "Provider evidence",
          "active" => false
        },
        %{"number" => "03", "label" => "Commit", "detail" => "Exact execution", "active" => false}
      ]
    }

  defp dashboard_form,
    do: form("dashboard-form", "Save dashboard", ["name", "description", "document_json"])

  defp playlist_form,
    do:
      form("playlist-form", "Create playlist", [
        "name",
        "description",
        "dashboard_ids",
        "dwell_seconds",
        "wallboard_mode"
      ])

  defp requirement_template_props(page),
    do: %{
      "page" => Map.put(page, "back", link("templates-back", "Operations", "#")),
      "ledger" => %{
        "eyebrow" => "Template ledger",
        "copy" => "Phoenix-owned reusable requirements.",
        "count" => 0,
        "count_label" => "templates",
        "list_id" => "requirement-templates",
        "stream_empty_id" => "requirement-templates-empty",
        "empty" => %{
          "id" => "requirement-templates-empty",
          "icon" => "hero-document",
          "title" => "No templates",
          "copy" => "No templates are available."
        }
      },
      "authorization" => %{"organization_admin" => false, "admin_required" => nil},
      "template_form" =>
        form("requirement-template-form", "Create template", [
          "title",
          "spacecraft_id",
          "contact_intent",
          "success_measure"
        ]),
      "templates" => []
    }

  defp schedule_props(page),
    do: %{
      "page" =>
        Map.merge(page, %{
          "contact_ledger" => ledger("contacts", "Contact Records"),
          "opportunities" => ledger("opportunities", "Provider Opportunities"),
          "reservations" => ledger("reservations", "Reservations"),
          "opportunity_search" => %{
            "eyebrow" => "Search",
            "description" => "Search Phoenix provider read models.",
            "icon" => "hero-magnifying-glass"
          }
        }),
      "search" =>
        form("contact-search-form", "Search", [
          "spacecraft_id",
          "starts_at",
          "ends_at",
          "route_key"
        ]),
      "readiness" => %{
        "id" => "contact-readiness",
        "title" => "Readiness",
        "findings" => [],
        "action" => link("readiness-action", "Review", "#")
      },
      "busy" => %{"actions" => %{}},
      "contact_records" => [],
      "opportunities" => [],
      "provider_reservations" => []
    }

  defp ledger(id, title),
    do: %{
      "id" => "#{id}-ledger",
      "eyebrow" => title,
      "title" => title,
      "description" => "Phoenix-owned mission records.",
      "rows_id" => "#{id}-rows",
      "timeline_action" =>
        link("#{id}-timeline", "Timeline", "/missions/:mission_id/ops/timeline"),
      "empty" => %{"id" => "#{id}-empty", "icon" => "hero-inbox", "copy" => "No records."}
    }

  defp plan_props(page),
    do: %{
      "page" => Map.put(page, "back_action", link("plan-back", "Contact Requirements", "#")),
      "submission_form" => form("plan-submission", "Submit plan", ["reason"]),
      "admin_controls" => nil,
      "selected_opportunities" => [],
      "execution_items" => [],
      "approvals" => []
    }

  defp record_props(page, id),
    do: %{
      "id" => "ops-contact-record-page",
      "header" => Map.merge(page["header"], %{"back" => link("record-back", "Contacts", "#")}),
      "contact_id" => id,
      "lifecycle" => %{"label" => "Observed", "class" => "badge-info"},
      "paths" => [],
      "intents" => [],
      "sources" => [],
      "events" => [],
      "summary" => %{"id" => "record-summary", "items" => []}
    }

  defp library_props(page),
    do: %{
      "page" => page,
      "dashboard_options" => [],
      "library_options" => [],
      "stage_form" => form("library-stage-form", "Stage item", ["dashboard_id", "item_id"]),
      "create_form" =>
        form("library-create-form", "Create item", [
          "name",
          "description",
          "widget_json",
          "change_summary"
        ]),
      "version_form" =>
        form("library-version-form", "Add version", [
          "item_id",
          "version",
          "widget_json",
          "change_summary"
        ]),
      "library_items" => []
    }

  defp settings_props(page),
    do: %{
      "page" =>
        Map.merge(page, %{
          "access" => %{
            "id" => "settings-access",
            "eyebrow" => "Access",
            "heading" => "Access",
            "copy" => "Mission-scoped access."
          },
          "sharing" => %{
            "id" => "settings-sharing",
            "eyebrow" => "Sharing",
            "heading" => "Shares",
            "copy" => "Phoenix-owned shares.",
            "list" => %{
              "id" => "shares",
              "empty" => %{"id" => "shares-empty", "copy" => "No shares."}
            }
          },
          "snapshots" => %{
            "id" => "settings-snapshots",
            "eyebrow" => "Snapshots",
            "heading" => "Snapshots",
            "list" => %{
              "id" => "snapshots",
              "empty" => %{"id" => "snapshots-empty", "copy" => "No snapshots."}
            }
          },
          "portability" => %{
            "eyebrow" => "Portability",
            "copy" => "Export is Phoenix-owned.",
            "export" => link("export-dashboard", "Export", "#"),
            "deployments" => %{
              "id" => "deployments",
              "empty" => %{"id" => "deployments-empty", "copy" => "No deployments."}
            }
          },
          "lifecycle" => %{
            "eyebrow" => "Lifecycle",
            "copy" => "Archive is Phoenix-owned.",
            "archive" => %{
              "id" => "archive-dashboard",
              "label" => "Archive",
              "icon" => "hero-archive-box",
              "confirm" => "Archive this dashboard?"
            }
          }
        }),
      "settings_form" =>
        form("dashboard-settings-form", "Save settings", [
          "name",
          "description",
          "tags",
          "defaults_json"
        ]),
      "share_form" =>
        form("dashboard-share-form", "Create share", ["data_visibility", "runtime_context"]),
      "snapshot_form" =>
        form("dashboard-snapshot-form", "Create snapshot", ["data_semantics", "data_visibility"]),
      "dashboard_shares" => [],
      "dashboard_snapshots" => [],
      "dashboard_deployments" => []
    }

  defp share_props(_page, share_id),
    do: %{
      "id" => "dashboard-share-page",
      "eyebrow" => "Authenticated mission share",
      "title" => "Dashboard context is ready",
      "restriction" => %{
        "prefix" => "This mission share is restricted to the authenticated mission.",
        "visibility_id" => "dashboard-share-visibility",
        "visibility" => "mission",
        "suffix" => "."
      },
      "context" => %{
        "id" => "dashboard-share-context",
        "entries" => [%{"key" => "share_id", "value" => share_id}]
      },
      "dashboard" => %{
        "id" => "dashboard-share-dashboard",
        "href" => "#",
        "label" => "Open dashboard"
      },
      "warning" => "Runtime values remain Phoenix-owned."
    }

  defp snapshot_props(page, snapshot_id),
    do: %{
      "id" => "dashboard-snapshot-page",
      "eyebrow" => "Read-only snapshot",
      "name" => page["header"]["title"],
      "policy" => %{
        "id" => "dashboard-snapshot-policy",
        "text" => "Snapshot #{snapshot_id} is immutable."
      },
      "warning" => "Definition and selectors are immutable.",
      "definition" => %{"id" => "dashboard-snapshot-definition", "items" => []},
      "context" => %{"id" => "dashboard-snapshot-context", "entries" => []},
      "navigation" => %{"back" => link("snapshot-back", "Dashboards", "#")}
    }

  defp current_dashboard,
    do: %{
      "id" => "current-dashboard",
      "title" => "Dashboard",
      "name" => "Dashboard",
      "dashboard_id" => nil,
      "href" => "#",
      "status" => %{"label" => "Ready", "class" => "badge-info"}
    }

  defp diagnostics_presentation(page),
    do: %{
      "root" => %{"attrs" => %{"id" => page["id"], "class" => "min-h-0 flex-1 overflow-y-auto"}},
      "header" => %{
        "attrs" => %{},
        "inner" => %{"attrs" => %{}},
        "content" => %{"attrs" => %{}},
        "eyebrow" => %{"attrs" => %{}, "text" => "Diagnostics"},
        "heading" => %{"attrs" => %{}, "text" => "Dashboard Diagnostics"},
        "copy" => %{"attrs" => %{}, "text" => "Phoenix-owned diagnostic evidence."}
      }
    }

  defp planning_props(page),
    do: %{
      "page" => page,
      "actions" => %{
        "refresh" => link("refresh-planning", "Refresh", "#"),
        "policy" => link("planning-policy", "Policy", "#"),
        "new_run" => link("new-fleet-run", "New run", "#")
      },
      "control_metrics" => [],
      "stopped_policy" => nil,
      "ledger" => ledger("fleet-runs", "Fleet runs"),
      "journey" => journey(),
      "recurring_demand" => %{"items" => []},
      "fleet_runs" => []
    }

  defp fleet_new_props(page),
    do: %{
      "header" => Map.put(page["header"], "back", link("planning-back", "Fleet planning", "#")),
      "policy_state" => %{
        "active" => false,
        "required" => %{
          "id" => "policy-required",
          "title" => "Policy required",
          "copy" => "An active Phoenix policy is required.",
          "action_id" => "open-policy",
          "action_label" => "Open policy",
          "icon" => "hero-shield-exclamation"
        }
      },
      "form" =>
        form("fleet-run-form", "Create run", ["horizon_start", "horizon_end", "include_recurring"]),
      "preview" => %{
        "id" => "fleet-preview",
        "eyebrow" => "Preview",
        "version" => nil,
        "details" => %{
          "id" => "fleet-preview-details",
          "copy" => "The policy preview is Phoenix-owned.",
          "summary" => "No active policy.",
          "facts" => []
        }
      },
      "paths" => %{"planning" => "#", "policy" => "#"}
    }

  defp fleet_policy_props(page),
    do: %{
      "page" =>
        Map.merge(page, %{
          "back" => link("policy-back", "Fleet planning", "#"),
          "state" => %{
            "id" => "policy-state",
            "label" => "Unavailable",
            "class" => "badge-warning"
          },
          "manifest" => %{"id" => "policy-manifest", "facts" => []}
        }),
      "policy_form" =>
        form("fleet-policy-form", "Save policy", [
          "maximum_horizon_hours",
          "maximum_execution_concurrency",
          "maximum_contacts"
        ]),
      "approval_form" => form("fleet-policy-approval-form", "Approve policy", ["reason"]),
      "authorization" => %{"organization_admin" => false, "admin_required" => nil},
      "grant_ledger" => %{"count" => 0, "label" => "active grants"},
      "grant_form" =>
        form("fleet-grant-form", "Issue grant", ["service_identity_id", "maximum_horizon_hours"]),
      "revocation_form" => form("fleet-revoke-form", "Revoke grant", ["automation_grant_id"]),
      "automation_grants" => []
    }

  defp fleet_run_props(page, run_id),
    do: %{
      "page" =>
        Map.merge(page, %{
          "run_id" => run_id,
          "back" => link("run-back", "Fleet planning", "#"),
          "header" =>
            Map.merge(page["header"], %{
              "run_id" => run_id,
              "lifecycle" => %{"label" => "Observed", "class" => "badge-info"},
              "algorithm" => "Phoenix planner",
              "refresh" => %{
                "id" => "refresh-fleet-run",
                "label" => "Refresh",
                "icon" => "hero-arrow-path",
                "payload" => %{}
              }
            }),
          "coverage" => %{
            "id" => "run-coverage",
            "list_id" => "run-coverage-rows",
            "columns" => [],
            "empty" => %{"id" => "run-coverage-empty", "copy" => "No coverage."}
          },
          "exception_queue" => %{
            "id" => "run-exceptions",
            "label" => "Exceptions",
            "list_id" => "run-exception-rows",
            "empty_id" => "run-exceptions-empty",
            "visible" => true
          },
          "decision_inspector" => %{
            "id" => "run-decisions",
            "label" => "Decisions",
            "list_id" => "run-decision-rows",
            "count" => 0,
            "copy" => "Phoenix-owned decisions.",
            "empty" => %{"id" => "run-decisions-empty", "copy" => "No decisions."}
          },
          "horizon" => %{
            "id" => "run-horizon",
            "counts" => [],
            "empty" => %{"id" => "run-horizon-empty", "copy" => "No commitments."}
          },
          "automation" => %{
            "label" => "Automation",
            "list_id" => "run-automation-rows",
            "empty_id" => "run-automation-empty",
            "visible" => true
          },
          "failure" => nil
        }),
      "repair_form" => form("fleet-repair-form", "Repair run", ["reason"]),
      "planning" => false,
      "requirement_rows" => [],
      "exceptions" => [],
      "decisions" => [],
      "horizon_commitments" => [],
      "resource_pressure" => [],
      "automation_actions" => []
    }

  defp activation_props(page),
    do: %{
      "page" => page,
      "selected" => nil,
      "form" => form("activation-decision-form", "Decide", ["request_id", "reason"]),
      "activation_requests" => []
    }

  defp telemetry_props(page, params),
    do: %{
      "page" => Map.put(page, "point_label", Map.get(params, "point_id", "Telemetry point")),
      "clipboard" => %{
        "button_id" => "telemetry-explore-copy-link",
        "text" => "#",
        "class" => "btn btn-ghost btn-sm",
        "icon" => "hero-link",
        "icon_class" => "h-4 w-4",
        "label" => "Copy link",
        "copied_message" => "Copied",
        "failed_message" => "Copy failed"
      },
      "investigation" => %{
        "id" => "telemetry-investigation",
        "label" => "Investigation",
        "path" => "#",
        "fingerprint" => ""
      },
      "navigation" => %{"back_to_dashboard" => nil},
      "questions" => [],
      "question_briefing" => nil,
      "filter_form" =>
        form("telemetry-filter-form", "Apply filters", [
          "point_id",
          "spacecraft_id",
          "data_source_id",
          "source_binding_id",
          "from",
          "to",
          "limit",
          "realm"
        ]),
      "point" => %{
        "id" => Map.get(params, "point_id"),
        "label" => Map.get(params, "point_id", "Telemetry point"),
        "name" => Map.get(params, "point_id", "Telemetry point"),
        "unit" => nil,
        "description" => nil,
        "options" => []
      },
      "selected_sample" => nil,
      "source_context" => %{"state" => "unselected", "rows" => []},
      "context_rows" => [],
      "diagnostics" => %{"id" => "telemetry-diagnostics", "rows" => []},
      "samples" => []
    }

  defp data_operations_props(page),
    do: %{
      "page" =>
        Map.merge(page, %{
          "groups_empty" => true,
          "selected_group_id" => nil,
          "navigation" => %{
            "manage" => link("data-sources", "Data Sources", "#"),
            "reader" => link("ops-home", "Operations", "#")
          }
        }),
      "request_form" =>
        form("historical-workflow-form", "Request workflow", [
          "run_id",
          "realm",
          "data_source_id",
          "workflow",
          "reason",
          "confirmed"
        ]),
      "selected_group" => nil,
      "data_operation_groups" => []
    }

  defp alarm_row(row),
    do: %{
      "id" => row.id,
      "limit_event_id" => row.limit_event_id,
      "severity" => to_string(row.severity),
      "state" => if(row.active?, do: "active", else: "nominal"),
      "point" => row.point_name || row.point_id,
      "context" => row.spacecraft_id,
      "value" => inspect(row.evaluated_value),
      "observed" => iso(row.generation_time),
      "evidence" => nil,
      "definition" => nil
    }

  defp timeline_event(event),
    do: %{
      "id" => event.mission_event_id,
      "mission_event_id" => event.mission_event_id,
      "occurred_at" => iso(event.occurred_at),
      "category" => to_string(event.category),
      "kind" => to_string(event.kind),
      "severity" => to_string(event.severity),
      "title" => event.title,
      "summary" => event.summary,
      "subject" => event.subject_id || event.spacecraft_id
    }

  defp command_row(row),
    do: %{
      "id" => row.id,
      "command_request_id" => row.command_request_id,
      "command_name" => row.command_name,
      "status" => %{
        "value" => to_string(row.status),
        "label" => to_string(row.status),
        "class" => "badge-info"
      },
      "target" => %{"display" => to_string(row.target), "label" => "Target"},
      "requester" => %{"display" => row.requested_by, "label" => "Requested by"},
      "age" => %{"display" => iso(row.occurred_at), "label" => "Occurred"},
      "evidence" => %{
        "summary" => "Phoenix command projection",
        "queue_entry" => %{"display" => "", "label" => "Queue"},
        "release_attempt" => %{"display" => "", "label" => "Release"},
        "request_state" => %{"display" => to_string(row.request_state), "label" => "Request"},
        "verification" => %{
          "display" => to_string(row.verification_state),
          "label" => "Verification"
        }
      },
      "focus" => nil
    }

  defp dashboard_row(summary, mission_id, dashboard_author?) do
    dashboard_id = summary.dashboard_id

    %{
      "id" => dashboard_id,
      "__dom_id" => "dashboard-#{dashboard_id}",
      "dashboard_id" => dashboard_id,
      "name" => summary.name,
      "description" => summary.description,
      "tags" => List.wrap(Map.get(summary, :tags, [])),
      "lifecycle" => lifecycle_dto(summary.lifecycle_state),
      "starred" => false,
      "open" => dashboard_open_dto(mission_id, summary),
      "star" => dashboard_star_dto(summary),
      "widget_version_label" =>
        "#{summary.widget_count} widgets · v#{summary.latest_version || 1}",
      "restore" => dashboard_restore_dto(summary)
    }
    |> maybe_put_clone(mission_id, summary, dashboard_author?)
  end

  defp lifecycle_dto("active"),
    do: %{
      "state" => "active",
      "class" =>
        "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-success/30 text-success"
    }

  defp lifecycle_dto("archived"),
    do: %{
      "state" => "archived",
      "class" =>
        "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-base-content/20 text-base-content/45"
    }

  defp dashboard_open_dto(mission_id, %{lifecycle_state: "active"} = summary),
    do: %{
      "id" => "dashboard-directory-open-#{summary.dashboard_id}",
      "href" => "/missions/#{mission_id}/ops/dashboards/#{summary.dashboard_id}"
    }

  defp dashboard_open_dto(_mission_id, _summary), do: nil

  defp dashboard_star_dto(summary),
    do: %{
      "id" => "dashboard-directory-star-#{summary.dashboard_id}",
      "payload" => %{"dashboard-id" => summary.dashboard_id, "starred" => "true"},
      "aria_label" => "Star #{summary.name}",
      "aria_pressed" => "false",
      "disabled" => summary.lifecycle_state == "archived",
      "title" =>
        if(summary.lifecycle_state == "archived",
          do: "Restore this dashboard before starring it",
          else: nil
        ),
      "icon" => "hero-star"
    }

  defp dashboard_restore_dto(%{lifecycle_state: "archived"} = summary),
    do: %{
      "id" => "restore-dashboard-#{summary.dashboard_id}",
      "label" => "Restore",
      "icon" => "hero-arrow-uturn-left",
      "payload" => %{
        "dashboard-id" => summary.dashboard_id,
        "expected-version" => to_string(summary.latest_version)
      },
      "disabled" => false,
      "lifecycle_action" => "restore",
      "action_available" => "available"
    }

  defp dashboard_restore_dto(_summary), do: nil

  defp maybe_put_clone(row, mission_id, %{lifecycle_state: "active"} = summary, true),
    do:
      Map.put(row, "clone", %{
        "id" => "clone-dashboard-#{summary.dashboard_id}",
        "label" => "Clone",
        "icon" => "hero-document-duplicate",
        "href" =>
          "/missions/#{mission_id}/ops/dashboards/new?source_dashboard_id=#{summary.dashboard_id}"
      })

  defp maybe_put_clone(row, _mission_id, _summary, _dashboard_author?),
    do: Map.put(row, "clone", nil)

  defp timeline_presentation(mission, _params),
    do: %{
      "root" => %{
        "attrs" => %{"id" => "ops-timeline-page", "class" => "min-h-0 flex-1 overflow-y-auto"}
      },
      "header" => %{
        "attrs" => %{},
        "inner" => %{"attrs" => %{}},
        "content" => %{"attrs" => %{}},
        "eyebrow" => %{"attrs" => %{}, "text" => "Mission timeline"},
        "heading" => %{"attrs" => %{}, "text" => "Timeline"},
        "description" => %{"attrs" => %{}, "text" => "Phoenix-owned mission events."},
        "return_link" => nil
      },
      "filters" =>
        filters("timeline-filter-form", [
          "category",
          "kind",
          "severity",
          "spacecraft_id",
          "from",
          "to"
        ]),
      "body" => %{"id" => "timeline-body"},
      "selected_event" => nil,
      "mission_id" => mission.mission_id
    }

  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp iso(value) when is_binary(value), do: value
  defp iso(_value), do: ""
  defp valid_text?(value), do: is_binary(value) and value != ""

  defp title(surface_id),
    do:
      surface_id
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)
end
