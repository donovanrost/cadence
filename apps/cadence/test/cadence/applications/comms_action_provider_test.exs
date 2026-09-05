defmodule Cadence.Applications.CommsActionProviderTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, Comms, HostContext}
  alias Cadence.Applications.Comms.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Comms.GroundStationStore
  alias Cadence.Spacecraft

  setup do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    organization_id = "org-comms-actions-" <> suffix
    mission_id = "mission-comms-actions-" <> suffix

    persist_mission_scope(organization_id, mission_id)

    spacecraft = Spacecraft.new(%{mission_id: mission_id, display_name: "Aurora"})

    assert {:ok, spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok,
     organization_id: organization_id,
     mission_id: mission_id,
     spacecraft_id: spacecraft.spacecraft_id,
     scope: %Scope{organization_id: organization_id},
     host_context: HostContext.mission(mission_id)}
  end

  test "validates each Comms form through its exact surface and payload shape", context do
    for {surface_id, payload} <- form_payloads(context) do
      assert {:ok, %{"valid" => true}} = execute(context, "validate", surface_id, payload)
    end
  end

  test "saves each Comms form and returns navigation only after persistence", context do
    assert {:ok, transport_receipt} =
             execute(context, "save", "transport_new", %{
               "transport" => %{
                 "display_name" => "Lab TCP",
                 "origin" => "direct",
                 "transport_kind" => "tcp_socket",
                 "tcp_mode" => "listen",
                 "direction_capability" => "inbound",
                 "host" => "0.0.0.0",
                 "port" => "5000",
                 "framing_mode" => "raw",
                 "tls_enabled" => "false"
               }
             })

    assert transport_receipt["navigation"]["kind"] == "navigate"
    transport_id = transport_receipt["transportId"]

    assert {:ok, routing_receipt} =
             execute(context, "save", "routing_new", %{
               "routing_rule" => %{
                 "display_name" => "Aurora downlink",
                 "purpose_label" => "Live telemetry",
                 "spacecraft_id" => context.spacecraft_id,
                 "transport_ref" => "#{transport_id}:1",
                 "direction" => "inbound",
                 "role" => "primary"
               }
             })

    assert routing_receipt["navigation"]["kind"] == "navigate"

    assert {:ok, ground_station_receipt} =
             execute(context, "save", "ground_station_new", %{
               "ground_station" => %{
                 "ground_station_id" => "dss-14",
                 "display_name" => "Goldstone",
                 "provider" => "DSN",
                 "region" => "goldstone",
                 "metadata_json" => "{}"
               }
             })

    assert ground_station_receipt["navigation"]["kind"] == "navigate"

    assert {:ok, edit_receipt} =
             execute(context, "save", "ground_station_edit", %{
               "ground_station" => %{
                 "ground_station_id" => "dss-14",
                 "display_name" => "Goldstone Updated",
                 "provider" => "DSN",
                 "region" => "goldstone",
                 "metadata_json" => ~s({"antenna_diameter_m":70})
               }
             })

    assert edit_receipt["navigation"]["kind"] == "navigate"

    assert {:ok, station} =
             GroundStationStore.fetch_ground_station(
               context.organization_id,
               context.mission_id,
               "dss-14"
             )

    assert station.display_name == "Goldstone Updated"
  end

  test "rejects omitted and wrong-version shared form envelopes", context do
    payload = %{"transport" => %{"display_name" => "Lab TCP"}}

    for action_id <- ["validate", "save"] do
      assert {:error, :unsupported_application_action} =
               execute_without_surface(context, action_id, payload)

      assert {:error, :unsupported_application_action} =
               execute(context, action_id, "transport_new", payload, surface_version: 2)
    end
  end

  test "rejects cross-surface and non-exact form payloads", context do
    payloads = form_payloads(context)

    for {surface_id, payload} <- payloads,
        {other_surface_id, other_payload} <- payloads,
        payload_key(payload) != payload_key(other_payload) do
      assert {:error, :invalid_application_request} =
               execute(context, "validate", surface_id, other_payload)

      assert {:error, :invalid_application_request} =
               execute(context, "save", surface_id, other_payload)

      assert other_surface_id != surface_id
    end

    for {surface_id, payload} <- payloads do
      payload = Map.put(payload, "unexpected", %{})

      assert {:error, :invalid_application_request} =
               execute(context, "validate", surface_id, payload)

      assert {:error, :invalid_application_request} =
               execute(context, "save", surface_id, payload)
    end
  end

  test "keeps form action effects and surface declarations exact" do
    actions = Map.new(Comms.definition().actions, &{&1.action_id, &1})

    assert actions["validate"].effect == :none
    assert actions["save"].effect == :durable

    assert Enum.map(Comms.definition().surfaces, fn surface ->
             {surface.surface_id, surface.actions}
           end)
           |> Enum.filter(fn {_surface_id, actions} -> actions != [] end) == [
             {"provider_new", ["create_provider"]},
             {"provider_show", ["validate_provider", "sync_provider", "archive_provider"]},
             {"transport_new", ["validate", "save"]},
             {"routing_new", ["validate", "save"]},
             {"ground_station_new", ["validate", "save"]},
             {"ground_station_edit", ["validate", "save"]}
           ]
  end

  defp execute(context, action_id, surface_id, payload, opts \\ []) do
    request = %ActionRequest{
      application_key: "comms",
      application_version: 1,
      action_id: action_id,
      surface_id: surface_id,
      surface_version: Keyword.get(opts, :surface_version, 1),
      params: payload
    }

    ActionProvider.execute(context.scope, context.host_context, request)
  end

  defp execute_without_surface(context, action_id, payload) do
    request = %ActionRequest{
      application_key: "comms",
      application_version: 1,
      action_id: action_id,
      params: payload
    }

    ActionProvider.execute(context.scope, context.host_context, request)
  end

  defp form_payloads(context) do
    [
      {"transport_new",
       %{
         "transport" => %{
           "display_name" => "Lab TCP",
           "transport_kind" => "tcp_socket"
         }
       }},
      {"routing_new",
       %{
         "routing_rule" => %{
           "display_name" => "Aurora downlink",
           "purpose_label" => "Live telemetry",
           "spacecraft_id" => context.spacecraft_id,
           "transport_ref" => "transport-1:1",
           "direction" => "inbound",
           "role" => "primary"
         }
       }},
      {"ground_station_new", ground_station_payload()},
      {"ground_station_edit", ground_station_payload()}
    ]
  end

  defp ground_station_payload do
    %{
      "ground_station" => %{
        "ground_station_id" => "dss-14",
        "display_name" => "Goldstone",
        "provider" => "DSN",
        "region" => "goldstone",
        "metadata_json" => "{}"
      }
    }
  end

  defp payload_key(payload), do: payload |> Map.keys() |> List.first()
end
