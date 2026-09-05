defmodule Cadence.Applications.OpsConsole.Actions.MissionOperations do
  @moduledoc """
  Mission-scoped host actions for the Ops Console mission-operations cohort.

  This adapter deliberately has a separate `surface_id` argument. The final
  host composer will add that identity to the generic action request after the
  cohort adapters have been completed.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.{Activations, TelemetryDataManagement}
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

  @application_key "ops_console"
  @application_version 1
  @surface_version 1

  @data_operation_surfaces ["data_operations", "data_operations_manage"]

  @host_bindings [
    {"activation_requests", "decide"},
    {"data_operations", "validate-request"},
    {"data_operations", "record-historical-workflow-request"},
    {"data_operations", "transition-group"},
    {"data_operations", "retry-group"},
    {"data_operations", "request-correction"},
    {"data_operations_manage", "validate-request"},
    {"data_operations_manage", "record-historical-workflow-request"},
    {"data_operations_manage", "transition-group"},
    {"data_operations_manage", "retry-group"},
    {"data_operations_manage", "request-correction"}
  ]

  @workflow_keys ~w(
    workflow run_id realm data_source_id source_binding_id observable_id point_id point_ids
    source_from source_to dashboard_id dashboard_version dashboard_time_mode
    dashboard_replay_run_id dashboard_data_view dashboard_limit_mode
    comparison_review_request_event_id comparison_review_request_kind comparison_review_open_count
    comparison_review_open_placement_ids comparison_review_workflow_kind
    comparison_review_workflow_action comparison_review_workflow_selection_kind
    comparison_review_workflow_selection_count comparison_review_primary_data_view
    comparison_review_compare_data_view comparison_review_scope_kind comparison_review_scope_ids
    comparison_review_contact_ids comparison_review_resource_ids comparison_review_transport_ids
    comparison_review_source_endpoint_ids comparison_review_ground_station_ids
    comparison_review_scope_link_ids reason confirmed
  )

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @host_bindings

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, term()} | {:error, term()}
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    execute(scope, host_context, request.surface_id, request)
  end

  def execute(
        %Scope{} = scope,
        %HostContext{} = host_context,
        surface_id,
        %ActionRequest{} = request
      ) do
    with :ok <- validate_request(request),
         :ok <- validate_host_context(scope, host_context),
         :ok <- validate_binding(surface_id, request.action_id),
         :ok <- JSONBoundary.validate(request.params),
         :ok <- validate_action_params(surface_id, request.action_id, request.params),
         :ok <- validate_context_params(scope, host_context, request.params),
         :ok <- authorize(scope, host_context, surface_id, request.action_id) do
      dispatch(scope, host_context, surface_id, request)
    end
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term() | nil
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp validate_request(%ActionRequest{
         application_key: @application_key,
         application_version: @application_version,
         surface_id: request_surface_id,
         surface_version: @surface_version,
         action_id: action_id,
         params: params
       })
       when is_binary(request_surface_id) and is_binary(action_id) and is_map(params),
       do: :ok

  defp validate_request(_request), do: {:error, :unsupported_application_action}

  defp validate_host_context(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :mission,
           mission_id: mission_id
         } = host_context
       )
       when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
              mission_id != "" do
    if HostContext.valid?(host_context), do: :ok, else: {:error, :invalid_host_context}
  end

  defp validate_host_context(_scope, _host_context),
    do: {:error, :invalid_host_context}

  defp validate_binding(surface_id, action_id) do
    if {surface_id, action_id} in @host_bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_context_params(scope, %HostContext{mission_id: mission_id}, params) do
    with :ok <- matching_param(params, "organization_id", scope.organization_id) do
      matching_param(params, "mission_id", mission_id)
    end
  end

  defp matching_param(params, key, expected) do
    case Map.get(params, key) do
      nil -> :ok
      ^expected -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp validate_action_params(surface_id, "validate-request", params)
       when surface_id in @data_operation_surfaces,
       do: validate_workflow_values(params)

  defp validate_action_params(
         surface_id,
         "record-historical-workflow-request",
         params
       )
       when surface_id in @data_operation_surfaces,
       do: validate_workflow_values(params)

  defp validate_action_params(surface_id, "transition-group", params)
       when surface_id in @data_operation_surfaces do
    with :ok <- exact_keys(params, ["group-id", "stage"]),
         :ok <- required_text(params, "group-id") do
      member_text(params, "stage", ~w(approved rejected started completed failed))
    end
  end

  defp validate_action_params(surface_id, "retry-group", params)
       when surface_id in @data_operation_surfaces do
    with :ok <- exact_keys(params, ["group-id"]) do
      required_text(params, "group-id")
    end
  end

  defp validate_action_params(surface_id, "request-correction", params)
       when surface_id in @data_operation_surfaces do
    with :ok <- exact_keys(params, ["group-id", "event-id"]),
         :ok <- required_text(params, "group-id") do
      required_text(params, "event-id")
    end
  end

  defp validate_action_params("activation_requests", "decide", params) do
    with :ok <- exact_keys(params, ["activation_decision", "decision"]),
         {:ok, decision_params} <-
           nested_map(params, "activation_decision", ["request_id", "reason"]),
         :ok <- required_text(decision_params, "request_id"),
         :ok <- required_text(decision_params, "reason") do
      member_text(params, "decision", ["approved", "rejected"])
    end
  end

  defp validate_action_params(_surface_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp validate_workflow_values(params) do
    with {:ok, values} <- nested_map(params, "historical_workflow_request", @workflow_keys) do
      string_values(values)
    end
  end

  defp nested_map(params, key, allowed_keys) when is_map(params) do
    with {:ok, nested} <- Map.fetch(params, key),
         true <- is_map(nested),
         :ok <- exact_keys(nested, allowed_keys) do
      {:ok, nested}
    else
      :error -> {:error, :invalid_action_input}
      false -> {:error, :invalid_action_input}
      {:error, reason} -> {:error, reason}
    end
  end

  defp nested_map(_params, _key, _allowed_keys), do: {:error, :invalid_action_input}

  defp exact_keys(map, expected) when is_map(map) do
    keys = Map.keys(map)

    if Enum.all?(keys, &is_binary/1) and Enum.sort(keys) == Enum.sort(expected),
      do: :ok,
      else: {:error, :invalid_action_input}
  end

  defp exact_keys(_map, _expected), do: {:error, :invalid_action_input}

  defp string_values(map) when is_map(map) do
    if Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end),
      do: :ok,
      else: {:error, :invalid_action_input}
  end

  defp required_text(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, {:missing_field, key}}
    end
  end

  defp member_text(map, key, allowed) do
    if Map.get(map, key) in allowed, do: :ok, else: {:error, :invalid_action_input}
  end

  defp authorize(scope, %HostContext{mission_id: mission_id}, surface_id, action)
       when surface_id in @data_operation_surfaces and
              action in [
                "transition-group",
                "retry-group",
                "request-correction"
              ] do
    with :ok <- organization_admin(scope) do
      Policy.authorize(scope, :operate_mission, mission_context(scope, mission_id))
    end
  end

  defp authorize(scope, %HostContext{mission_id: mission_id}, "activation_requests", "decide") do
    with :ok <- organization_admin(scope) do
      Policy.authorize(scope, :approve_activation, mission_context(scope, mission_id))
    end
  end

  defp authorize(scope, %HostContext{mission_id: mission_id}, _surface_id, _action_id) do
    Policy.authorize(scope, :operate_mission, mission_context(scope, mission_id))
  end

  defp organization_admin(scope),
    do: Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id})

  defp mission_context(scope, mission_id),
    do: %{organization_id: scope.organization_id, mission_id: mission_id}

  defp dispatch(
         scope,
         %HostContext{mission_id: mission_id},
         "activation_requests",
         %ActionRequest{params: params}
       ) do
    decision_params = Map.fetch!(params, "activation_decision")
    request_id = decision_params["request_id"]
    reason = decision_params["reason"]

    with {:ok, request} <- ManagementActivations.fetch(scope, request_id),
         :ok <- bind_record(scope, mission_id, request.organization_id, request.mission_id) do
      decide_activation(scope, request_id, reason, params["decision"])
    end
  end

  defp dispatch(
         _scope,
         %HostContext{mission_id: _mission_id},
         surface_id,
         %ActionRequest{
           action_id: "validate-request",
           params: params
         }
       )
       when surface_id in @data_operation_surfaces do
    values = Map.fetch!(params, "historical_workflow_request")
    {:ok, %{"valid" => true, "values" => values}}
  end

  defp dispatch(
         scope,
         %HostContext{mission_id: mission_id},
         surface_id,
         %ActionRequest{action_id: "record-historical-workflow-request", params: params}
       )
       when surface_id in @data_operation_surfaces do
    values = Map.fetch!(params, "historical_workflow_request")

    with true <- values["confirmed"] in ["true", "on", "confirmed"],
         {:ok, events} <- record_request(scope, mission_id, values) do
      {:ok, %{"eventIds" => Enum.map(events, & &1.backfill_lifecycle_event_id)}}
    else
      false -> {:error, :confirmation_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch(
         scope,
         %HostContext{mission_id: mission_id},
         surface_id,
         %ActionRequest{action_id: "transition-group", params: params}
       )
       when surface_id in @data_operation_surfaces do
    group_id = params["group-id"]
    stage = params["stage"]

    with {:ok, events} <- group_events(scope.organization_id, mission_id, group_id),
         {:ok, workflow} <- group_workflow(events),
         {:ok, transitioned, jobs} <-
           TelemetryDataManagement.record_historical_data_workflow_group_transition(
             workflow,
             stage,
             events,
             operation_actor_attrs(scope, mission_id),
             []
           ) do
      {:ok,
       %{
         "eventIds" => Enum.map(transitioned, & &1.backfill_lifecycle_event_id),
         "jobResults" => Enum.map(jobs, &job_result/1)
       }}
    end
  end

  defp dispatch(
         scope,
         %HostContext{mission_id: mission_id},
         surface_id,
         %ActionRequest{action_id: "retry-group", params: %{"group-id" => group_id}}
       )
       when surface_id in @data_operation_surfaces do
    with {:ok, summary} <-
           TelemetryDataManagement.retry_historical_data_workflow_group_failed_jobs(
             group_id,
             operation_actor_attrs(scope, mission_id),
             []
           ) do
      {:ok, retry_summary(summary)}
    end
  end

  defp dispatch(
         scope,
         %HostContext{mission_id: mission_id},
         surface_id,
         %ActionRequest{action_id: "request-correction", params: params}
       )
       when surface_id in @data_operation_surfaces do
    group_id = params["group-id"]
    event_id = params["event-id"]

    with {:ok, event} <- failed_group_event(scope.organization_id, mission_id, group_id, event_id),
         {:ok, workflow} <- group_workflow([event]),
         {:ok, correction_event} <-
           TelemetryDataManagement.record_historical_data_workflow_correction_request(
             workflow,
             operation_actor_attrs(scope, mission_id),
             %{
               "request_group_id" => group_id,
               "original_event_id" => event_id,
               "original_run_id" => event.backfill_run_id,
               "original_job_id" => WorkflowEventEvidence.job_id(event)
             },
             []
           ) do
      {:ok, event_result(correction_event)}
    end
  end

  defp dispatch(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  defp decide_activation(scope, request_id, reason, "approved") do
    case Activations.approve_and_execute(scope, request_id, reason) do
      {:ok, execution} -> {:ok, activation_result(execution, "approved")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decide_activation(scope, request_id, reason, "rejected") do
    case ManagementActivations.reject(scope, request_id, reason) do
      {:ok, request, decision} ->
        {:ok,
         %{
           "activationRequestId" => request.activation_request_id,
           "decision" => Atom.to_string(decision.decision),
           "state" => Atom.to_string(request.state)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp activation_result(execution, decision) do
    %{
      "activationExecutionId" => execution.activation_execution_id,
      "activationRequestId" => execution.activation_request_id,
      "decision" => decision,
      "missionId" => execution.mission_id,
      "status" => Atom.to_string(execution.status)
    }
  end

  defp record_request(scope, mission_id, values) do
    workflow = text(values["workflow"]) || "backfill"
    run_id = text(values["run_id"]) || Cadence.Ids.new("telemetry_backfill_run")
    point_ids = request_point_ids(values)

    TelemetryDataManagement.record_historical_data_workflow_request(
      workflow,
      Map.merge(operation_attrs(scope, mission_id, values), %{
        backfill_run_id: run_id,
        import_run_id: run_id
      }),
      point_ids,
      []
    )
  end

  defp request_point_ids(values) do
    case split_text(values["point_ids"]) do
      [] ->
        Enum.uniq(
          Enum.filter([text(values["point_id"]), text(values["observable_id"])], &is_binary/1)
        )

      point_ids ->
        point_ids
    end
  end

  defp operation_attrs(scope, mission_id, values) do
    %{
      backfill_run_id: text(values["run_id"]),
      import_run_id: text(values["run_id"]),
      organization_id: scope.organization_id,
      mission_id: mission_id,
      realm: text(values["realm"]),
      data_source_id: text(values["data_source_id"]),
      binding_id: text(values["source_binding_id"]),
      observable_id: text(values["observable_id"]),
      point_id: text(values["point_id"]),
      source_from: text(values["source_from"]),
      source_to: text(values["source_to"]),
      actor_id: actor_id(scope),
      actor_kind: "operator",
      authority: :unknown,
      reason: text(values["reason"]) || "operator_requested_backfill",
      payload: %{}
    }
    |> compact()
  end

  defp operation_actor_attrs(scope, mission_id) do
    %{
      organization_id: scope.organization_id,
      mission_id: mission_id,
      actor_id: actor_id(scope),
      actor_kind: "operator"
    }
    |> compact()
  end

  defp bind_record(scope, mission_id, organization_id, record_mission_id) do
    cond do
      scope.organization_id != organization_id -> {:error, :scope_mismatch}
      mission_id != record_mission_id -> {:error, :scope_mismatch}
      true -> :ok
    end
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}}), do: user_id
  defp actor_id(%Scope{actor_kind: :user, user: %{id: user_id}}), do: user_id

  defp actor_id(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}}),
    do: id

  defp actor_id(_scope), do: nil

  defp group_events(organization_id, mission_id, group_id) do
    events =
      Storage.list_backfill_lifecycle_events(mission_id,
        organization_id: organization_id,
        limit: 1_000
      )
      |> Enum.filter(fn event ->
        BackfillLifecycleGroup.payload_value(event, :request_group_id) == group_id
      end)

    case events do
      [_event | _events] -> {:ok, events}
      [] -> {:error, {:request_group_not_found, group_id}}
    end
  end

  defp failed_group_event(organization_id, mission_id, group_id, event_id) do
    with {:ok, events} <- group_events(organization_id, mission_id, group_id),
         %Storage.BackfillLifecycleEvent{} = event <-
           Enum.find(events, fn candidate ->
             candidate.backfill_lifecycle_event_id == event_id and
               candidate.event_type in [:backfill_failed, :import_failed]
           end) do
      {:ok, event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp group_workflow([event | _events]) do
    case WorkflowEventEvidence.workflow(event) do
      "backfill" -> {:ok, :backfill}
      "import" -> {:ok, :import}
      :backfill -> {:ok, :backfill}
      :import -> {:ok, :import}
      _workflow -> {:error, :unsupported_historical_data_workflow}
    end
  end

  defp event_result(event) do
    %{
      "eventId" => event.backfill_lifecycle_event_id,
      "eventType" => Atom.to_string(event.event_type),
      "missionId" => event.mission_id,
      "runId" => event.backfill_run_id
    }
  end

  defp job_result({:ok, nil}), do: nil
  defp job_result({:ok, job}), do: %{status: "started", job_id: job.job_id}
  defp job_result({:error, reason}), do: %{status: "error", reason: inspect(reason)}
  defp job_result(value), do: value

  defp retry_summary(summary) do
    summary
    |> Map.take([:retried, :nonretryable, :skipped, :failed])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp split_text(value) when is_binary(value),
    do: value |> String.split([",", "\n", "\r", "\t", " "], trim: true) |> Enum.uniq()

  defp split_text(_value), do: []

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end
end
