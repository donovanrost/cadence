defmodule Cadence.Projections.DashboardRuntimeInvalidations do
  @moduledoc """
  Projection boundary for dashboard runtime invalidation decisions.

  Durable decision projections are preferred; the in-memory runtime-health
  projection is an explicit fallback when no durable decision is available.
  """

  alias Cadence.Dashboards.Diagnostics
  alias Cadence.Telemetry.RuntimeHealth

  @spec list(keyword()) :: [map()]
  def list(opts \\ []) when is_list(opts) do
    case list_durable(opts) do
      [] -> RuntimeHealth.snapshot() |> Diagnostics.runtime_invalidation_decisions(opts)
      decisions -> decisions
    end
  end

  @spec list_durable(keyword()) :: [map()]
  def list_durable(opts \\ []) when is_list(opts) do
    Diagnostics.durable_runtime_invalidation_decisions(opts)
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  @spec record(term(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def record(event, decision, opts \\ []) when is_map(decision) and is_list(opts) do
    Diagnostics.record_runtime_invalidation_decision(event, decision, opts)
  end
end
