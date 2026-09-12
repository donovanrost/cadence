defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole do
  @moduledoc "Phoenix-owned query provider for every route-level Ops surface."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, JSONBoundary, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole, as: OpsDefinition
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Dashboards.PlaylistInput
  alias Cadence.Reads.ActivationApprovals
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation

  alias Cadence.Reads.ApplicationSurfaces.Planning.{
    ContactDetail,
    ContactPlanShow,
    ContactRecord,
    ContactRequirementList,
    ContactRequirementNew,
    ContactRequirementShow,
    ContactSchedule,
    FleetDirectory,
    FleetPolicy,
    FleetRun,
    FleetStart,
    RequirementTemplates
  }

  alias Cadence.Reads.CommandMonitor
  alias Cadence.Reads.Dashboards.Activity
  alias Cadence.Reads.Dashboards.Creation
  alias Cadence.Reads.Dashboards.Directory
  alias Cadence.Reads.LimitAlarmConditions
  alias Cadence.Reads.OpsWorkspace.Landing

  @application_key "ops_console"
  @application_version 1
  @surface_version 1
  @exploration_query_keys ~w(point_id spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id order limit selection_view data_view validity_state realm logical_source data_source_id source_binding_id source_dashboard_id sample_id selected_time question limit_mode)
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
         {:ok, safe_payload} <- JSONBoundary.safe_trusted_output(payload) do
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

  defp validate_params(%{id: "telemetry_explore"}, params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["mission_id" | @exploration_query_keys])),
         true <- Enum.all?(Map.values(params), &exploration_value?/1),
         :ok <- JSONBoundary.validate(params) do
      :ok
    else
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_params(%{id: "alarms"}, params) do
    case LimitAlarmConditions.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_params(%{id: "commands"}, params) do
    case CommandMonitor.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_params(%{id: "contact_requirement_list"}, params) do
    case ContactRequirementList.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "fleet_planning"}, params) do
    case FleetDirectory.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "contact_schedule"}, params) do
    case ContactSchedule.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "contact_record"}, params) do
    case ContactRecord.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "contact_detail"}, params) do
    case ContactDetail.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "contact_plan_show"}, params) do
    case ContactPlanShow.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "contact_requirement_show"}, params) do
    case ContactRequirementShow.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "fleet_planning_run"}, params) do
    case FleetRun.admit_query(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_params(%{id: "timeline"}, params) do
    if Enum.all?(params, fn {key, value} ->
         key in ~w(mission_id category kind severity spacecraft_id from to event_id source_dashboard_id before_at before_id) and
           is_binary(value) and byte_size(value) <= 512
       end), do: :ok, else: {:error, :unsupported_application_surface_query}
  end

  defp validate_params(%{id: surface_id} = spec, params)
       when surface_id in ~w(dashboard_show dashboard_editor dashboard_library dashboard_playlists dashboard_activity dashboard_playlist_present) do
    keys = ["mission_id" | Map.get(spec, :query_params, [])]

    with true <-
           Enum.all?(params, fn {key, value} ->
             key in keys and value != "" and exploration_value?(value) and
               (key not in ~w(mission_id dashboard_id playlist_id) or value not in [".", ".."])
           end),
         :ok <- validate_subject_param(surface_id, params),
         :ok <- validate_dashboard_destination(surface_id, params) do
      :ok
    else
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_params(%{id: "dashboard_directory"}, params) do
    case Directory.filters(Map.delete(params, "mission_id")) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_params(%{id: "dashboard_new"}, params) do
    if Enum.all?(params, fn {key, value} ->
         key in ~w(mission_id mode source_dashboard_id) and exploration_value?(value)
       end), do: :ok, else: {:error, :invalid_application_surface_query}
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

  defp validate_dashboard_destination("dashboard_activity", params) do
    case Activity.admit(Map.take(params, ~w(version selected_publish_issue))) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_dashboard_destination("dashboard_playlist_present", params) do
    case PlaylistInput.position(Map.take(params, ~w(index)), 100, false) do
      {:ok, _, _} -> :ok
      _ -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_dashboard_destination(_, _), do: :ok

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

  defp validate_subject("contact_requirement_show", organization_id, mission_id, params) do
    case ContactRequirements.fetch(
           organization_id,
           mission_id,
           params["contact_requirement_id"]
         ) do
      {:ok, _requirement, _version} -> :ok
      _ -> {:error, :subject_not_found}
    end
  end

  defp validate_subject("contact_plan_show", organization_id, mission_id, params) do
    case Cadence.Management.Contacts.fetch_plan(
           organization_id,
           mission_id,
           params["contact_plan_id"]
         ) do
      {:ok, _plan, _version} -> :ok
      _ -> {:error, :subject_not_found}
    end
  end

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
      fetch_subject(Cadence.ContactPlanning.FleetPlanningRuns, :fetch, [
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

  defp dispatch("workspace", scope, mission, _params), do: landing(scope, mission)
  defp dispatch("alarms", scope, mission, params), do: alarms(scope, mission, params)
  defp dispatch("timeline", scope, mission, params), do: timeline(scope, mission, params)
  defp dispatch("commands", scope, mission, params), do: commands(scope, mission, params)

  defp dispatch("dashboard_directory", scope, mission, params),
    do: dashboard_directory(scope, mission, params)

  defp dispatch(surface_id, _scope, mission, params)
       when surface_id in ~w(dashboard_show dashboard_editor),
       do:
         envelope("OpsDashboardShow", %{
           "mission_id" => mission.mission_id,
           "dashboard_id" => params["dashboard_id"],
           "mode" => if(surface_id == "dashboard_show", do: "view", else: "edit"),
           "query" => Map.drop(params, ~w(mission_id dashboard_id))
         })

  defp dispatch("dashboard_activity", _scope, mission, params),
    do:
      envelope("OpsDashboardActivitySurface", %{
        "mission_id" => mission.mission_id,
        "dashboard_id" => params["dashboard_id"],
        "query" => Map.take(params, ~w(version selected_publish_issue))
      })

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

  defp dispatch("activation_requests", scope, mission, _params) do
    case ActivationApprovals.load(scope, mission.mission_id) do
      {:ok, data} -> envelope("OpsActivationRequests", data)
      {:error, _reason} -> throw(:activation_inbox_unavailable)
    end
  end

  defp dispatch("contact_requirement_list", scope, mission, params) do
    case ContactRequirementList.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactRequirementList", model)
      {:error, _} -> throw(:requirement_list_unavailable)
    end
  end

  defp dispatch("contact_requirement_new", scope, mission, _params),
    do: envelope("OpsContactRequirementNew", ContactRequirementNew.load(scope, mission))

  defp dispatch("contact_schedule", scope, mission, params) do
    case ContactSchedule.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactSchedule", model)
      {:error, _} -> throw(:contact_schedule_unavailable)
    end
  end

  defp dispatch("contact_record", scope, mission, params) do
    case ContactRecord.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactRecord", model)
      {:error, _} -> throw(:contact_record_unavailable)
    end
  end

  defp dispatch("contact_detail", scope, mission, params) do
    case ContactDetail.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactDetail", model)
      {:error, _} -> throw(:reservation_detail_unavailable)
    end
  end

  defp dispatch("contact_plan_show", scope, mission, params) do
    case ContactPlanShow.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactPlanShow", model)
      {:error, _} -> throw(:plan_detail_unavailable)
    end
  end

  defp dispatch("contact_requirement_show", scope, mission, params) do
    case ContactRequirementShow.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsContactRequirementShow", model)
      {:error, _} -> throw(:requirement_detail_unavailable)
    end
  end

  defp dispatch("contact_requirement_template", scope, mission, _params),
    do: envelope("OpsContactRequirementTemplate", RequirementTemplates.load(scope, mission))

  defp dispatch("fleet_planning", scope, mission, params) do
    case FleetDirectory.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsFleetPlanning", model)
      {:error, reason} -> raise ArgumentError, "Fleet directory unavailable: #{inspect(reason)}"
    end
  end

  defp dispatch("fleet_planning_new", scope, mission, _params) do
    case FleetStart.load(scope, mission) do
      {:ok, model} -> envelope("OpsFleetPlanningNew", model)
      {:error, reason} -> raise ArgumentError, "Fleet start unavailable: #{inspect(reason)}"
    end
  end

  defp dispatch("fleet_planning_run", scope, mission, params) do
    case FleetRun.load(scope, mission, params) do
      {:ok, model} -> envelope("OpsFleetPlanningRun", model)
      {:error, _} -> throw(:fleet_run_unavailable)
    end
  end

  defp dispatch("fleet_planning_policy", scope, mission, _params),
    do: envelope("OpsFleetPlanningPolicy", FleetPolicy.load(scope, mission))

  defp dispatch("dashboard_new", scope, mission, params) do
    case Creation.load(scope, mission.mission_id, Map.delete(params, "mission_id")) do
      {:ok, model} ->
        envelope("OpsDashboardNew", %{
          "model" => %{
            "version" => 1,
            "context" => %{
              "organization_id" => scope.organization_id,
              "mission_id" => mission.mission_id
            },
            "mode" => model.mode,
            "source_dashboard_id" => model.source && model.source.id
          }
        })

      _ ->
        throw(:dashboard_creation_unavailable)
    end
  end

  defp dispatch(surface_id, _scope, mission, params), do: generic(surface_id, mission, params)

  defp landing(scope, mission) do
    case Landing.load(scope, mission.mission_id) do
      {:ok, model} -> envelope("OpsConsoleLanding", %{"model" => model})
      _ -> throw(:workspace_unavailable)
    end
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

  defp generic_props(surface_id, page, _params)
       when surface_id in ~w(dashboard_library dashboard_playlists),
       do: %{"mission_id" => page["mission_id"], "query" => %{}}

  defp generic_props("dashboard_playlist_present", page, params),
    do: %{
      "mission_id" => page["mission_id"],
      "playlist_id" => params["playlist_id"],
      "query" => Map.take(params, ~w(index))
    }

  defp generic_props("dashboard_settings", page, params),
    do: %{"mission_id" => page["mission_id"], "dashboard_id" => params["dashboard_id"]}

  defp generic_props("dashboard_share", page, params),
    do: %{"mission_id" => page["mission_id"], "share_id" => params["share_id"]}

  defp generic_props("dashboard_snapshot", page, params),
    do: %{"mission_id" => page["mission_id"], "snapshot_id" => params["snapshot_id"]}

  defp generic_props("dashboard_diagnostics", page, params),
    do: %{"mission_id" => page["mission_id"], "dashboard_id" => params["dashboard_id"]}

  defp generic_props("telemetry_explore", page, params), do: telemetry_props(page, params)
  defp generic_props("data_operations", page, _params), do: data_operations_props(page)

  defp alarms(_scope, mission, params) do
    envelope("OpsAlarms", %{
      "mission_id" => mission.mission_id,
      "query" => Map.delete(params, "mission_id")
    })
  end

  defp timeline(_scope, mission, params) do
    envelope("OpsTimeline", %{
      "mission_id" => mission.mission_id,
      "query" =>
        Map.take(
          params,
          ~w(category kind severity spacecraft_id from to event_id source_dashboard_id before_at before_id)
        )
    })
  end

  defp commands(_scope, mission, params) do
    envelope("OpsCommands", %{
      "mission_id" => mission.mission_id,
      "query" => Map.delete(params, "mission_id")
    })
  end

  defp dashboard_directory(scope, mission, params) do
    case Directory.load(scope, mission.mission_id, Map.delete(params, "mission_id")) do
      {:ok, model} ->
        envelope("OpsDashboardDirectory", %{
          "model" => %{
            "version" => 1,
            "context" => %{
              "organization_id" => scope.organization_id,
              "mission_id" => mission.mission_id
            },
            "filters" => model.filters
          }
        })

      _ ->
        throw(:dashboard_directory_unavailable)
    end
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

  defp link(id, label, href),
    do: %{"id" => id, "label" => label, "href" => href, "icon" => "hero-arrow-left"}

  defp telemetry_props(page, params),
    do: %{
      "mission_id" => page["mission_id"],
      "query" => Map.take(params, @exploration_query_keys)
    }

  defp exploration_value?(value) when is_binary(value) and byte_size(value) <= 256,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1f\x7f]/u, value)

  defp exploration_value?(_), do: false

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

  defp valid_text?(value), do: is_binary(value) and value != ""

  defp title(surface_id),
    do:
      surface_id
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)
end
