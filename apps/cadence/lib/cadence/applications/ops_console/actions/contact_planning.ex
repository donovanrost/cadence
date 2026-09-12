defmodule Cadence.Applications.OpsConsole.Actions.ContactPlanning do
  @moduledoc """
  Phoenix-owned Contact actions exposed to the Ops Console host.

  The route LiveViews remain the authoritative description of the workflows.
  This module only translates bounded host input into those existing context
  calls and returns bounded JSON values.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}

  alias Cadence.Applications.OpsConsole.Actions.{
    PlanDecisions,
    ProviderChangeDecisions,
    RequirementDecisions,
    RequirementDeclarationInput,
    RequirementTemplateInput,
    ScheduleCancellations
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    OpportunityCapability
  }

  alias Cadence.Contacts.{
    ProviderBooking,
    ProviderScheduling
  }

  @application_key "ops_console"
  @application_version 1
  @opportunity_max_age_seconds 900

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
  def result(
        %{"contract_version" => 1, "opportunities" => _, "search" => _, "route" => _} = value
      ) do
    case JSONBoundary.safe_trusted_output(value) do
      {:ok, safe} -> safe
      {:error, _} -> nil
    end
  end

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
    with :ok <- validate_params(params),
         true <- Enum.all?(Map.keys(params), &is_binary/1),
         :ok <- request_mission(Map.get(params, "mission_id"), mission_id) do
      {:ok, Map.delete(params, "mission_id")}
    else
      {:error, :scope_mismatch} -> {:error, :scope_mismatch}
      _invalid -> {:error, :malformed_input}
    end
  end

  defp prepare_params(_params, _mission_id), do: {:error, :malformed_input}

  defp validate_params(%{"token" => token} = params)
       when is_binary(token) and byte_size(token) <= 8_192 do
    JSONBoundary.validate(Map.delete(params, "token"))
  end

  defp validate_params(params), do: JSONBoundary.validate(params)

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
    with {:ok, planning} <- RequirementDecisions.plan(scope, mission_id, params) do
      {:ok,
       %{
         "contactRequirementId" => planning.run.contact_requirement_id,
         "planningRunId" => planning.run.contact_planning_run_id,
         "searchCount" => length(planning.searches),
         "opportunityCount" => length(planning.snapshots),
         "navigation" => %{
           "href" =>
             "/missions/#{URI.encode(mission_id, &URI.char_unreserved?/1)}/ops/requirements/#{URI.encode(planning.run.contact_requirement_id, &URI.char_unreserved?/1)}?" <>
               URI.encode_query(%{
                 "version" => planning.run.contact_requirement_version,
                 "planning_run_id" => planning.run.contact_planning_run_id
               })
         }
       }}
    end
  end

  defp dispatch(scope, mission_id, "contact_requirement_show", "create-plan", params) do
    with {:ok, plan, version} <- RequirementDecisions.create_plan(scope, mission_id, params) do
      result = versioned_result("contactPlan", plan.contact_plan_id, version)

      {:ok,
       Map.merge(result, %{
         "actorId" => scope.user.user_id,
         "requirementEvidence" => params["requirement_evidence"],
         "planningRunId" => params["planning_run_id"],
         "navigation" => %{
           "href" =>
             "/missions/#{URI.encode(mission_id, &URI.char_unreserved?/1)}/ops/plans/#{URI.encode(plan.contact_plan_id, &URI.char_unreserved?/1)}"
         }
       })}
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
    with {:ok, params} <- exact_map(params, ["contact_search", "route_evidence"]),
         {:ok, form} <- exact_string_map(params["contact_search"], @search_fields),
         true <- is_map(params["route_evidence"]),
         {:ok, window} <- search_window(form),
         {:ok, found} <-
           ProviderScheduling.search_opportunities(
             scope.organization_id,
             mission_id,
             form["route_key"],
             window,
             expected_route: params["route_evidence"]
           ) do
      search_result(found, scope.organization_id, mission_id, form)
    else
      false -> {:error, :malformed_input}
      {:error, _} = error -> error
    end
  end

  defp dispatch(scope, mission_id, "contact_schedule", "reserve", params) do
    with {:ok, %{"token" => token}} <- exact_ids(params, ["token"]),
         {:ok, payload} <- verify_opportunity(token),
         :ok <- token_scope(payload, scope.organization_id, mission_id),
         :ok <- opportunity_current(payload),
         {:ok, route} <- token_route(payload, scope.organization_id, mission_id),
         :ok <- validate_token_route(route, payload["route"]),
         {:ok, attrs} <- reservation_attrs(payload, route),
         {:ok, booking} <-
           ProviderBooking.reserve(scope.organization_id, mission_id, route.provider_id, attrs) do
      {:ok, booking_result(booking)}
    end
  end

  defp dispatch(scope, mission_id, "contact_schedule", "cancel", params) do
    with {:ok, booking} <- ScheduleCancellations.execute(scope, mission_id, params),
         do: {:ok, booking_result(booking)}
  end

  defp dispatch(scope, mission_id, "contact_plan_show", "submit-plan", params) do
    with {:ok, plan_id, version} <- PlanDecisions.submit(scope, mission_id, params) do
      {:ok, versioned_result("contactPlan", plan_id, version)}
    end
  end

  defp dispatch(scope, mission_id, "contact_plan_show", action, params)
       when action in ["approve-plan", "reject-plan"] do
    with {:ok, plan_id, version} <- PlanDecisions.decide(scope, mission_id, action, params) do
      {:ok, versioned_result("contactPlan", plan_id, version)}
    end
  end

  defp dispatch(scope, mission_id, "contact_plan_show", "execute-plan", params) do
    with {:ok, execution} <- PlanDecisions.execute(scope, mission_id, params) do
      {:ok, execution_result(execution)}
    end
  end

  defp dispatch(scope, mission_id, "contact_detail", action, params)
       when action in [
              "approve-provider-change",
              "reject-provider-change",
              "acknowledge-provider-change"
            ] do
    ProviderChangeDecisions.decide(scope, mission_id, action, params)
  end

  defp dispatch(_scope, _mission_id, _surface_id, _action_id, _params),
    do: {:error, :unsupported_action}

  defp form_params(params, wrapper, fields) do
    with {:ok, form} <- wrapped_map(params, wrapper) do
      exact_string_map(form, fields)
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

  defp requirement_attrs(params),
    do: RequirementDeclarationInput.parse(params)

  defp template_attrs(params), do: RequirementTemplateInput.parse(params)

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      _invalid -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

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
    case OpportunityCapability.verify(token, max_age: @opportunity_max_age_seconds) do
      {:ok, payload} when is_map(payload) ->
        case JSONBoundary.validate(payload) do
          :ok -> {:ok, payload}
          {:error, _reason} -> {:error, :malformed_opportunity_token}
        end

      {:error, reason} ->
        {:error, reason}
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

  defp token_route(route), do: ProviderScheduling.route_evidence(route)

  defp opportunity_current(%{
         "opportunity" => %{"expires_at" => expires, "availability" => availability}
       }) do
    with true <- is_binary(expires) and availability in ["available", "limited"],
         {:ok, deadline, _} <- DateTime.from_iso8601(expires),
         true <- DateTime.after?(deadline, DateTime.utc_now()),
         do: :ok,
         else: (_ -> {:error, :opportunity_expired_or_unavailable})
  end

  defp opportunity_current(_), do: {:error, :opportunity_expired_or_unavailable}

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

  defp search_result(%{route: route, opportunities: opportunities} = found, org, mission, form) do
    result = %{
      "contract_version" => 1,
      "context" => %{"organization_id" => org, "mission_id" => mission},
      "search" => form,
      "route" => ProviderScheduling.route_summary(route),
      "truncated" => Map.get(found, :truncated, false),
      "opportunities" =>
        Enum.map(opportunities, fn o ->
          %{
            "id" => o["id"],
            "starts_at" => o["starts_at"],
            "ends_at" => o["ends_at"],
            "expires_at" => capability_expiry(o),
            "availability" => o["availability"],
            "synthetic" => o["synthetic"],
            "station" => o["ground_station_ref"],
            "antenna" => o["antenna_or_service_pool_ref"],
            "cost" => cost(get_in(o, ["extensions", "cost"])),
            "token" => OpportunityCapability.sign(opportunity_payload(o, route, org, mission))
          }
        end)
    }

    bounded_search_result(result)
  end

  defp bounded_search_result(result) do
    base = Map.put(result, "opportunities", [])

    bounded =
      Enum.reduce_while(result["opportunities"], base, fn opportunity, acc ->
        candidate = Map.update!(acc, "opportunities", &(&1 ++ [opportunity]))

        if bounded_search_output?(candidate),
          do: {:cont, candidate},
          else: {:halt, Map.put(acc, "truncated", true)}
      end)

    case JSONBoundary.safe_trusted_output(bounded) do
      {:ok, safe} -> {:ok, safe}
      {:error, _} -> {:error, :opportunity_response_unavailable}
    end
  end

  defp bounded_search_output?(candidate) do
    case JSONBoundary.safe_trusted_output(candidate) do
      {:ok, safe} -> byte_size(Jason.encode!(safe)) <= 60_000
      {:error, _} -> false
    end
  end

  defp capability_expiry(opportunity) do
    {:ok, provider_expiry, _} = DateTime.from_iso8601(opportunity["expires_at"])

    capability_expiry =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(@opportunity_max_age_seconds)

    if DateTime.before?(provider_expiry, capability_expiry),
      do: DateTime.to_iso8601(provider_expiry),
      else: DateTime.to_iso8601(capability_expiry)
  end

  defp cost(v) when is_number(v), do: v
  defp cost(_), do: nil

  defp opportunity_payload(opportunity, route, org, mission),
    do: %{
      "organization_id" => org,
      "mission_id" => mission,
      "spacecraft_id" => route.spacecraft_id,
      "route_key" => route.route_key,
      "route" => token_route(route),
      "opportunity" =>
        Map.take(
          opportunity,
          ~w(id ground_station_ref antenna_or_service_pool_ref starts_at ends_at expires_at availability)
        )
    }

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
      "providerRevision" => reservation.provider_revision,
      "lifecycleState" => Atom.to_string(reservation.lifecycle_state),
      "scheduledContactId" => if(scheduled, do: scheduled.scheduled_contact_id, else: nil)
    }
  end

  defp versioned_result(prefix, id, version) do
    %{
      "#{prefix}Id" => id,
      "version" => version.version,
      "contentSha256" => version.content_sha256
    }
  end

  defp valid_id?(value), do: is_binary(value) and value != ""
end
