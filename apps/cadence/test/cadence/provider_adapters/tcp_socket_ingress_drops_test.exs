defmodule Cadence.ProviderAdapters.TCPSocket.IngressDropsTest do
  @moduledoc "#38: dropped inbound bytes on a TCP provider binding warn, at most once a minute."
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cadence.ProviderAdapters.TCPSocket.IngressDrops

  @receiver %{
    provider_binding_id: "provider-uplink-010",
    direction: :uplink,
    path_id: "route-010-uplink:uplink",
    ingress_protocol_family: :cop1_clcw,
    fixed_message_bytes: 4,
    ingress_transport_binding_id: nil
  }

  test "an unlinked CLCW warns once, then counts quietly until the next warning is due" do
    {state, log} =
      with_log(fn -> IngressDrops.note(@receiver, :clcw_unlinked, 1, 4) end)

    assert log =~ "TCP provider provider-uplink-010 (uplink, path route-010-uplink:uplink)"
    assert log =~ "dropped 1 CLCW(s), 4 bytes: no ingress_transport_binding_id"

    {state, log} =
      with_log(fn ->
        state
        |> IngressDrops.note(:clcw_unlinked, 2, 8)
        |> IngressDrops.note(:clcw_unlinked, 1, 4)
      end)

    refute log =~ "TCP provider provider-uplink-010"
    assert %{count: 3, bytes: 12} = state.ingress_drops.clcw_unlinked
  end

  test "each kind warns on its own schedule" do
    state = %{@receiver | ingress_protocol_family: nil, fixed_message_bytes: nil}

    log =
      capture_log(fn ->
        state
        |> IngressDrops.note(:clcw_unlinked, 1, 4)
        |> IngressDrops.note(:undecoded, 1, 37)
        |> IngressDrops.note(:undecoded, 1, 37)
      end)

    assert length(Regex.scan(~r/dropped 1 CLCW/, log)) == 1

    assert length(
             Regex.scan(~r/dropped 1 read\(s\), 37 bytes: the binding decodes no ingress/, log)
           ) == 1

    assert log =~ "ingress_protocol_family nil, fixed_message_bytes nil"
  end
end
