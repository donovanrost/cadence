defmodule Cadence.ProviderAdapters.TCPSocket.IngressDrops do
  @moduledoc """
  Rate-limited warnings for inbound bytes a TCP provider binding drops (#38): bytes on a binding
  with no ingress decoding (no protocol family it decodes, or no fixed message size), and COP-1
  CLCWs on a binding no `ingress_transport_binding_id` links to an uplink gateway. Either can
  keep a pass's FOP waiting for its first report, so its lane retries `uplink_busy` all pass.

  Each kind warns at most once a minute per connection, counting what was dropped since the
  last warning.
  """

  require Logger

  @interval_ms 60_000

  @type kind :: :undecoded | :clcw_unlinked

  @doc "Notes a drop on the receiver `state` and warns if this kind hasn't warned recently."
  @spec note(map(), kind(), non_neg_integer(), non_neg_integer()) :: map()
  def note(state, kind, reads_or_messages, bytes) do
    now = System.monotonic_time(:millisecond)
    drops = Map.get(state, :ingress_drops, %{})
    seen = Map.get(drops, kind, %{count: 0, bytes: 0, warned_at: nil})
    count = seen.count + reads_or_messages
    total = seen.bytes + bytes

    entry =
      if is_nil(seen.warned_at) or now - seen.warned_at >= @interval_ms do
        Logger.warning(message(state, kind, count, total))
        %{count: 0, bytes: 0, warned_at: now}
      else
        %{count: count, bytes: total, warned_at: seen.warned_at}
      end

    Map.put(state, :ingress_drops, Map.put(drops, kind, entry))
  end

  defp message(state, :undecoded, count, bytes) do
    "#{prefix(state)}: dropped #{count} read(s), #{bytes} bytes: the binding decodes no ingress " <>
      "(ingress_protocol_family #{inspect(state[:ingress_protocol_family])}, " <>
      "fixed_message_bytes #{inspect(state[:fixed_message_bytes])}); a CLCW sent here never " <>
      "reaches the uplink gateway"
  end

  defp message(state, :clcw_unlinked, count, bytes) do
    "#{prefix(state)}: dropped #{count} CLCW(s), #{bytes} bytes: no ingress_transport_binding_id " <>
      "links this binding to an uplink gateway, so its FOP keeps waiting for a first report"
  end

  defp prefix(state),
    do:
      "TCP provider #{state[:provider_binding_id]} (#{state[:direction]}, " <>
        "path #{state[:path_id]})"
end
