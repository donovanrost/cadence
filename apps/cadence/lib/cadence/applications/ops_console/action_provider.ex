defmodule Cadence.Applications.OpsConsole.ActionProvider do
  @moduledoc "Strict surface/action admission for the composed Ops action cohorts."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.Scope

  alias Cadence.Applications.OpsConsole.Actions.{
    ContactPlanning,
    DashboardDeepActions,
    DashboardWorkflows,
    DataSources,
    FleetPlanning,
    MissionOperations,
    TelemetryExplore,
    UiInteractions
  }

  @application_key "ops_console"
  @application_version 1
  @surface_version 1

  @cohort_adapters [
    UiInteractions,
    DashboardWorkflows,
    DashboardDeepActions,
    ContactPlanning,
    FleetPlanning,
    DataSources,
    MissionOperations,
    TelemetryExplore
  ]

  @binding_list Enum.flat_map(
                  @cohort_adapters,
                  fn adapter -> Enum.map(adapter.bindings(), &{&1, adapter}) end
                )

  @binding_keys Enum.map(@binding_list, &elem(&1, 0))
  @duplicate_binding_keys @binding_keys -- Enum.uniq(@binding_keys)
  @dispatch_valid? @duplicate_binding_keys == []
  @dispatch if @dispatch_valid?, do: Map.new(@binding_list), else: %{}

  @impl true
  def application_key, do: @application_key

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @binding_keys

  @spec binding_keys() :: [{binary(), binary()}]
  def binding_keys, do: @binding_keys

  @spec duplicate_binding_keys() :: [{binary(), binary()}]
  def duplicate_binding_keys, do: @duplicate_binding_keys

  @spec execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
          {:ok, term()} | {:error, term()}
  @impl true
  def execute(scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    if @dispatch_valid? do
      dispatch(scope, host_context, request)
    else
      {:error, :unsupported_application_action}
    end
  end

  def execute(_scope, _host_context, _request),
    do: {:error, :unsupported_application_action}

  defp dispatch(scope, host_context, request) do
    with :ok <- validate_request(request),
         {:ok, adapter} <- adapter_for(request.surface_id, request.action_id) do
      case adapter.execute(scope, host_context, request.surface_id, request) do
        {:ok, value} -> {:ok, adapter.result(value)}
        {:error, _reason} = error -> error
      end
    end
  end

  @impl true
  def result(
        %{"contract_version" => 1, "opportunities" => _, "search" => _, "route" => _} = value
      ),
      do: ContactPlanning.result(value)

  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp validate_request(%ActionRequest{
         application_key: @application_key,
         application_version: @application_version,
         surface_id: surface_id,
         surface_version: @surface_version,
         action_id: action_id,
         params: params
       })
       when is_binary(surface_id) and surface_id != "" and is_binary(action_id) and
              action_id != "" and is_map(params),
       do: :ok

  defp validate_request(_request), do: {:error, :unsupported_application_action}

  defp adapter_for(surface_id, action_id) do
    case Map.fetch(@dispatch, {surface_id, action_id}) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> {:error, :unsupported_application_action}
    end
  end
end
