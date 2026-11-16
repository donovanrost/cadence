defmodule Cadence.Applications.CommsActionProviderTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, Comms, HostContext}
  alias Cadence.Applications.Comms.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Comms.GroundStationStore
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.Management.CommunicationsSetup
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
     scope: %Scope{
       actor_kind: :user,
       organization_id: organization_id,
       mission_id: mission_id,
       user: %{user_id: "comms-setup-operator"},
       organization_membership: %{lifecycle_state: :active}
     },
     host_context: HostContext.mission(mission_id)}
  end

  test "validates each Comms form through its exact surface and payload shape", context do
    for {surface_id, payload} <- form_payloads(context) do
      assert {:ok, %{"valid" => true}} = execute(context, "validate", surface_id, payload)
    end
  end

  test "saves the routing form and returns navigation only after persistence", context do
    transport = transport!(context)

    assert {:ok, routing_receipt} =
             execute(context, "save", "routing_new", %{
               "routing_rule" => %{
                 "display_name" => "Aurora downlink",
                 "purpose_label" => "Live telemetry",
                 "spacecraft_id" => context.spacecraft_id,
                 "transport_ref" => "#{transport.transport_id}:#{transport.version}",
                 "direction" => "inbound",
                 "role" => "primary"
               }
             })

    assert routing_receipt["navigation"]["kind"] == "navigate"
  end

  # Host-action sweep batch 1: transports and ground stations are written only through the
  # console's change sets; their forms bind nothing and the provider refuses them.
  test "refuses the removed transport and ground station forms", context do
    for surface_id <- ~w(transport_new ground_station_new ground_station_edit),
        action_id <- ["validate", "save"] do
      assert {:error, :unsupported_application_action} =
               execute(context, action_id, surface_id, %{"transport" => %{}})
    end

    assert TransportStore.list_transports(context.organization_id, context.mission_id) == []

    assert GroundStationStore.list_ground_stations(context.organization_id, context.mission_id) ==
             []
  end

  test "rejects omitted and wrong-version shared form envelopes", context do
    payload = %{"routing_rule" => %{"display_name" => "Aurora downlink"}}

    for action_id <- ["validate", "save"] do
      assert {:error, :unsupported_application_action} =
               execute_without_surface(context, action_id, payload)

      assert {:error, :unsupported_application_action} =
               execute(context, action_id, "routing_new", payload, surface_version: 2)
    end
  end

  test "rejects non-exact form payloads", context do
    for {surface_id, payload} <- form_payloads(context) do
      payload = Map.put(payload, "unexpected", %{})

      assert {:error, :invalid_application_request} =
               execute(context, "validate", surface_id, payload)

      assert {:error, :invalid_application_request} =
               execute(context, "save", surface_id, payload)
    end

    assert {:error, :invalid_application_request} =
             execute(context, "validate", "routing_new", %{"transport" => %{}})
  end

  test "setup commands authorize without relying on a frontend adapter", context do
    for {form, payload} <- form_payloads(context),
        event <- ["validate", "save"],
        scope <- [
          %Scope{organization_id: context.organization_id},
          %{context.scope | user: nil},
          %{context.scope | organization_membership: nil},
          %{context.scope | mission_id: "foreign"},
          %{context.scope | organization_id: "foreign"}
        ] do
      assert {:error, _} =
               CommunicationsSetup.execute(scope, context.mission_id, form, event, payload)
    end

    assert TransportStore.list_transports(context.organization_id, context.mission_id) == []

    assert GroundStationStore.list_ground_stations(context.organization_id, context.mission_id) ==
             []
  end

  test "setup rejects non-text and oversized nested input before validation or effects",
       context do
    for payload <- [
          nil,
          [],
          %{"routing_rule" => %{"direction" => 5000}},
          %{"routing_rule" => %{"display_name" => String.duplicate("x", 8193)}},
          %{"routing_rule" => %{"display_name" => <<255>>}}
        ] do
      for event <- ["validate", "save"] do
        assert {:error, _} =
                 CommunicationsSetup.execute(
                   context.scope,
                   context.mission_id,
                   "routing_new",
                   event,
                   payload
                 )
      end
    end
  end

  test "domain and legacy adapters share validation output", context do
    for {form, payload} <- form_payloads(context) do
      assert CommunicationsSetup.execute(
               context.scope,
               context.mission_id,
               form,
               "validate",
               payload
             ) ==
               execute(context, "validate", form, payload)
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
             {"routing_new", ["validate", "save"]}
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
       }}
    ]
  end

  defp transport!(context) do
    {:ok, transport} =
      TransportStore.persist_transport(
        context.organization_id,
        Transport.new(%{
          mission_id: context.mission_id,
          display_name: "Lab TCP",
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    transport
  end
end
