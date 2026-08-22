defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommands do
  @moduledoc false

  alias Cadence.Control.TelemetryDataManagement, as: DataManagement

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams

  def record_decision(params, scope, mission, opts \\ [])
      when is_map(params) and is_list(opts) do
    params = LateDataPolicyParams.new(params)

    with {:ok, decision} <- require_param(params.decision, :decision),
         {:ok, execution_mode} <- require_param(params.execution_mode, :execution_mode),
         :ok <- validate_execution_context(execution_mode, params) do
      record_decision_for_mode(
        decision,
        execution_mode,
        LateDataPolicyParams.attrs(params, scope, mission),
        opts
      )
    end
  end

  defp record_decision_for_mode(decision, "sample_execution", attrs, opts) do
    case DataManagement.execute_late_data_policy(decision, attrs, opts) do
      {:ok, %{event: event}} -> {:ok, event}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_decision_for_mode(decision, "event_only", attrs, opts) do
    DataManagement.record_late_data_policy_decision(decision, attrs, opts)
  end

  defp record_decision_for_mode(_decision, execution_mode, _attrs, _opts) do
    {:error, {:unsupported_late_data_policy_execution_mode, execution_mode}}
  end

  defp require_param(nil, field), do: {:error, {:missing_field, field}}
  defp require_param(value, _field), do: {:ok, value}

  defp validate_execution_context("sample_execution", %{dashboard_time_mode: "replay_run"}) do
    {:error, :replay_late_data_policy_requires_event_only}
  end

  defp validate_execution_context(_execution_mode, _params), do: :ok
end
