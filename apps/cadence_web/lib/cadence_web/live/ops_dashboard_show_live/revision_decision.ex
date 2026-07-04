defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecision do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommands
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel

  def apply_decision(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = RevisionDecisionParams.from_event(params)

    if RevisionDecisionParams.confirmed?(params) do
      case apply_decision_command(opts).(params, scope, mission) do
        {:ok, _state, event} ->
          socket
          |> put_action_flash(action_outcome(:ok, event, params))
          |> put_decision_event_selection(event, opts)

        {:error, reason} ->
          put_action_flash(socket, action_outcome({:error, reason}, nil, params))
      end
    else
      put_action_flash(socket, action_outcome(:unconfirmed, nil, params))
    end
  end

  defp put_decision_event_selection(socket, event, opts) do
    query = %{
      "selected_target" => "telemetry_revision_decision_event",
      "selected_id" => event.decision_event_id,
      "realm" => text_value(event.realm),
      "data_source_id" => event.data_source_id,
      "source_binding_id" => event.binding_id
    }

    link = %DataLink{
      link_id: "direct:telemetry_revision_decision_event:#{event.decision_event_id}",
      label: "Telemetry revision decision event",
      target: :telemetry_revision_decision_event,
      target_id: event.decision_event_id,
      context: %{
        data: %{
          realm: event.realm,
          data_source_id: event.data_source_id,
          source_binding_id: event.binding_id
        }
      },
      source: :annotation
    }

    socket
    |> SelectionPanel.put_historical_workflow_link_selection(
      query,
      link,
      Keyword.put(opts, :preserve_data_link_action_outcome?, true)
    )
  end

  defp action_outcome(:ok, event, %RevisionDecisionParams{} = params) do
    RevisionDecisionActionOutcome.new(
      status: :ok,
      kind: :info,
      reason: "revision_decision_applied",
      decision: params.decision,
      dashboard_limit_mode: params.dashboard_limit_mode,
      result_event_id: event_id(event),
      target_event_id: event_id(event),
      target_observation_identity_id: observation_identity_id(event),
      message: "Telemetry revision decision applied."
    )
  end

  defp action_outcome({:error, reason}, _event, %RevisionDecisionParams{} = params) do
    RevisionDecisionActionOutcome.new(
      status: :error,
      kind: :error,
      reason: "revision_decision_failed",
      decision: params.decision,
      dashboard_limit_mode: params.dashboard_limit_mode,
      target_observation_identity_id: params.observation_identity_id,
      error: reason,
      message: "Failed to apply telemetry revision decision: #{inspect(reason)}"
    )
  end

  defp action_outcome(:unconfirmed, _event, %RevisionDecisionParams{} = params) do
    RevisionDecisionActionOutcome.new(
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      decision: params.decision,
      dashboard_limit_mode: params.dashboard_limit_mode,
      target_observation_identity_id: params.observation_identity_id,
      message: "Confirm the telemetry revision decision before applying it."
    )
  end

  defp event_id(%{decision_event_id: event_id}) when is_binary(event_id), do: event_id
  defp event_id(_event), do: nil

  defp observation_identity_id(%{observation_identity_id: observation_identity_id})
       when is_binary(observation_identity_id),
       do: observation_identity_id

  defp observation_identity_id(_event), do: nil

  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp put_action_flash(socket, %{kind: kind, message: message} = outcome) do
    socket
    |> assign(:data_link_action_outcome, outcome)
    |> put_flash(kind, message)
  end

  defp apply_decision_command(opts),
    do: Keyword.get(opts, :apply_decision, &RevisionDecisionCommands.apply_decision/3)
end
