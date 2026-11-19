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
  The uplink's CLCW stream (#38, #59 follow-up): `{:received, age_ms}` since the last CLCW,
  `{:awaiting, waited_ms}` while the FOP still waits for the pass's first one, or
  `:unavailable` when the runtime can't say.
  """
  @spec clcw_report(pid(), integer()) ::
          {:received, non_neg_integer()} | {:awaiting, non_neg_integer()} | :unavailable
  def clcw_report(runtime, now_ms \\ System.system_time(:millisecond)) do
    case TransportRuntime.snapshot(runtime) do
      {:ok, %{state: %{cop1_awaiting_clcw: true} = state}} ->
        {:awaiting, age(now_ms, Map.get(state, :cop1_started_at))}

      {:ok, %{state: %{cop1_clcw_at: at}}} when is_integer(at) ->
        {:received, age(now_ms, at)}

      {:ok, %{state: %{}}} ->
        {:received, 0}

      _other ->
        :unavailable
    end
  catch
    :exit, _ -> :unavailable
  end

  defp age(now_ms, at) when is_integer(at), do: max(now_ms - at, 0)
  defp age(_now_ms, _at), do: 0

  defdelegate begin_recovery(runtime, evidence), to: TransportRuntime, as: :begin_session_recovery

  @doc "Drops the session's connection to an unverified peer and keeps accepting (#67)."
  defdelegate drop_unverified_peer(runtime, peer, reason),
    to: TransportRuntime,
    as: :drop_session_peer

  defdelegate complete_recovery(runtime, evidence),
    to: TransportRuntime,
    as: :complete_session_recovery
end
