defmodule Cadence.Projections.DashboardRuntimeInvalidations do
  @moduledoc """
  Projection boundary for dashboard runtime invalidation decisions.

  Durable decision projections are preferred; the in-memory runtime-health
  projection is an explicit fallback when no durable decision is available.
  """

  alias Cadence.Dashboards
  alias Cadence.Telemetry.RuntimeHealth

  @spec list(keyword()) :: [map()]
  def list(opts \\ []) when is_list(opts) do
    case list_durable(opts) do
      [] -> RuntimeHealth.snapshot() |> Dashboards.dashboard_runtime_invalidation_decisions(opts)
      decisions -> decisions
    end
  end

  @spec list_durable(keyword()) :: [map()]
  def list_durable(opts \\ []) when is_list(opts) do
    Dashboards.durable_dashboard_runtime_invalidation_decisions(opts)
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  @spec record(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def record(event, decision, opts \\ []) when is_map(decision) and is_list(opts) do
    Dashboards.record_dashboard_runtime_invalidation_decision(event, decision, opts)
  end
end
