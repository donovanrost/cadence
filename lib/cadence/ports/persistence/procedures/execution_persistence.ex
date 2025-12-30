defmodule Cadence.Ports.Persistence.Procedures.ExecutionPersistence do
  @moduledoc """
  Port (behavior) defining the contract for v1 procedure execution persistence.

  This allows the execution engine to persist step events and final results
  without coupling directly to Ecto or the database.
  """

  alias Cadence.Procedures.ProcedureExecution

  @type execution_id :: String.t()

  @callback update_status_with_log(
              ProcedureExecution.t(),
              atom(),
              map(),
              atom(),
              String.t(),
              keyword()
            ) :: {:ok, ProcedureExecution.t()} | {:error, term()}

  @callback create_log_entry(execution_id(), atom(), String.t(), integer() | nil) ::
              {:ok, term()} | {:error, term()}

  @callback persist_and_broadcast_log(execution_id(), atom(), String.t(), integer() | nil) :: :ok

  @callback save_checkpoint(ProcedureExecution.t(), integer(), binary() | nil) ::
              {:ok, ProcedureExecution.t()} | {:error, term()}

  @callback persist_step_event(
              ProcedureExecution.t(),
              String.t(),
              atom(),
              term(),
              keyword()
            ) :: :ok | {:error, term()}

  @callback persist_dag_result(ProcedureExecution.t(), atom(), map()) ::
              {:ok, ProcedureExecution.t()} | {:error, term()}

  @callback list_step_events(execution_id()) :: list()

  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :execution_persistence,
      Cadence.Procedures.Engine.ExecutionPersistence
    )
  end
end
