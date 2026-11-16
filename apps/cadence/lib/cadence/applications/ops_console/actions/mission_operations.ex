defmodule Cadence.Applications.OpsConsole.Actions.MissionOperations do
  @moduledoc """
  Mission-scoped host actions for the Ops Console mission-operations cohort.

  This adapter deliberately has a separate `surface_id` argument. The final
  host composer will add that identity to the generic action request after the
  cohort adapters have been completed.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.Activations

  @application_key "ops_console"
  @application_version 1
  @surface_version 1

  # The data operations surfaces bind no host actions: their workflow decisions go through the
  # native path (`HistoricalWorkflowActions`: reason, evidence and lock checks), never this one.
  @host_bindings [{"activation_requests", "decide"}]

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

  defp exact_keys(map, expected) when is_map(map) do
    keys = Map.keys(map)

    if Enum.all?(keys, &is_binary/1) and Enum.sort(keys) == Enum.sort(expected),
      do: :ok,
      else: {:error, :invalid_action_input}
  end

  defp exact_keys(_map, _expected), do: {:error, :invalid_action_input}

  defp required_text(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, {:missing_field, key}}
    end
  end

  defp member_text(map, key, allowed) do
    if Map.get(map, key) in allowed, do: :ok, else: {:error, :invalid_action_input}
  end

  defp authorize(scope, %HostContext{mission_id: mission_id}, "activation_requests", "decide") do
    with :ok <- organization_admin(scope) do
      Policy.authorize(scope, :approve_activation, mission_context(scope, mission_id))
    end
  end

  defp authorize(_scope, _host_context, _surface_id, _action_id),
    do: {:error, :unsupported_application_action}

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
    Activations.review(scope, mission_id, params)
  end

  defp dispatch(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}
end
