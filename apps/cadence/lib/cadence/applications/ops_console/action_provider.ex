defmodule Cadence.Applications.OpsConsole.ActionProvider do
  @moduledoc "Fail-closed action provider for the bounded, read-only Ops cohort."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary, OpsConsole}
  alias Cadence.Auth.{Policy, Scope}

  @application_key "ops_console"

  @impl true
  def application_key, do: @application_key

  @impl true
  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: action_id,
          params: params
        }
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(action_id) and is_map(params) do
    with true <- declared?(action_id),
         :ok <- JSONBoundary.validate(params),
         :ok <- validate_mission_param(mission_id, params),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         :ok <- dispatch(action_id) do
      {:ok, %{"status" => "accepted", "actionId" => action_id, "missionId" => mission_id}}
    else
      false ->
        {:error, :unsupported_application_action}

      {:error, :ops_console_action_pending_exact_wiring} ->
        {:error, :ops_console_action_pending_exact_wiring}

      {:error, _reason} ->
        {:error, :unsupported_application_action}
    end
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @impl true
  def result(value), do: value

  defp declared?(action_id) do
    OpsConsole.definition().actions
    |> Enum.any?(&(&1.action_id == action_id))
  end

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp dispatch(action_id) do
    case Map.fetch(action_dispatch(), action_id) do
      {:ok, :wired} -> :ok
      {:ok, :residual} -> {:error, :ops_console_action_pending_exact_wiring}
      :error -> {:error, :unsupported_application_action}
    end
  end

  defp action_dispatch, do: Map.new(OpsConsole.action_ids(), &{&1, :residual})
end
