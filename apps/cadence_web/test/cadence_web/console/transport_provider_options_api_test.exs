defmodule CadenceWeb.Console.TransportProviderOptionsAPITest do
  @moduledoc """
  Comms parity 2: GET …/config/kinds/transport/provider-options. The choices narrow as the form
  fills in, and the preview is domain's derive/3 (the same derivation an apply stores).
  """
  use CadenceWeb.ConnCase, async: false

  import Cadence.ReadyProviderFixtures

  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    provider = persist_ready_provider!(org.organization_id, mission.mission_id)

    %{
      conn: TestFixtures.member_conn(user),
      provider: provider,
      path:
        "/api/console/v1/missions/#{mission.mission_id}/config/kinds/transport/provider-options"
    }
  end

  defp choices(c, query),
    do: c.conn |> get(c.path, query) |> json_response(200) |> Map.fetch!("data")

  test "nothing chosen: the providers only", c do
    id = c.provider.provider_id
    version = c.provider.version

    assert %{
             "providers" => [%{"id" => ^id, "version" => ^version, "name" => "Simulator"}],
             "services" => [],
             "deliveries" => [],
             "preview" => nil,
             "errors" => []
           } = choices(c, %{})
  end

  test "a provider narrows to its services, a service to the deliveries that support it", c do
    assert %{
             "services" => [
               %{"id" => "service-downlink", "version" => 3, "name" => "Realtime telemetry"}
             ],
             "deliveries" => [],
             "preview" => nil
           } = choices(c, %{"provider_id" => c.provider.provider_id})

    assert %{
             "deliveries" => [
               %{"id" => "delivery-cadence", "version" => 7, "name" => "Cadence primary ingress"}
             ],
             "preview" => nil
           } =
             choices(c, %{
               "provider_id" => c.provider.provider_id,
               "service_profile_id" => "service-downlink"
             })
  end

  test "all three chosen: derive/3's preview, as rows", c do
    version = c.provider.version

    assert %{
             "preview" => %{
               "configuration" => configuration,
               "direction_capability" => "inbound",
               "provider_version" => ^version,
               "summary" => summary
             },
             "errors" => []
           } =
             choices(c, %{
               "provider_id" => c.provider.provider_id,
               "service_profile_id" => "service-downlink",
               "delivery_profile_id" => "delivery-cadence"
             })

    assert %{"label" => "Endpoint", "value" => "127.0.0.1:5100"} in summary
    assert Enum.map(summary, & &1["label"]) == ["Endpoint", "Mode", "Framing", "TLS"]
    assert Enum.all?(configuration ++ summary, &is_binary(&1["value"]))
    assert %{"label" => "Endpoint", "value" => "127.0.0.1:5100"} in configuration
  end

  test "a choice that isn't on offer lands on its field", c do
    assert %{"errors" => [%{"path" => "mission_provider_id"}], "services" => []} =
             choices(c, %{"provider_id" => "no-such-provider"})

    assert %{"errors" => [%{"path" => "service_profile_ref"}], "deliveries" => []} =
             choices(c, %{
               "provider_id" => c.provider.provider_id,
               "service_profile_id" => "service-gone"
             })
  end

  test "another organization's mission is not found" do
    stranger = TestFixtures.persist_user!()
    other = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             stranger
             |> TestFixtures.member_conn()
             |> get(
               "/api/console/v1/missions/#{other.mission_id}/config/kinds/transport/provider-options"
             )
             |> json_response(404)
  end
end
