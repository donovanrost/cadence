defmodule Cadence.Capabilities.ManagedApplication do
  @moduledoc """
  Behaviour for first-party stateful managed application capabilities.
  """

  alias Cadence.Capabilities.{ExecutionContext, ExecutionResult}

  @callback init_instance(term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback handle_record(term(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback handle_timer(binary(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback snapshot_state(term(), ExecutionContext.t()) :: {:ok, term()} | {:error, term()}
end
