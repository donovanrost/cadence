defmodule Cadence.Applications.OpsConsole.Actions.ContactPlanning do
  @moduledoc """
  Phoenix-owned Contact actions exposed to the Ops Console host.

  Translates bounded host requests into domain services and returns bounded JSON
  values. Contact scheduling intent and execution belong to Cadence.Contacts;
  neither transport owns their lifetime.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}

  alias Cadence.Applications.OpsConsole.Actions.{
    PlanDecisions,
    ProviderChangeDecisions,
    RequirementDecisions,
    RequirementDeclarationInput,
    RequirementTemplateInput
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates
  }

  alias Cadence.Contacts.{
    ScheduleCommands,
    ScheduleOperations
  }

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

  # Version two separates durable mutations from page/socket state. Version one
  # remains available to already deployed remotes during the compatibility window.
  def execute(
        scope,
        %HostContext{placement: :mission, mission_id: mission},
        "contact_schedule",
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          action_id: action,
          params: %{"contract_version" => 2} = params
        }
      ) do
    ScheduleOperations.request(scope, mission, action, params)
  end

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

  defp dispatch(scope, mission, "contact_schedule", action, params)
       when action in ["search", "reserve", "cancel"],
       do: ScheduleCommands.execute(scope, mission, action, params)

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

  defp execution_result(%{plan: plan, items: items}) do
    %{
      "contactPlanId" => plan.contact_plan_id,
      "lifecycleState" => Atom.to_string(plan.lifecycle_state),
      "executionItemCount" => length(items)
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
