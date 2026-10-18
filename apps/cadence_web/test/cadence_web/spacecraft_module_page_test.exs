defmodule CadenceWeb.SpacecraftModulePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Reads.ApplicationSurfaces.Spacecraft, as: LegacySpacecraft
  alias Cadence.Reads.Comms.SpacecraftRouting
  alias CadenceWeb.{HostTransportTestSupport, TestFixtures}

  @validator Path.expand(
               "../../../../frontend/modules/communications/src/features/routing/spacecraft-routing.validation.ts",
               __DIR__
             )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

    %{
      conn: TestFixtures.member_conn(user),
      user: user,
      org: org,
      mission: mission,
      spacecraft: spacecraft,
      path: "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
    }
  end

  test "host composes the Communications page without an application installation or release",
       context do
    %{conn: conn, path: path, mission: mission, spacecraft: spacecraft} = context
    {:ok, view, _} = live(conn, path)

    HostTransportTestSupport.assert_context(view, %{
      "kind" => "spacecraft_module",
      "mission_id" => mission.mission_id,
      "spacecraft_id" => spacecraft.spacecraft_id,
      "host_scope" => "spacecraft",
      "query_params" => %{}
    })

    empty = contribution(view)
    assert empty["data"]["page"]["rows"] == []
    assert_consumer(empty)
    {rule, transport} = persist_rule!(context)

    assert {:ok, _} =
             TransportStore.persist_transport(context.org.organization_id, %{
               transport
               | version: 2,
                 display_name: "Latest transport name"
             })

    render_hook(view, "host:context", %{"path" => path})
    snapshot = contribution(view)
    assert_consumer(snapshot)

    assert [%{"id" => id, "transport_name" => "Pinned transport name", "transport_version" => 1}] =
             snapshot["data"]["page"]["rows"]

    assert id == "spacecraft-routing-rule-#{rule.routing_rule_id}"

    assert snapshot["data"]["page"]["new_rule"]["href"] ==
             "/missions/#{mission.mission_id}/comms/routing/new?spacecraft_id=#{spacecraft.spacecraft_id}"
  end

  test "path identity wins over query parameters and other spacecraft rows stay isolated",
       context do
    persist_rule!(context)
    other = TestFixtures.persist_spacecraft!(context.mission, display_name: "Other spacecraft")
    {:ok, view, _} = live(context.conn, context.path)

    render_hook(view, "host:context", %{
      "path" => context.path <> "?spacecraft_id=#{other.spacecraft_id}&mission_id=foreign"
    })

    snapshot = contribution(view)
    assert snapshot["context"]["spacecraftId"] == context.spacecraft.spacecraft_id
    assert length(snapshot["data"]["page"]["rows"]) == 1

    render_hook(view, "host:context", %{
      "path" =>
        "/missions/#{context.mission.mission_id}/spacecraft/#{other.spacecraft_id}/routing"
    })

    assert contribution(view)["data"]["page"]["rows"] == []

    render_hook(view, "host:context", %{
      "path" => "/missions/#{context.mission.mission_id}/spacecraft"
    })

    assert contribution(view) == nil
  end

  test "legacy surface delegates to the same scoped producer", context do
    persist_rule!(context)

    scope = %Scope{
      actor_kind: :user,
      organization_id: context.org.organization_id,
      mission_id: context.mission.mission_id,
      user: %{user_id: context.user.user_id},
      organization_membership: %{lifecycle_state: :active}
    }

    assert {:ok, data} =
             SpacecraftRouting.load(
               scope,
               context.mission.mission_id,
               context.spacecraft.spacecraft_id
             )

    host = HostContext.spacecraft(context.mission.mission_id, context.spacecraft.spacecraft_id)

    request = %SurfaceQueryRequest{
      application_key: "spacecraft",
      application_version: 1,
      surface_id: "routing",
      surface_version: 1,
      query_id: "cadence.spacecraft.routing",
      query_version: 1,
      params: %{}
    }

    assert {:ok, legacy} = LegacySpacecraft.load(scope, host, request)
    assert legacy["data"] == data

    assert {:error, _} =
             SpacecraftRouting.load(
               %{scope | mission_id: "foreign"},
               context.mission.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert {:error, _} =
             SpacecraftRouting.load(
               %{scope | organization_id: "foreign"},
               context.mission.mission_id,
               context.spacecraft.spacecraft_id
             )
  end

  test "unauthenticated, cross-organization and revoked-session reads remain rejected", context do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), context.path)
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org)
    other_spacecraft = TestFixtures.persist_spacecraft!(other_mission)

    assert {:error, {:redirect, _}} =
             live(
               context.conn,
               "/missions/#{other_mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}/routing"
             )

    {:ok, view, _} = live(context.conn, context.path)
    :ok = Cadence.Auth.revoke_user_session(get_session(context.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => context.path})
    assert_redirect(view, "/sign-in")
  end

  defp contribution(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "spacecraft_module_page"
      ]

  defp persist_rule!(context) do
    mission = context.mission

    {:ok, transport} =
      TransportStore.persist_transport(
        mission.organization_id,
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: "Pinned transport name",
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

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        mission.organization_id,
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: context.spacecraft.spacecraft_id,
          display_name: "Primary downlink",
          purpose_label: "Telemetry",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )

    {rule, transport}
  end

  defp assert_consumer(snapshot) do
    assert snapshot["id"] == "comms.spacecraft-routing"
    assert snapshot["slot"] == "spacecraft.page"
    assert snapshot["version"] == 1
    assert snapshot["status"] == "ready"

    script = """
    import {readSpacecraftRouting} from #{Jason.encode!(@validator)};
    readSpacecraftRouting(JSON.parse(process.argv[1]), JSON.parse(process.argv[2]));
    """

    node = System.find_executable("node") || flunk("Node required for routing contract")

    {output, status} =
      System.cmd(
        node,
        [
          "--no-warnings",
          "--input-type=module",
          "-e",
          script,
          Jason.encode!(snapshot["data"]),
          Jason.encode!(snapshot["context"])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
