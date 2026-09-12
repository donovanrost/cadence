defmodule Cadence.Applications.CommsTransportSetupTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary, SurfaceQueryRequest}
  alias Cadence.Applications.Comms.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Comms.TransportStore
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.Reads.ApplicationSurfaces.Comms

  @features Path.expand(
              "../../../../../frontend/modules/communications/src/features/transports",
              __DIR__
            )

  setup do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    org = "org-provider-setup-" <> suffix
    mission = "mission-provider-setup-" <> suffix
    persist_mission_scope(org, mission)
    provider = provider!(org, mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: org,
      mission_id: mission,
      user: %{user_id: "transport-setup-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{org: org, mission: mission, scope: scope, provider: provider}
  end

  test "partial choices and derived preview satisfy the real consumer before exact-version persistence",
       c do
    request = %SurfaceQueryRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: "transport_new",
      surface_version: 1,
      query_id: "cadence.comms.transport_new",
      query_version: 1,
      params: %{}
    }

    assert {:ok, form} = Comms.load(c.scope, HostContext.mission(c.mission), request)
    assert [%{"id" => id, "version" => version}] = form["data"]["form"]["provider"]["versions"]
    assert id == c.provider.provider_id
    assert version == c.provider.version
    consumer!("form-validation.ts", "readForm", form, %{missionId: c.mission})

    partial = draft(c, "", "")
    assert {:ok, choices} = execute(c, "validate", partial)
    refute choices["valid"]
    assert [%{"value" => service}] = choices["provider_setup"]["services"]
    assert choices["provider_setup"]["deliveries"] == []
    consumer!("validation-receipt.ts", "admitValidation", choices, partial)

    service_draft = put_in(partial, ["transport", "service_profile_id"], service)
    assert {:ok, choices} = execute(c, "validate", service_draft)
    assert [%{"value" => delivery}] = choices["provider_setup"]["deliveries"]
    consumer!("validation-receipt.ts", "admitValidation", choices, service_draft)

    complete = put_in(service_draft, ["transport", "delivery_profile_id"], delivery)
    assert {:ok, preview} = execute(c, "validate", complete)
    assert preview["valid"]
    assert preview["transport_review"]["endpoint"] == "127.0.0.1:5100"
    assert :ok = JSONBoundary.validate(preview)
    refute Jason.encode!(preview) =~ "must-not-expose"
    consumer!("validation-receipt.ts", "admitValidation", preview, complete)
    assert TransportStore.list_transports(c.org, c.mission) == []

    forged =
      update_in(
        complete,
        ["transport"],
        &Map.merge(&1, %{"host" => "must-not-win", "port" => "9999"})
      )

    assert {:ok, receipt} = execute(c, "save", forged)

    assert {:ok, transport} =
             TransportStore.fetch_transport(c.org, c.mission, receipt["transportId"])

    assert transport.mission_provider_version == c.provider.version
    assert transport.service_profile_ref == %{"id" => "service", "version" => 3}
    assert transport.delivery_profile_ref == %{"id" => "delivery", "version" => 7}
    assert transport.configuration["port"] == 5100
    assert transport.configuration["host"] == "127.0.0.1"
    assert transport.configuration["fixed_message_bytes"] == 1115
  end

  test "save rejects incomplete, cross-scope, wrong-version and incompatible selections", c do
    valid = draft(c, token("service", 3), token("delivery", 7))

    for invalid <- [
          draft(c, "", ""),
          put_in(valid, ["transport", "mission_provider_id"], "other-provider"),
          put_in(valid, ["transport", "mission_provider_version"], "999"),
          put_in(valid, ["transport", "service_profile_id"], token("service", 4)),
          put_in(valid, ["transport", "delivery_profile_id"], token("incompatible", 1)),
          put_in(valid, ["transport", "display_name"], "")
        ] do
      assert {:error, _} = execute(c, "save", invalid)
    end

    other = "another-mission"
    persist_mission_scope(c.org, other)
    assert {:error, _} = execute(%{c | mission: other}, "validate", valid)
    assert TransportStore.list_transports(c.org, c.mission) == []
    assert TransportStore.list_transports(c.org, other) == []
  end

  test "a provider version change between preview and save cannot silently repin the draft", c do
    input = draft(c, token("service", 3), token("delivery", 7))
    assert {:ok, %{"valid" => true}} = execute(c, "validate", input)

    assert {:ok, _} =
             MissionProviders.version_provider(c.org, c.mission, c.provider.provider_id, %{
               display_name: "Updated"
             })

    assert {:error, _} = execute(c, "save", input)
    assert TransportStore.list_transports(c.org, c.mission) == []
  end

  defp execute(c, action, params) do
    ActionProvider.execute(c.scope, HostContext.mission(c.mission), %ActionRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: "transport_new",
      surface_version: 1,
      action_id: action,
      params: params
    })
  end

  defp draft(c, service, delivery),
    do: %{
      "transport" => %{
        "display_name" => "Provider downlink",
        "origin" => "provider_managed",
        "transport_kind" => "tcp_socket",
        "mission_provider_id" => c.provider.provider_id,
        "mission_provider_version" => Integer.to_string(c.provider.version),
        "service_profile_id" => service,
        "delivery_profile_id" => delivery
      }
    }

  defp token(id, version),
    do:
      %{"id" => id, "version" => version} |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp consumer!(file, function, payload, context) do
    path = Path.join(@features, file)

    script =
      "import {#{function}} from #{Jason.encode!(path)}; #{function}(JSON.parse(process.argv[1]), JSON.parse(process.argv[2]));"

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        [
          "--no-warnings",
          "--input-type=module",
          "-e",
          script,
          Jason.encode!(payload),
          Jason.encode!(context)
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp provider!(org, mission) do
    delivery = %{
      "id" => "delivery",
      "version" => 7,
      "display_name" => "Primary ingress",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "state" => "ready",
      "supported_service_profile_refs" => ["service"],
      "diagnostics" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => "127.0.0.1",
        "port" => 5100,
        "framing_family" => "ccsds_tm",
        "frame_bytes" => 1115,
        "endpoint_health" => "healthy",
        "api_token" => "must-not-expose"
      }
    }

    provider =
      MissionProvider.new(%{
        mission_id: mission,
        display_name: "Simulator",
        provider_type: :simulator,
        base_url: "http://127.0.0.1:4101",
        credential_ref: "config://simulator",
        environment_ref: "local",
        last_validated_at: ~U[2026-09-07 00:00:00.000000Z],
        last_synced_at: ~U[2026-09-07 00:00:00.000000Z],
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: %{
          "service_profiles" => %{
            "items" => [
              %{
                "id" => "service",
                "version" => 3,
                "display_name" => "Telemetry",
                "direction" => "downlink",
                "state" => "active"
              },
              %{
                "id" => "uplink",
                "version" => 1,
                "display_name" => "Uplink",
                "direction" => "uplink",
                "state" => "active"
              }
            ]
          },
          "delivery_profiles" => %{
            "items" => [
              delivery,
              %{
                delivery
                | "id" => "incompatible",
                  "version" => 1,
                  "supported_service_profile_refs" => ["unrelated"]
              }
            ]
          }
        }
      })

    {:ok, persisted} = MissionProviders.persist_provider(org, provider)
    persisted
  end
end
