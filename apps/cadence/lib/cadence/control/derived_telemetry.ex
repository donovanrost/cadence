defmodule Cadence.Control.DerivedTelemetry do
  @moduledoc """
  Control-plane handoff for governed derived-telemetry evaluation.

  Each run receives an immutable snapshot of the currently approved
  definitions so data-plane execution never queries management state.
  """

  alias Cadence.DerivedTelemetry, as: DataDerivedTelemetry
  alias Cadence.DerivedTelemetry.Run
  alias Cadence.Governance

  @spec evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    mission_id
    |> evaluation_opts(opts)
    |> then(&DataDerivedTelemetry.evaluate(mission_id, &1))
  end

  @spec start_evaluate(binary(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def start_evaluate(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    mission_id
    |> evaluation_opts(opts)
    |> then(&DataDerivedTelemetry.start_evaluate(mission_id, &1))
  end

  @spec fetch_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  defdelegate fetch_run(derived_run_id), to: DataDerivedTelemetry

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  defdelegate execute_enqueued_run(derived_run_id), to: DataDerivedTelemetry

  defp evaluation_opts(mission_id, opts) do
    Keyword.put(opts, :definitions, Governance.list_derived_definitions(mission_id))
  end
end
