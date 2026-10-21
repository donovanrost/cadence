defmodule Cadence.Reads.Comms.FleetValidationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Reads.Comms.Pages
  alias Cadence.{Spacecraft, SpacecraftStore, SpacecraftType, SpacecraftTypeStore}

  @org "org-comms-fleet"
  @mission "mission-comms-fleet"

  @tag timeout: 180_000
  test "overview and validation scan 500 spacecraft, 1000 routes and every installation" do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "fleet-reader"},
      organization_membership: %{lifecycle_state: :active}
    }

    {:ok, profile} =
      SpacecraftTypeStore.persist_spacecraft_type(
        @org,
        SpacecraftType.new(%{
          mission_id: @mission,
          display_name: "Fleet profile",
          downlink_protocol: :tm,
          uplink_protocol: :tc,
          packet_protocol: :space_packet,
          frame_parameters: %{"frame_length" => 1115}
        })
      )

    {:ok, transport} =
      TransportStore.persist_transport(
        @org,
        Transport.new(%{
          mission_id: @mission,
          display_name: "Fleet downlink",
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "host" => "127.0.0.1",
            "port" => 5000,
            "direction_capability" => "inbound",
            "framing_mode" => "raw",
            "tls_enabled" => false
          }
        })
      )

    fleet = Enum.map(1..500, &persist_spacecraft(scope, profile, transport, &1))
    last = List.last(fleet)
    {:ok, _} = SpacecraftStore.update_spacecraft(@org, %{last | scid: nil})

    assert {:ok, findings} = Pages.validation(scope, @mission)
    assert length(findings) > 500
    assert Enum.any?(findings, &(&1.title == "Fleet 500 is missing SCID"))
    refute Enum.any?(findings, &String.contains?(&1.title, "has no Routing Rule"))

    assert {:ok, overview} = Pages.load(scope, @mission, "overview")
    validation = overview["data"]["overview"]["validation"]
    assert validation["status"]["label"] == "#{length(findings)} Findings"
    preview = Enum.flat_map(validation["finding_groups"], & &1["findings"])
    assert length(preview) == 20
    assert Enum.any?(preview, &(&1["id"] == "comms-validation-more-findings"))

    for requested <- [1, 2, 10_000] do
      assert {:ok, payload} =
               Pages.load(scope, @mission, "validation", %{"page" => to_string(requested)})

      data = payload["data"]
      expected_page = min(requested, ceil(length(findings) / 20))
      expected = Enum.slice(findings, (expected_page - 1) * 20, 20)
      assert data["page"] == expected_page
      assert data["total_count"] == length(findings)
      assert data["finding_count"] == length(expected)
      assert Enum.map(data["findings"], & &1["title"]) == Enum.map(expected, & &1.title)
      assert :ok = Pages.validate_bounded_payload(payload)
    end

    assert {:error, :application_surface_bounds_exceeded} =
             Pages.load(scope, @mission, "validation", %{"page" => "10001"})

    assert {:error, _} =
             Pages.load(%{scope | organization_id: "another-org"}, @mission, "validation")
  end

  defp persist_spacecraft(scope, profile, transport, index) do
    suffix = index |> to_string() |> String.pad_leading(3, "0")

    {:ok, craft} =
      SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{
          spacecraft_id: "fleet-#{suffix}",
          mission_id: @mission,
          display_name: "Fleet #{suffix}",
          scid: index,
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        })
      )

    for role <- [:primary, :candidate] do
      {:ok, _} =
        RoutingRuleStore.create_routing_rule(
          @org,
          RoutingRule.new(%{
            mission_id: @mission,
            spacecraft_id: craft.spacecraft_id,
            display_name: "Fleet #{suffix} #{role}",
            purpose_label: "Telemetry",
            direction: :inbound,
            transport_id: transport.transport_id,
            transport_version: transport.version,
            role: role
          })
        )
    end

    {:ok, _} =
      ApplicationInstallations.install(
        scope,
        HostContext.spacecraft(@mission, craft.spacecraft_id),
        "telemetry_decom"
      )

    craft
  end
end
