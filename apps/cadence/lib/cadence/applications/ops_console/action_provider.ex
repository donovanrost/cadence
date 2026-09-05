defmodule Cadence.Applications.OpsConsole.ActionProvider do
  @moduledoc "Fail-closed provider for the source-complete federated Ops action cohort."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, JSONBoundary, OpsConsole}
  alias Cadence.Applications.OpsConsole.Actions

  @application_key "ops_console"
  @application_version 1
  @surface_version 1
  @surface_ids ~w(
    dashboard_editor dashboard_activity data_operations_manage
    data_source_registration data_source_settings
  )

  @bindings OpsConsole.surface_action_pairs()
            |> Enum.filter(fn {surface_id, _action_id} -> surface_id in @surface_ids end)

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec validate_bindings() :: :ok | {:error, atom()}
  def validate_bindings do
    declared =
      OpsConsole.surface_action_pairs()
      |> Enum.filter(fn {surface_id, _action_id} -> surface_id in @surface_ids end)

    cond do
      length(@bindings) != length(Enum.uniq(@bindings)) -> {:error, :duplicate_binding}
      @bindings != declared -> {:error, :omitted_or_extra_binding}
      true -> :ok
    end
  end

  @impl true
  def application_key, do: @application_key

  @impl true
  def execute(scope, host_context, %ActionRequest{} = request) do
    with :ok <- validate_bindings(),
         :ok <- validate_request(request),
         :ok <- validate_binding(request.surface_id, request.action_id),
         {:ok, result} <- dispatch(scope, host_context, request) do
      {:ok, result}
    end
  end

  def execute(_scope, _host_context, _request),
    do: {:error, :unsupported_application_action}

  @impl true
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
       when is_binary(surface_id) and is_binary(action_id) and is_map(params),
       do: :ok

  defp validate_request(_request), do: {:error, :unsupported_application_action}

  defp validate_binding(surface_id, action_id) do
    if {surface_id, action_id} in @bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp dispatch(scope, host_context, %ActionRequest{surface_id: surface_id} = request) do
    adapter = adapter_for(surface_id)

    case adapter.execute(scope, host_context, request) do
      {:ok, value} -> {:ok, adapter.result(value)}
      {:error, _reason} = error -> error
    end
  end

  defp adapter_for(surface_id) when surface_id in ["dashboard_editor", "dashboard_activity"],
    do: Actions.DashboardDeepActions

  defp adapter_for("data_operations_manage"), do: Actions.MissionOperations

  defp adapter_for(surface_id)
       when surface_id in ["data_source_registration", "data_source_settings"],
       do: Actions.DataSources
end
