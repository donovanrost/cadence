defmodule Cadence.Comms.TransportListenAllowlistTest do
  @moduledoc """
  #990 (DECISIONS #115): a listening TCP transport names the source addresses it accepts. One
  without them can't be created, in any environment; entries are IP addresses or CIDR ranges; the
  list reaches the materialized provider profile; and a provider's delivery profile supplies it as
  `egress.source_addresses`. Client mode (Cadence connects) needs none. An entry that allows every
  address (a whole-family prefix) is refused everywhere.
  """
  use ExUnit.Case, async: true

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportKinds.TCPSocket

  @listen %{
    "mode" => "listen",
    "direction_capability" => "inbound",
    "host" => "0.0.0.0",
    "port" => 4100,
    "framing_mode" => "fixed_size",
    "frame_size" => 1115
  }

  test "a listening transport without allowed source addresses is refused" do
    for missing <- [nil, [], "", " , "] do
      config = Map.put(@listen, "expected_peer_addresses", missing)

      assert TCPSocket.normalize_config(config) ==
               {:error,
                "A listening transport needs its allowed source addresses: the IP addresses " <>
                  "or CIDR ranges the provider connects from."}
    end
  end

  test "each entry must be an IP address or CIDR range; the field names the bad one" do
    config = Map.put(@listen, "expected_peer_addresses", ["10.0.0.0/8", "not-an-address"])

    assert {:error,
            "Allowed source addresses: \"not-an-address\" is not an IP address or CIDR range."} =
             TCPSocket.normalize_config(config)

    assert {:error, "Allowed source addresses: " <> _} =
             TCPSocket.normalize_config(
               Map.put(@listen, "expected_peer_addresses", ["10.0.0.0/33"])
             )
  end

  test "entries are normalized (text or list, IPv4 and IPv6) and kept in order and once" do
    config =
      Map.put(@listen, "expected_peer_addresses", "198.51.100.7, 10.1.2.3/8 ::1 10.0.0.0/8")

    assert {:ok, %{"expected_peer_addresses" => ["10.0.0.0/8", "198.51.100.7/32", "::1/128"]}} =
             TCPSocket.normalize_config(config)
  end

  test "client mode needs no allowlist and keeps none" do
    config = %{@listen | "mode" => "connect"} |> Map.put("expected_peer_addresses", ["10.0.0.1"])
    assert {:ok, normalized} = TCPSocket.normalize_config(config)
    refute Map.has_key?(normalized, "expected_peer_addresses")
  end

  test "the materialized provider profile carries the list to the runtime" do
    config = Map.put(@listen, "expected_peer_addresses", ["203.0.113.0/24"])

    transport = %Transport{
      transport_id: "transport-allowlist",
      mission_id: "mission-allowlist",
      transport_kind: :tcp_socket,
      display_name: "Downlink",
      version: 1,
      origin: :direct,
      configuration: config
    }

    assert {:ok, profile} = TCPSocket.materialize_provider_profile(transport)
    assert profile.configuration["expected_peer_addresses"] == ["203.0.113.0/24"]
    assert profile.configuration["mode"] == "listen"
  end

  test "a provider's delivery profile supplies the list from its egress; one without can't be derived" do
    assert {:ok, %{"expected_peer_addresses" => ["127.0.0.1/32", "::1/128"]}} =
             TCPSocket.from_delivery_profile(
               delivery(%{"source_addresses" => ["127.0.0.1/32", "::1/128"]})
             )

    for egress <- [nil, %{}, %{"source_addresses" => []}] do
      profile = delivery(egress)

      assert {:error, "A listening transport needs its allowed source addresses" <> _} =
               TCPSocket.from_delivery_profile(profile)

      assert TCPSocket.egress_refusal(profile) == :provider_egress_addresses_missing
    end

    # The provider's addresses live in egress, not diagnostics.
    in_diagnostics =
      delivery(nil)
      |> put_in(["diagnostics", "source_addresses"], ["127.0.0.1/32"])

    assert TCPSocket.egress_refusal(in_diagnostics) == :provider_egress_addresses_missing

    assert TCPSocket.egress_refusal(delivery(%{"source_addresses" => ["nope"]})) ==
             :provider_egress_addresses_invalid
  end

  @everyone ["0.0.0.0/0", "::/0", "::ffff:0:0/96", "0::0/0", "::ffff:0.0.0.0/96"]

  test "a whole-family prefix is refused at stage, naming the entry" do
    for entry <- @everyone do
      assert {:error, message} =
               TCPSocket.normalize_config(
                 Map.put(@listen, "expected_peer_addresses", ["10.0.0.0/8", entry])
               )

      assert message == "Allowed source addresses: #{inspect(entry)} allows every address."
    end

    # Narrower mapped and IPv6 ranges are fine.
    assert {:ok, %{"expected_peer_addresses" => ["10.0.0.0/8"]}} =
             TCPSocket.normalize_config(
               Map.put(@listen, "expected_peer_addresses", ["::ffff:10.0.0.0/104"])
             )
  end

  test "a delivery profile whose egress allows every address can't become a listening transport" do
    for entry <- @everyone do
      profile = delivery(%{"source_addresses" => [entry]})
      assert {:error, _message} = TCPSocket.from_delivery_profile(profile)
      assert TCPSocket.egress_refusal(profile) == :provider_egress_addresses_too_broad
    end
  end

  defp delivery(egress) do
    profile = %{
      "direction" => "downlink",
      "state" => "ready",
      "delivery_kind" => "realtime_stream",
      "diagnostics" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => "127.0.0.1",
        "port" => 4100,
        "framing_family" => "ccsds_tm",
        "frame_bytes" => 1115
      }
    }

    if egress, do: Map.put(profile, "egress", egress), else: profile
  end
end
