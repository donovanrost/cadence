defmodule CadenceSimulator.Provider.UplinkAttestationTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider.{
    ContactLifecycle,
    Contacts,
    DeliveryProfiles,
    Opportunities,
    Store,
    UplinkAttestation,
    UplinkSessions
  }

  alias CadenceSimulator.TestProviderFixtures

  @challenge String.duplicate("ab", 32)

  setup do
    :ok = Store.clear()
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    {:ok, uplink} = DeliveryProfiles.provision(context.run, uplink_delivery(port))
    contact = booked_with_uplink(context, uplink)

    sessions = UplinkSessions.ensure(%{}, internal(contact), nil)
    {:ok, socket} = :gen_tcp.accept(listener, 2_000)
    {:ok, {ip, peer_port}} = :inet.peername(socket)

    on_exit(fn ->
      UplinkSessions.stop(sessions, contact["id"])
      :gen_tcp.close(listener)
    end)

    %{
      run: context.run,
      contact: contact,
      session: fn _id -> sessions[contact["id"]].pid end,
      sessions: sessions,
      listener: listener,
      peer: "#{:inet.ntoa(ip)}:#{peer_port}"
    }
  end

  test "an active uplinked contact attests its connected peer, signed with the key", c do
    assert {:ok, attestation} = attest(c, "fencing", "provider-secret")

    assert %{"challenge" => @challenge, "purpose" => "fencing", "farm" => "unlocked"} =
             attestation

    assert attestation["peer"] == c.peer

    expected =
      :crypto.mac(:hmac, :sha256, "provider-secret", UplinkAttestation.canonical(attestation))
      |> Base.encode16(case: :lower)

    assert attestation["signature"] == expected
    assert {:ok, other} = attest(c, "fencing", "another-key")
    refute other["signature"] == expected
  end

  test "refuses bad requests, inactive contacts and missing sessions", c do
    assert {:error, {:invalid, _}} =
             UplinkAttestation.attest(c.run, c.contact["id"], %{"challenge" => "short"}, "k",
               session: c.session
             )

    {:ok, _} = ContactLifecycle.update(internal(c.contact), %{"status" => "completed"})
    assert {:error, {:conflict, _}} = attest(c, "fencing", "k")

    {:ok, _} = ContactLifecycle.update(internal(c.contact), %{"status" => "active"})

    assert {:error, {:conflict, "uplink session is not connected"}} =
             UplinkAttestation.attest(
               c.run,
               c.contact["id"],
               %{"challenge" => @challenge, "purpose" => "fencing"},
               "k",
               session: fn _ -> nil end
             )
  end

  test "an armed contact's session reports the CLCW overrides yet attests its FARM unlocked", c do
    id = c.contact["id"]
    UplinkSessions.stop(c.sessions, id)
    :ok = UplinkSessions.arm(id, %{lockout: 1})
    on_exit(fn -> UplinkSessions.disarm(id) end)

    sessions = UplinkSessions.ensure(%{}, internal(c.contact), nil)
    on_exit(fn -> UplinkSessions.stop(sessions, id) end)
    {:ok, _socket} = :gen_tcp.accept(c.listener, 2_000)
    pid = sessions[id].pid

    assert %{overrides: %{lockout: 1}} = :sys.get_state(pid).clcw_injector

    assert {:ok, %{"farm" => "unlocked"}} =
             attest(%{c | session: fn _id -> pid end}, "fencing", "k")

    assert UplinkSessions.disarm(id)
  end

  defp attest(c, purpose, key) do
    UplinkAttestation.attest(
      c.run,
      c.contact["id"],
      %{"challenge" => @challenge, "purpose" => purpose},
      key,
      session: c.session
    )
  end

  defp internal(contact) do
    {:ok, internal} = Contacts.fetch_internal(contact["id"])
    internal
  end

  defp booked_with_uplink(context, uplink) do
    {:ok, %{data: opportunities}} =
      Opportunities.search(context.run, %{
        "spacecraft_refs" => ["SC-001"],
        "ground_station_refs" => [],
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "starts_at" => "2026-07-17T12:00:00Z",
        "ends_at" => "2026-07-17T14:00:00Z",
        "page_size" => 25
      })

    opportunity = Enum.find(opportunities, &(&1["id"] != context.opportunity["id"]))

    request =
      context.request
      |> Map.merge(%{"opportunity_ref" => opportunity["id"], "client_reference" => "attest"})
      |> Map.put("uplink", %{
        "service_profile_ref" => "service-realtime-ttc-uplink",
        "delivery_profile_ref" => uplink["id"]
      })

    {:ok, contact} = Contacts.create(context.run, request, idempotency_key: "attest")
    {:ok, active} = ContactLifecycle.update(internal(contact), %{"status" => "active"})
    active
  end

  defp uplink_delivery(port) do
    %{
      "display_name" => "Test uplink",
      "client_reference" => "attest-uplink",
      "direction" => "uplink",
      "delivery_kind" => "realtime_stream",
      "target" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => "127.0.0.1",
        "port" => port
      },
      "framing" => %{"family" => "ccsds_tc", "mode" => "fixed_size", "frame_bytes" => 32}
    }
  end
end
