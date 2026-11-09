defmodule CadenceSimulator.Provider.UplinkSessions do
  @moduledoc """
  Uplink sessions for active contacts whose uplink leg is included (#44).

  For each such contact a COP-1 `LoopbackPeer` connects to the uplink delivery target (Cadence's
  uplink listener), receives TC frames, runs FARM and answers with CLCWs. Decoded commands go to
  the contact's TM stream (`command_target`), whose telemetry then reflects their effects, so
  Cadence can verify commands from telemetry. The peer reconnects on its own until stopped.
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
             command_target: stream_pid
           ) do
      Map.put(sessions, contact["id"], %{pid: pid, reference: Process.monitor(pid)})
    else
      _running_or_not_uplinked -> sessions
    end
  end

  @spec stop(sessions(), binary()) :: sessions()
  def stop(sessions, contact_id) do
    case Map.pop(sessions, contact_id) do
      {nil, sessions} ->
        sessions

      {%{pid: pid, reference: reference}, sessions} ->
        Process.demonitor(reference, [:flush])
        if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
        sessions
    end
  end

  @doc "Stops sessions whose contact is no longer active."
  @spec stop_except(sessions(), MapSet.t()) :: sessions()
  def stop_except(sessions, active_ids) do
    sessions
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(active_ids, &1))
    |> Enum.reduce(sessions, &stop(&2, &1))
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
