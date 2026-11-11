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

  @doc """
  Whether the uplink's protocol has the spacecraft's first report (#59): `:received`,
  `:awaiting`, or `:unavailable` when the runtime can't say (it errored or didn't answer). A
  caller deciding readiness treats `:unavailable` as not ready (#38: fail closed).
  """
  @spec first_report(pid()) :: :received | :awaiting | :unavailable
  def first_report(runtime) do
    case TransportRuntime.snapshot(runtime) do
      {:ok, %{state: %{cop1_awaiting_clcw: true}}} -> :awaiting
      {:ok, %{state: %{}}} -> :received
      _other -> :unavailable
    end
  catch
    :exit, _ -> :unavailable
  end

  defdelegate begin_recovery(runtime, evidence), to: TransportRuntime, as: :begin_session_recovery

  @doc "Drops the session's connection to an unverified peer and keeps accepting (#67)."
  defdelegate drop_unverified_peer(runtime, peer, reason),
    to: TransportRuntime,
    as: :drop_session_peer

  defdelegate complete_recovery(runtime, evidence),
    to: TransportRuntime,
    as: :complete_session_recovery
end
