defmodule CadenceSimulator.Provider.UplinkLegTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider.{Contacts, DeliveryProfiles, Opportunities, Store}
  alias CadenceSimulator.Provider.{UplinkLeg, UplinkSessions}
  alias CadenceSimulator.TestProviderFixtures

  setup do
    :ok = Store.clear()
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    {:ok, uplink} = DeliveryProfiles.provision(context.run, uplink_delivery(41_002))
    %{context: context, uplink: uplink}
  end

  test "uplink deliveries carry TC framing and support the built-in uplink service", c do
    assert %{"direction" => "uplink", "supported_service_profile_refs" => refs} = c.uplink
    assert "service-realtime-ttc-uplink" in refs
    assert %{"framing_family" => "ccsds_tc", "frame_bytes" => 32} = c.uplink["diagnostics"]

    assert {:error, {:invalid, "framing.family must be ccsds_tc"}} =
             DeliveryProfiles.provision(
               c.context.run,
               put_in(uplink_delivery(41_003), ["framing", "family"], "ccsds_tm")
             )
  end

  test "a contact books its uplink leg and reports it included", c do
    request =
      c
      |> another_request("with-uplink")
      |> Map.put("uplink", %{
        "service_profile_ref" => "service-realtime-ttc-uplink",
        "delivery_profile_ref" => c.uplink["id"]
      })

    assert {:ok, %{"uplink" => leg} = contact} =
             Contacts.create(c.context.run, request, idempotency_key: "with-uplink")

    assert %{"status" => "included", "delivery_profile_ref" => ref} = leg
    assert ref == c.uplink["id"]
    refute Map.has_key?(contact, "uplink_delivery_profile_snapshot")

    {:ok, internal} = Contacts.fetch_internal(contact["id"])
    assert %{host: "127.0.0.1", port: 41_002, tc_frame_size: 32} = UplinkLeg.target(internal)
  end

  test "an uplink leg that names a downlink delivery is refused", c do
    request =
      c
      |> another_request("bad-uplink")
      |> Map.put("uplink", %{
        "service_profile_ref" => "service-realtime-ttc-uplink",
        "delivery_profile_ref" => c.context.delivery_profile["id"]
      })

    assert {:error, {:invalid, "uplink.delivery_profile_ref is not an uplink delivery profile"}} =
             Contacts.create(c.context.run, request, idempotency_key: "bad-uplink")
  end

  test "an included leg starts a COP-1 peer that connects to the uplink listener" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    contact = %{
      "id" => "contact-uplink-session",
      "uplink" => %{"status" => "included"},
      "uplink_delivery_profile_snapshot" => %{
        "target" => %{"host" => "127.0.0.1", "port" => port},
        "framing" => %{"frame_bytes" => 32}
      }
    }

    sessions = UplinkSessions.ensure(%{}, contact, nil)
    assert %{"contact-uplink-session" => %{pid: pid}} = sessions
    assert {:ok, socket} = :gen_tcp.accept(listener, 2_000)

    assert UplinkSessions.ensure(sessions, contact, nil) == sessions
    assert UplinkSessions.stop(sessions, "contact-uplink-session") == %{}
    refute Process.alive?(pid)
    :gen_tcp.close(socket)
    :gen_tcp.close(listener)
  end

  defp another_request(c, reference) do
    {:ok, %{data: opportunities}} =
      Opportunities.search(c.context.run, %{
        "spacecraft_refs" => ["SC-001"],
        "ground_station_refs" => [],
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "starts_at" => "2026-07-17T12:00:00Z",
        "ends_at" => "2026-07-17T14:00:00Z",
        "page_size" => 25
      })

    opportunity =
      Enum.find(opportunities, &(&1["id"] != c.context.opportunity["id"]))

    %{
      c.context.request
      | "opportunity_ref" => opportunity["id"],
        "client_reference" => reference
    }
  end

  defp uplink_delivery(port) do
    %{
      "display_name" => "Test uplink",
      "client_reference" => "test-uplink-#{port}",
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
