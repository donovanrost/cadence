defmodule Cadence.Applications.OpsConsole.Actions.ContactPlanning do
  @moduledoc """
  Phoenix-owned Contact actions exposed to the Ops Console host.

  The route LiveViews remain the authoritative description of the workflows.
  This module only translates bounded host input into those existing context
  calls and returns bounded JSON values.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    ContactRequirementTemplates,
    Planner
  }

  alias Cadence.Contacts.{
    ProviderBooking,
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ProviderReservations,
    ProviderScheduling
  }

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts

  @application_key "ops_console"
  @application_version 1

  @bindings [
    {"contact_requirement_new", "validate"},
    {"contact_requirement_new", "save"},
    {"contact_requirement_show", "plan"},
    {"contact_requirement_show", "create-plan"},
    {"contact_requirement_template", "validate-template"},
    {"contact_requirement_template", "create-template"},
    {"contact_requirement_template", "pause-template"},
    {"contact_requirement_template", "activate-template"},
    {"contact_requirement_template", "close-template"},
    {"contact_schedule", "validate"},
    {"contact_schedule", "search"},
    {"contact_schedule", "reserve"},
    {"contact_schedule", "cancel"},
    {"contact_plan_show", "submit-plan"},
    {"contact_plan_show", "approve-plan"},
    {"contact_plan_show", "reject-plan"},
    {"contact_plan_show", "execute-plan"},
    {"contact_detail", "approve-provider-change"},
    {"contact_detail", "reject-provider-change"},
    {"contact_detail", "acknowledge-provider-change"}
  ]

  @requirement_fields ~w(
    spacecraft_id contact_intent earliest_start latest_end success_measure
    minimum_duration_seconds preferred_duration_seconds minimum_data_volume_bytes
    contact_count minimum_separation_seconds priority allowed_providers
    excluded_providers allowed_stations excluded_stations rationale
  )

  @template_fields ~w(
    spacecraft_id schedule_type anchor_at time_utc interval_minutes
    window_offset_minutes window_duration_minutes contact_intent success_measure
    minimum_duration_seconds preferred_duration_seconds minimum_data_volume_bytes
    contact_count minimum_separation_seconds priority approval_mode
    maximum_occurrences_per_run maximum_lookback_hours rationale
  )

  @search_fields ~w(spacecraft_id route_key starts_at ends_at)

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id} = host_context,
        surface_id,
        %ActionRequest{
          application_key: @application_key,
          application_version: @application_version,
          action_id: action_id,
          params: params
        }
      )
      when is_binary(surface_id) and is_binary(action_id) do
    with :ok <- validate_context(scope, host_context),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         true <- {surface_id, action_id} in @bindings,
         {:ok, params} <- prepare_params(params, mission_id),
         :ok <- authorize(scope, action_id, mission_id),
         {:ok, value} <- dispatch(scope, mission_id, surface_id, action_id, params) do
      {:ok, result(value)}
    else
      false -> {:error, :unsupported_action}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :malformed_action_request}
    end
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :malformed_action_request}

  @spec result(term()) :: term()
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe} -> safe
      {:error, _reason} -> nil
    end
  end

  defp validate_context(
         %Scope{
           organization_id: organization_id,
           actor_kind: actor_kind,
           mission_id: scoped_mission_id
         },
         %HostContext{mission_id: mission_id} = context
       ) do
    mission_bound? = actor_kind != :service or scoped_mission_id == mission_id

    if HostContext.valid?(context) and valid_id?(organization_id) and
         mission_bound? do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp prepare_params(params, mission_id) when is_map(params) do
    with :ok <- JSONBoundary.validate(params),
         true <- Enum.all?(Map.keys(params), &is_binary/1),
         :ok <- request_mission(Map.get(params, "mission_id"), mission_id) do
      {:ok, Map.delete(params, "mission_id")}
    else
      {:error, :scope_mismatch} -> {:error, :scope_mismatch}
      _invalid -> {:error, :malformed_input}
    end
  end

  defp prepare_params(_params, _mission_id), do: {:error, :malformed_input}

  defp request_mission(nil, _mission_id), do: :ok
  defp request_mission(mission_id, mission_id) when is_binary(mission_id), do: :ok
  defp request_mission(_mission_id, _expected), do: {:error, :scope_mismatch}

  defp authorize(scope, action_id, mission_id) do
    policy =
      cond do
        action_id in [
          "create-template",
          "pause-template",
          "activate-template",
          "close-template",
          "cancel"
        ] ->
          :manage_missions

        action_id in ["approve-plan", "reject-plan"] ->
          :approve_contact_plans

        action_id in [
          "approve-provider-change",
          "reject-provider-change",
          "acknowledge-provider-change"
        ] ->
          :approve_provider_changes

        true ->
          :operate_mission
      end

    policy_params = %{organization_id: scope.organization_id, mission_id: mission_id}

    case policy do
      :manage_missions ->
        Policy.authorize(scope, policy, %{organization_id: scope.organization_id})

      _policy ->
        Policy.authorize(scope, policy, policy_params)
    end
  end

  defp dispatch(_scope, _mission_id, "contact_requirement_new", "validate", params) do
    with {:ok, form} <- form_params(params, "contact_requirement", @requirement_fields) do
      {:ok, %{"contact_requirement" => form}}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_new", "save", params) do
    with {:ok, form} <- form_params(params, "contact_requirement", @requirement_fields),
         {:ok, attrs} <- requirement_attrs(form),
         {:ok, requirement, version} <- ContactRequirements.create(scope, mission_id, attrs) do
      {:ok, versioned_result("contactRequirement", requirement.contact_requirement_id, version)}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_show", "plan", params) do
    with {:ok, %{"contact_requirement_id" => requirement_id}} <-
           exact_ids(params, ["contact_requirement_id"]),
         {:ok, requirement, _version} <-
           ContactRequirements.fetch(scope.organization_id, mission_id, requirement_id),
         {:ok, planning} <-
           Planner.run(scope, mission_id, requirement_id, requirement.current_version) do
      {:ok,
       %{
         "contactRequirementId" => requirement_id,
         "planningRunId" => planning.run.contact_planning_run_id,
         "searchCount" => length(planning.searches),
         "opportunityCount" => length(planning.snapshots)
       }}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_show", "create-plan", params) do
    with {:ok, %{"contact_requirement_id" => requirement_id, "selected_snapshot_ids" => ids}} <-
           exact_selection_params(params),
         true <- ids != [],
         {:ok, _requirement, requirement_version} <-
           ContactRequirements.fetch(scope.organization_id, mission_id, requirement_id),
         {:ok, run_id} <- latest_run_id(scope.organization_id, mission_id, requirement_id),
         :ok <-
           selected_snapshots_match(
             scope.organization_id,
             mission_id,
             run_id,
             requirement_id,
             ids
           ),
         {:ok, plan, plan_version} <-
           ContactPlans.create(scope, mission_id, %{
             planning_run_ids: [run_id],
             selected_snapshot_ids: ids,
             rationale:
               "Operator-selected provider windows for #{requirement_version.contact_intent}"
           }) do
      {:ok, versioned_result("contactPlan", plan.contact_plan_id, plan_version)}
    else
      false -> {:error, :no_opportunities_selected}
      error -> error
    end
  end

  defp dispatch(_scope, _mission_id, "contact_requirement_template", "validate-template", params) do
    with {:ok, form} <- form_params(params, "template", @template_fields) do
      {:ok, %{"template" => form}}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_template", "create-template", params) do
    with {:ok, form} <- form_params(params, "template", @template_fields),
         {:ok, attrs} <- template_attrs(form),
         {:ok, template, version} <- ContactRequirementTemplates.create(scope, mission_id, attrs) do
      {:ok,
       versioned_result(
         "contactRequirementTemplate",
         template.contact_requirement_template_id,
         version
       )}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_template", action, params)
       when action in ["pause-template", "activate-template", "close-template"] do
    with {:ok, %{"id" => template_id}} <- exact_ids(params, ["id"]),
         {:ok, template, _version} <-
           ContactRequirementTemplates.fetch(scope.organization_id, mission_id, template_id),
         {:ok, updated} <-
           apply_template_transition(
             action,
             scope,
             mission_id,
             template_id,
             template.current_version
           ) do
      {:ok,
       %{
         "contactRequirementTemplateId" => updated.contact_requirement_template_id,
         "currentVersion" => updated.current_version,
         "lifecycleState" => Atom.to_string(updated.lifecycle_state)
       }}
    end
  end

  defp dispatch(_scope, _mission_id, "contact_schedule", "validate", params) do
    with {:ok, form} <- form_params(params, "contact_search", @search_fields) do
      {:ok, %{"contact_search" => form}}
    end
  end

  defp dispatch(scope, mission_id, "contact_schedule", "search", params) do
    with {:ok, form} <- form_params(params, "contact_search", @search_fields),
         {:ok, window} <- search_window(form),
         {:ok, found} <-
           ProviderScheduling.search_opportunities(
             scope.organization_id,
             mission_id,
             form["route_key"],
             window
           ) do
      {:ok, search_result(found, scope.organization_id, mission_id)}
    end
  end

  defp dispatch(scope, mission_id, "contact_schedule", "reserve", params) do
    with {:ok, %{"token" => token}} <- exact_ids(params, ["token"]),
         {:ok, payload} <- verify_opportunity(token),
         :ok <- token_scope(payload, scope.organization_id, mission_id),
         {:ok, route} <- token_route(payload, scope.organization_id, mission_id),
         :ok <- validate_token_route(route, payload["route"]),
         {:ok, attrs} <- reservation_attrs(payload, route),
         {:ok, booking} <-
           ProviderBooking.reserve(scope.organization_id, mission_id, route.provider_id, attrs) do
      {:ok, booking_result(booking)}
    end
  end

  defp dispatch(scope, mission_id, "contact_schedule", "cancel", params) do
    with {:ok, %{"reservation-id" => reservation_id}} <- exact_ids(params, ["reservation-id"]),
         {:ok, booking} <-
           ProviderBooking.cancel(scope.organization_id, mission_id, reservation_id) do
      {:ok, booking_result(booking)}
    end
  end

  defp dispatch(scope, mission_id, "contact_plan_show", "submit-plan", params) do
    with {:ok, plan_id, reason} <- plan_reason_params(params, "submission"),
         {:ok, plan, version} <-
           ManagementContacts.fetch_plan(scope.organization_id, mission_id, plan_id),
         {:ok, updated} <-
           ManagementContacts.submit_plan(
             scope,
             mission_id,
             plan_id,
             plan.current_version,
             reason
           ) do
      {:ok, versioned_result("contactPlan", updated.contact_plan_id, version)}
    end
  end

  defp dispatch(scope, mission_id, "contact_plan_show", action, params)
       when action in ["approve-plan", "reject-plan"] do
    with {:ok, plan_id, reason} <- plan_reason_params(params, "decision"),
         {:ok, plan, version} <-
           ManagementContacts.fetch_plan(scope.organization_id, mission_id, plan_id),
         {:ok, updated} <- decide_plan(action, scope, mission_id, plan, version, reason) do
      {:ok, versioned_result("contactPlan", updated.contact_plan_id, version)}
    end
  end

  defp dispatch(scope, mission_id, "contact_plan_show", "execute-plan", params) do
    with {:ok, %{"contact_plan_id" => plan_id}} <- exact_ids(params, ["contact_plan_id"]),
         {:ok, execution} <- ControlContacts.execute_approved_plan(scope, mission_id, plan_id) do
      {:ok, execution_result(execution)}
    end
  end

  defp dispatch(scope, mission_id, "contact_detail", action, params)
       when action in [
              "approve-provider-change",
              "reject-provider-change",
              "acknowledge-provider-change"
            ] do
    with {:ok, reservation_id, proposal_hash, reason} <- change_params(params, action),
         {:ok, reservation} <-
           ProviderReservations.fetch(scope.organization_id, mission_id, reservation_id),
         {:ok, change} <-
           current_change(scope.organization_id, reservation.provider_reservation_id),
         {:ok, decision} <-
           apply_change_decision(action, scope, change, proposal_hash, reason) do
      {:ok,
       %{
         "providerReservationChangeId" => decision.provider_reservation_change_id,
         "providerReservationId" => reservation.provider_reservation_id,
         "lifecycleState" => Atom.to_string(decision.lifecycle_state)
       }}
    end
  end

  defp dispatch(_scope, _mission_id, _surface_id, _action_id, _params),
    do: {:error, :unsupported_action}

  defp form_params(params, wrapper, fields) do
    with {:ok, form} <- wrapped_map(params, wrapper),
         {:ok, form} <- exact_string_map(form, fields) do
      {:ok, form}
    end
  end

  defp wrapped_map(params, key) do
    with {:ok, params} <- exact_map(params, [key]),
         {:ok, form} <- Map.fetch(params, key),
         true <- is_map(form) do
      {:ok, form}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp exact_string_map(value, fields) do
    with {:ok, value} <- exact_map(value, fields),
         true <- Enum.all?(Map.values(value), &is_binary/1) do
      {:ok, value}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp exact_map(value, keys) when is_map(value) do
    if Enum.all?(Map.keys(value), &is_binary/1) and
         MapSet.new(Map.keys(value)) == MapSet.new(keys) do
      {:ok, value}
    else
      {:error, :malformed_input}
    end
  end

  defp exact_map(_value, _keys), do: {:error, :malformed_input}

  defp exact_ids(params, keys) do
    with {:ok, params} <- exact_map(params, keys),
         true <- Enum.all?(Map.values(params), &(is_binary(&1) and &1 != "")) do
      {:ok, params}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp exact_selection_params(params) do
    with {:ok, params} <- exact_map(params, ["contact_requirement_id", "selected_snapshot_ids"]),
         true <-
           is_binary(params["contact_requirement_id"]) and params["contact_requirement_id"] != "",
         ids when is_list(ids) <- params["selected_snapshot_ids"],
         true <- ids != [] and Enum.all?(ids, &(is_binary(&1) and &1 != "")),
         true <- length(ids) == length(Enum.uniq(ids)) do
      {:ok, params}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp requirement_attrs(params) do
    with {:ok, earliest_start} <- parse_datetime(params["earliest_start"]),
         {:ok, latest_end} <- parse_datetime(params["latest_end"]),
         {:ok, minimum_duration} <- optional_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <- optional_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"], 1),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"], 0) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         service_direction: :downlink,
         contact_intent: params["contact_intent"],
         earliest_start: earliest_start,
         latest_end: latest_end,
         success_measure: params["success_measure"],
         minimum_duration_seconds: minimum_duration,
         preferred_duration_seconds: preferred_duration,
         minimum_data_volume_bytes: minimum_volume,
         contact_count: contact_count,
         minimum_separation_seconds: separation,
         priority: params["priority"],
         provider_constraints_document: %{
           "allowed" => refs(params["allowed_providers"]),
           "excluded" => refs(params["excluded_providers"])
         },
         station_constraints_document: %{
           "allowed" => refs(params["allowed_stations"]),
           "excluded" => refs(params["excluded_stations"])
         },
         policy_constraints_document: %{},
         approval_policy_document: %{"mode" => "manual"},
         rationale: params["rationale"],
         metadata: %{"source" => "ops_contact_requirement_form"}
       }}
    end
  end

  defp template_attrs(params) do
    with {:ok, anchor} <- parse_datetime(params["anchor_at"]),
         {:ok, offset} <- integer(params["window_offset_minutes"]),
         {:ok, duration} <- positive_integer(params["window_duration_minutes"]),
         {:ok, minimum} <- optional_positive_integer(params["minimum_duration_seconds"]),
         {:ok, preferred} <- optional_positive_integer(params["preferred_duration_seconds"]),
         {:ok, volume} <- optional_positive_integer(params["minimum_data_volume_bytes"]),
         {:ok, count} <- positive_integer(params["contact_count"]),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"]),
         {:ok, maximum} <- positive_integer(params["maximum_occurrences_per_run"]),
         {:ok, lookback} <- nonnegative_integer(params["maximum_lookback_hours"]),
         {:ok, schedule} <- schedule_document(params, anchor, offset, duration) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         schedule_document: schedule,
         requirement_document: %{
           "service_direction" => "downlink",
           "contact_intent" => params["contact_intent"],
           "success_measure" => params["success_measure"],
           "minimum_duration_seconds" => minimum,
           "preferred_duration_seconds" => preferred,
           "minimum_data_volume_bytes" => volume,
           "contact_count" => count,
           "minimum_separation_seconds" => separation,
           "priority" => params["priority"],
           "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
           "station_constraints_document" => %{"allowed" => [], "excluded" => []},
           "policy_constraints_document" => %{},
           "approval_policy_document" => %{"mode" => params["approval_mode"]},
           "rationale" => params["rationale"],
           "metadata" => %{}
         },
         catch_up_policy_document: %{
           "maximum_occurrences_per_run" => maximum,
           "maximum_lookback_seconds" => lookback * 3_600
         }
       }}
    end
  end

  defp schedule_document(params, anchor, offset, duration) do
    base = %{
      "type" => params["schedule_type"],
      "anchor_at" => DateTime.to_iso8601(anchor),
      "ends_at" => nil,
      "window_offset_seconds" => offset * 60,
      "window_duration_seconds" => duration * 60
    }

    case params["schedule_type"] do
      "fixed_interval" ->
        with {:ok, interval} <- positive_integer(params["interval_minutes"]) do
          {:ok, Map.put(base, "interval_seconds", interval * 60)}
        end

      "daily" ->
        case Time.from_iso8601(params["time_utc"]) do
          {:ok, time} -> {:ok, Map.put(base, "time_utc", Time.to_iso8601(time))}
          _invalid -> {:error, :invalid_daily_time}
        end

      _invalid ->
        {:error, :invalid_schedule_type}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      _invalid -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

  defp integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> {:error, :invalid_integer}
    end
  end

  defp optional_integer(value) when value in [""], do: {:ok, nil}
  defp optional_integer(value), do: positive_integer(value, nil)

  defp optional_positive_integer(""), do: {:ok, nil}
  defp optional_positive_integer(value), do: positive_integer(value)

  defp positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      {_, ""} -> {:error, :invalid_positive_integer}
      _invalid when value == "" -> {:ok, default}
      _invalid -> {:error, :invalid_positive_integer}
    end
  end

  defp positive_integer(value) do
    with {integer, ""} <- Integer.parse(value), true <- integer > 0 do
      {:ok, integer}
    else
      _invalid -> {:error, :invalid_positive_integer}
    end
  end

  defp nonnegative_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _invalid when value == "" -> {:ok, default}
      _invalid -> {:error, :invalid_nonnegative_integer}
    end
  end

  defp nonnegative_integer(value) do
    with {integer, ""} <- Integer.parse(value), true <- integer >= 0 do
      {:ok, integer}
    else
      _invalid -> {:error, :invalid_nonnegative_integer}
    end
  end

  defp refs(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp latest_run_id(organization_id, mission_id, requirement_id) do
    case Planner.list_runs(organization_id, mission_id, requirement_id) do
      [%{contact_planning_run_id: run_id} | _] -> {:ok, run_id}
      [] -> {:error, :contact_planning_run_not_found}
    end
  end

  defp selected_snapshots_match(organization_id, mission_id, run_id, requirement_id, ids) do
    if Enum.all?(ids, fn id ->
         case ContactPlans.fetch_opportunity_snapshot(organization_id, mission_id, id) do
           {:ok, snapshot} ->
             snapshot.contact_planning_run_id == run_id and
               snapshot.contact_requirement_id == requirement_id

           _not_found ->
             false
         end
       end) do
      :ok
    else
      {:error, :opportunity_scope_mismatch}
    end
  end

  defp apply_template_transition("pause-template", scope, mission_id, id, version),
    do: ContactRequirementTemplates.pause(scope, mission_id, id, version, "Paused by Ops Console")

  defp apply_template_transition("activate-template", scope, mission_id, id, version),
    do:
      ContactRequirementTemplates.activate(
        scope,
        mission_id,
        id,
        version,
        "Activated by Ops Console"
      )

  defp apply_template_transition("close-template", scope, mission_id, id, version),
    do: ContactRequirementTemplates.close(scope, mission_id, id, version, "Closed by Ops Console")

  defp search_window(params) do
    with {:ok, starts_at} <- parse_search_datetime(params["starts_at"]),
         {:ok, ends_at} <- parse_search_datetime(params["ends_at"]),
         true <- DateTime.before?(starts_at, ends_at) do
      {:ok,
       %{
         "spacecraft_id" => params["spacecraft_id"],
         "starts_at" => DateTime.to_iso8601(starts_at),
         "ends_at" => DateTime.to_iso8601(ends_at)
       }}
    else
      false -> {:error, :invalid_search_window}
      _invalid -> {:error, :invalid_search_datetime}
    end
  end

  defp parse_search_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> parse_datetime(value)
    end
  end

  defp verify_opportunity(token) do
    try do
      case apply(CadenceWeb.OpsContactScheduleLive.OpportunityToken, :verify, [token]) do
        {:ok, payload} when is_map(payload) ->
          case JSONBoundary.validate(payload) do
            :ok -> {:ok, payload}
            {:error, _reason} -> {:error, :malformed_opportunity_token}
          end

        {:error, reason} ->
          {:error, reason}

        _invalid ->
          {:error, :malformed_opportunity_token}
      end
    rescue
      UndefinedFunctionError -> {:error, :malformed_opportunity_token}
    end
  end

  defp token_scope(payload, organization_id, mission_id) do
    if payload["organization_id"] == organization_id and payload["mission_id"] == mission_id,
      do: :ok,
      else: {:error, :opportunity_scope_mismatch}
  end

  defp token_route(payload, organization_id, mission_id) do
    with spacecraft_id when is_binary(spacecraft_id) <- payload["spacecraft_id"],
         route_key when is_binary(route_key) <- payload["route_key"],
         {:ok, route} <-
           ProviderScheduling.resolve_ready_downlink_route(
             organization_id,
             mission_id,
             spacecraft_id,
             route_key
           ) do
      {:ok, route}
    else
      _invalid -> {:error, :provider_scheduling_route_not_ready}
    end
  end

  defp validate_token_route(route, signed_route) do
    if token_route(route) == signed_route, do: :ok, else: {:error, :route_changed}
  end

  defp token_route(route) do
    %{
      "provider_id" => route.provider_id,
      "provider_version" => route.provider_version,
      "transport_id" => route.transport_id,
      "transport_version" => route.transport_version,
      "provider_profile_id" => route.provider_profile_id,
      "provider_profile_version" => route.provider_profile_version,
      "routing_rule_id" => route.routing_rule_id,
      "path_template_id" => route.path_template_id,
      "path_template_version" => route.path_template_version,
      "source_endpoint_id" => route.source_endpoint_id,
      "provider_spacecraft_ref" => route.provider_spacecraft_ref,
      "service_profile_ref" => route.service_profile_ref,
      "delivery_profile_ref" => route.delivery_profile_ref
    }
  end

  defp reservation_attrs(payload, route) do
    with %{"id" => opportunity_id} = opportunity when is_binary(opportunity_id) <-
           payload["opportunity"],
         true <- is_map(payload["route"]) do
      suffix = stable_booking_suffix(payload)

      {:ok,
       opportunity
       |> Map.take([
         "id",
         "ground_station_ref",
         "antenna_or_service_pool_ref",
         "starts_at",
         "ends_at"
       ])
       |> Map.put("opportunity_ref", opportunity_id)
       |> Map.put("provider_reservation_id", "provider_reservation_#{suffix}")
       |> Map.put("scheduled_contact_id", "scheduled_contact_#{suffix}")
       |> Map.put("idempotency_key", "cadence:contact:#{suffix}")
       |> Map.put("provider_version", route.provider_version)
       |> Map.put("transport_id", route.transport_id)
       |> Map.put("transport_version", route.transport_version)
       |> Map.put("service_profile_ref", route.service_profile_ref)
       |> Map.put("delivery_profile_ref", route.delivery_profile_ref)
       |> Map.put("provider_profile_id", route.provider_profile_id)
       |> Map.put("provider_profile_version", route.provider_profile_version)
       |> Map.put("routing_rule_id", route.routing_rule_id)
       |> Map.put("transport_display_name", route.transport_display_name)
       |> Map.put("service_display_name", route.service_display_name)
       |> Map.put("delivery_display_name", route.delivery_display_name)
       |> Map.put("delivery_operator_summary", route.delivery_operator_summary)
       |> Map.put("cadence_spacecraft_id", route.spacecraft_id)
       |> Map.put("provider_spacecraft_ref", route.provider_spacecraft_ref)
       |> Map.put("source_endpoint_refs", [route.source_endpoint_id])
       |> Map.put("path_template_ids", [route.path_template_id])
       |> Map.put("path_template_refs", [
         %{"path_template_id" => route.path_template_id, "version" => route.path_template_version}
       ])}
    else
      _invalid -> {:error, :malformed_opportunity_token}
    end
  end

  defp search_result(%{route: route, opportunities: opportunities}, organization_id, mission_id) do
    route_token = token_route(route)

    %{
      "route" => route_token,
      "opportunities" =>
        Enum.map(opportunities, fn opportunity ->
          id = opportunity["id"]

          payload = %{
            "organization_id" => organization_id,
            "mission_id" => mission_id,
            "spacecraft_id" => route.spacecraft_id,
            "route_key" => route.route_key,
            "route" => route_token,
            "opportunity" =>
              Map.take(opportunity, [
                "id",
                "ground_station_ref",
                "antenna_or_service_pool_ref",
                "starts_at",
                "ends_at",
                "extensions"
              ])
          }

          opportunity
          |> Map.take([
            "id",
            "ground_station_ref",
            "antenna_or_service_pool_ref",
            "starts_at",
            "ends_at",
            "extensions"
          ])
          |> Map.put("provider_display_name", route.provider_display_name)
          |> Map.put("service_display_name", route.service_display_name)
          |> Map.put("delivery_display_name", route.delivery_display_name)
          |> Map.put("delivery_operator_summary", route.delivery_operator_summary)
          |> Map.put(
            "booking_token",
            apply(CadenceWeb.OpsContactScheduleLive.OpportunityToken, :sign, [payload])
          )
          |> Map.put("route_key", route.route_key)
          |> Map.put("provider_id", route.provider_id)
          |> Map.put("__dom_id", "opportunity-#{id}")
        end)
    }
  end

  defp stable_booking_suffix(payload) do
    [
      payload["organization_id"],
      payload["mission_id"],
      payload["route_key"],
      payload["opportunity"]["id"]
    ]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end

  defp plan_reason_params(params, wrapper) do
    with {:ok, params} <- exact_map(params, ["contact_plan_id", wrapper]),
         {:ok, wrapper} <- wrapped_map(params, wrapper),
         {:ok, form} <- exact_string_map(wrapper, ["reason"]),
         plan_id when is_binary(plan_id) and plan_id != "" <- params["contact_plan_id"] do
      {:ok, plan_id, form["reason"]}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp decide_plan("approve-plan", scope, mission_id, plan, version, reason) do
    ControlContacts.approve_and_accept_plan(
      scope,
      mission_id,
      plan.contact_plan_id,
      plan.current_version,
      version.content_sha256,
      reason
    )
    |> normalize_approved_plan()
  end

  defp decide_plan("reject-plan", scope, mission_id, plan, version, reason) do
    ManagementContacts.reject_plan(
      scope,
      mission_id,
      plan.contact_plan_id,
      plan.current_version,
      version.content_sha256,
      reason
    )
    |> normalize_plan()
  end

  defp normalize_approved_plan({:ok, approved}), do: {:ok, approved.plan}
  defp normalize_approved_plan(error), do: error

  defp normalize_plan({:ok, plan, _version, _approval}), do: {:ok, plan}
  defp normalize_plan({:ok, plan}), do: {:ok, plan}
  defp normalize_plan(error), do: error

  defp execution_result(%{plan: plan, items: items}) do
    %{
      "contactPlanId" => plan.contact_plan_id,
      "lifecycleState" => Atom.to_string(plan.lifecycle_state),
      "executionItemCount" => length(items)
    }
  end

  defp booking_result(%{provider_reservation: reservation, scheduled_contact: scheduled}) do
    %{
      "providerReservationId" => reservation.provider_reservation_id,
      "lifecycleState" => Atom.to_string(reservation.lifecycle_state),
      "scheduledContactId" => if(scheduled, do: scheduled.scheduled_contact_id, else: nil)
    }
  end

  defp current_change(organization_id, reservation_id) do
    case ProviderReservationChanges.list_for_reservation(organization_id, reservation_id)
         |> Enum.reverse()
         |> Enum.find(&(&1.lifecycle_state in [:pending_approval, :acknowledgment_required])) do
      nil -> {:error, :provider_reservation_change_not_found}
      change -> {:ok, change}
    end
  end

  defp change_params(params, action) do
    wrapper =
      case action do
        "approve-provider-change" -> "approval"
        "reject-provider-change" -> "rejection"
        "acknowledge-provider-change" -> "acknowledgment"
      end

    with {:ok, form} <- wrapped_map(params, wrapper),
         {:ok, form} <- exact_string_map(form, ["proposal_hash", "reason"]),
         {:ok, _params} <- exact_map(params, ["provider_reservation_id", wrapper]),
         reservation_id when is_binary(reservation_id) and reservation_id != "" <-
           params["provider_reservation_id"] do
      {:ok, reservation_id, form["proposal_hash"], form["reason"]}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp apply_change_decision("approve-provider-change", scope, change, hash, reason),
    do:
      ProviderChangeApprovals.approve(scope, change.provider_reservation_change_id, hash, reason)

  defp apply_change_decision("reject-provider-change", scope, change, hash, reason),
    do: ProviderChangeApprovals.reject(scope, change.provider_reservation_change_id, hash, reason)

  defp apply_change_decision("acknowledge-provider-change", scope, change, hash, reason),
    do:
      ProviderChangeApprovals.acknowledge(
        scope,
        change.provider_reservation_change_id,
        hash,
        reason
      )

  defp versioned_result(prefix, id, version) do
    %{
      "#{prefix}Id" => id,
      "version" => version.version,
      "contentSha256" => version.content_sha256
    }
  end

  defp valid_id?(value), do: is_binary(value) and value != ""
end
