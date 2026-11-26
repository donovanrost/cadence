defmodule CadenceSimulator.Provider.UplinkSessions do
  @moduledoc """
  Uplink sessions for active contacts whose uplink leg is included (#44).

  For each such contact a COP-1 `LoopbackPeer` connects to the uplink delivery target (Cadence's
  uplink listener), receives TC frames, runs FARM and answers with CLCWs. Decoded commands go to
  the contact's TM stream (`command_target`), whose telemetry then reflects their effects, so
  Cadence can verify commands from telemetry. The peer reconnects on its own until stopped.

  The caller (the Orchestrator) is linked to every peer it starts (DECISIONS #67): a peer can't
  outlive the Orchestrator that tracks it. An orphaned peer kept reconnecting to its station's
  uplink port and took the next pass's listener (qa #38 positive test).
  """

  alias CadenceSimulator.Provider.UplinkLeg

  @type sessions :: %{optional(binary()) => %{pid: pid(), reference: reference()}}

  @doc "Starts the contact's uplink session if its leg is included and none is running."
  @spec ensure(sessions(), map(), pid() | nil) :: sessions()
  def ensure(sessions, contact, stream_pid) do
    with nil <- Map.get(sessions, contact["id"]),
         %{} = target <- UplinkLeg.target(contact),
         {:ok, pid} <-
           CadenceSimulator.start_cop1_loopback_peer(
             host: target.host,
             port: target.port,
             tc_frame_size: target.tc_frame_size,
             command_target: stream_pid,
             clcw_overrides: armed(contact["id"])
           ) do
      true = Process.link(pid)
      Map.put(sessions, contact["id"], %{pid: pid, reference: Process.monitor(pid)})
    else
      _running_or_not_uplinked -> sessions
    end
  end

  @doc """
  Arms CLCW overrides for one contact's uplink session (test fault injection), e.g.
  `%{lockout: 1}`: the peer's FARM still accepts frames and attests `unlocked`, so the session
  qualifies, but every CLCW it reports carries the overrides. Read when the session starts, so
  arm before AOS; other contacts are unaffected. `disarm/1` clears it.
  """
  @spec arm(binary(), map()) :: :ok
  def arm(contact_id, overrides) when is_binary(contact_id) and is_map(overrides),
    do: :persistent_term.put({__MODULE__, :clcw_overrides, contact_id}, overrides)

  @spec disarm(binary()) :: boolean()
  def disarm(contact_id), do: :persistent_term.erase({__MODULE__, :clcw_overrides, contact_id})

  defp armed(contact_id), do: :persistent_term.get({__MODULE__, :clcw_overrides, contact_id}, %{})

  @spec stop(sessions(), binary()) :: sessions()
  def stop(sessions, contact_id) do
    case Map.pop(sessions, contact_id) do
      {nil, sessions} ->
        sessions

      {%{pid: pid, reference: reference}, sessions} ->
        Process.demonitor(reference, [:flush])
        # A deliberate stop isn't a failure: don't let its exit reach the caller (#67).
        Process.unlink(pid)
        if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
        sessions
    end
  end

  @doc "Drops a session whose peer exited; returns `:not_found` for other pids."
  @spec down(sessions(), reference()) :: {:ok, sessions()} | :not_found
  def down(sessions, reference) do
    case Enum.find(sessions, fn {_id, session} -> session.reference == reference end) do
      {contact_id, _session} -> {:ok, Map.delete(sessions, contact_id)}
      nil -> :not_found
    end
  end
end
