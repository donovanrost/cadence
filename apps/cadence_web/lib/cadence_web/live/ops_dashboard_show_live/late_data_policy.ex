defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicy do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelection
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommands
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  def record_decision(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = LateDataPolicyParams.from_event(params)

    if LateDataPolicyParams.confirmed?(params) do
      case record_decision_command(opts).(params, scope, mission) do
        {:ok, event} ->
          socket
          |> put_action_flash(action_outcome(:ok, event, params))
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(socket, action_outcome({:error, reason}, nil, params))
      end
    else
      put_action_flash(socket, action_outcome(:unconfirmed, nil, params))
    end
  end

  defp put_event_selection(socket, event, params, opts) do
    selection = HistoricalWorkflowSelection.event_selection(event, params)

    SelectionPanel.put_historical_workflow_link_selection(
      socket,
      late_data_policy_selection_query(selection.query, event, params),
      selection.link,
      Keyword.put(opts, :preserve_data_link_action_outcome?, true)
    )
  end

  defp late_data_policy_selection_query(query, event, %LateDataPolicyParams{} = params) do
    query
    |> SelectionQuery.to_params()
    |> Map.merge(
      %{
        "time_mode" => params.dashboard_time_mode,
        "replay_run_id" => params.dashboard_replay_run_id,
        "selected_data_view" => params.dashboard_data_view,
        "realm" => Map.get(event, :realm),
        "data_source_id" => Map.get(event, :data_source_id),
        "source_binding_id" => Map.get(event, :binding_id)
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()
    )
  end

  defp action_outcome(:ok, event, %LateDataPolicyParams{} = params) do
    LateDataPolicyActionOutcome.new(
      status: :ok,
      kind: :info,
      reason: "late_data_policy_applied",
      decision: params.decision,
      execution_mode: params.execution_mode,
      dashboard_time_mode: params.dashboard_time_mode,
      dashboard_replay_run_id: params.dashboard_replay_run_id,
      dashboard_data_view: params.dashboard_data_view,
      dashboard_limit_mode: params.dashboard_limit_mode,
      result_event_id: event_id(event),
      target_event_id: event_id(event),
      target_run_id: run_id(event),
      message: "Late-data policy applied."
    )
  end

  defp action_outcome({:error, reason}, _event, %LateDataPolicyParams{} = params) do
    LateDataPolicyActionOutcome.new(
      status: :error,
      kind: :error,
      reason: "late_data_policy_failed",
      decision: params.decision,
      execution_mode: params.execution_mode,
      dashboard_time_mode: params.dashboard_time_mode,
      dashboard_replay_run_id: params.dashboard_replay_run_id,
      dashboard_data_view: params.dashboard_data_view,
      dashboard_limit_mode: params.dashboard_limit_mode,
      error: reason,
      message: "Failed to apply late-data policy: #{inspect(reason)}"
    )
  end

  defp action_outcome(:unconfirmed, _event, %LateDataPolicyParams{} = params) do
    LateDataPolicyActionOutcome.new(
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      decision: params.decision,
      execution_mode: params.execution_mode,
      dashboard_time_mode: params.dashboard_time_mode,
      dashboard_replay_run_id: params.dashboard_replay_run_id,
      dashboard_data_view: params.dashboard_data_view,
      dashboard_limit_mode: params.dashboard_limit_mode,
      message: "Confirm the late-data policy decision before applying it."
    )
  end

  defp event_id(%{backfill_lifecycle_event_id: event_id}) when is_binary(event_id), do: event_id
  defp event_id(_event), do: nil

  defp run_id(%{backfill_run_id: run_id}) when is_binary(run_id), do: run_id
  defp run_id(_event), do: nil

  defp put_action_flash(socket, %{kind: kind, message: message} = outcome) do
    socket
    |> assign(:data_link_action_outcome, outcome)
    |> put_flash(kind, message)
  end

  defp record_decision_command(opts),
    do: Keyword.get(opts, :record_decision, &LateDataPolicyCommands.record_decision/3)
end
