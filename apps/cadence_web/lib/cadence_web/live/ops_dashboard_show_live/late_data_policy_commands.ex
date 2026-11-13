defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommands do
  @moduledoc false

  alias Cadence.Control.TelemetryDataManagement, as: DataManagement
  alias Cadence.Telemetry.Storage

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams

  def record_decision(params, scope, mission, opts \\ [])
      when is_map(params) and is_list(opts) do
    params = LateDataPolicyParams.new(params)

    with {:ok, decision} <- require_param(params.decision, :decision),
         {:ok, execution_mode} <- require_param(params.execution_mode, :execution_mode),
         :ok <- validate_execution_context(execution_mode, params),
         :ok <- require_own_run(params.run_id, scope, mission) do
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

  # The decision is recorded against an existing run of this organization and mission. A client
  # run id naming another tenant's run would make its own dashboard read that run's job (id,
  # status, failure) back through the global (job_type, run_id) lookup.
  defp require_own_run(run_id, scope, mission) when is_binary(run_id) do
    case Storage.list_backfill_lifecycle_events(mission.mission_id,
           organization_id: scope.organization_id,
           backfill_run_id: run_id,
           limit: 1
         ) do
      [_event] -> :ok
      [] -> {:error, {:backfill_run_not_found, run_id}}
    end
  end

  defp require_own_run(_run_id, _scope, _mission), do: :ok
end
