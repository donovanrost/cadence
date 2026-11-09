defmodule Cadence.Runtime.UplinkSessions do
  @moduledoc """
  Public runtime boundary for uplink session qualification (#44 D2): lists the running
  transport runtimes and exposes their session review and recovery steps, so a control-plane
  qualifier can drive them without reaching into runtime internals.
  """

  alias Cadence.Runtime.{ProcessNamespace, TransportRuntime}

  @type key :: {binary(), binary(), binary(), binary()}

  @doc "Running transport runtimes as `{{mission, contact, path, binding}, pid}`."
  @spec list(ProcessNamespace.t()) :: [{key(), pid()}]
  def list(%ProcessNamespace{registry: registry}) do
    Registry.select(registry, [
      {{{:transport_runtime, :"$1", :"$2", :"$3", :"$4"}, :"$5", :_}, [],
       [{{{{:"$1", :"$2", :"$3", :"$4"}}, :"$5"}}]}
    ])
  end

  defdelegate review(runtime), to: TransportRuntime, as: :session_review
  defdelegate begin_recovery(runtime, evidence), to: TransportRuntime, as: :begin_session_recovery

  defdelegate complete_recovery(runtime, evidence),
    to: TransportRuntime,
    as: :complete_session_recovery
end
