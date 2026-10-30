defmodule Cadence.Capabilities.TransportExtension do
  @moduledoc """
  Behaviour for first-party transport-local capability families.
  """

  alias Cadence.Capabilities.{ExecutionContext, ExecutionResult}

  @callback init_transport(term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback handle_transport_event(term(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback handle_control_input(term(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback handle_timer(binary(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @callback snapshot_state(term(), ExecutionContext.t()) :: {:ok, term()} | {:error, term()}
  @callback export_checkpoint(term(), ExecutionContext.t()) :: {:ok, map()} | {:error, term()}
  @callback restore_checkpoint(map(), term(), ExecutionContext.t()) ::
              {:ok, ExecutionResult.t()} | {:error, term()}

  @optional_callbacks export_checkpoint: 2, restore_checkpoint: 3
end
