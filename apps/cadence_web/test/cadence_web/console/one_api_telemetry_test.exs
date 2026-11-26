defmodule CadenceWeb.Console.OneAPITelemetryTest do
  @moduledoc """
  #780 (#747, one public API): telemetry's old bearer endpoints are gone and what replaced them
  on the console API answers a person's session and refuses a service identity.

  * mission health  -> `GET fleet`; mission events -> `GET events`;
  * telemetry latest and history -> `POST telemetry/latest`, `GET telemetry/points/:id/history`;
  * `POST dev/space_packets` and `POST dev/tm_frames` ported, mounted in dev and test only.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.ServiceIdentity
  alias CadenceWeb.Console.DevIngestRoutes
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    ControlPlaneApiFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    # Ingest needs an active binding set.
    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        org.organization_id,
        mission.mission_id,
        "read-models",
        1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    {:ok, %{api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-one-api-#{System.unique_integer([:positive])}",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "One API automation",
          capabilities: [:mission_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: org.organization_id,
          user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
        }
      )

    %{
      user: user,
      token: token,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  @window "from=2023-11-15T00:00:00Z&to=2023-11-16T00:00:00Z"

  defp packet_hex,
    do:
      42
      |> ControlPlaneApiFixtures.build_space_packet(3, <<12.5::float-32, 1::size(1), 0::size(7)>>)
      |> Base.encode16(case: :lower)

  defp frame_hex,
    do:
      42
      |> ControlPlaneApiFixtures.build_tm_single_frame(
        4,
        <<12.5::float-32, 1::size(1), 0::size(7)>>,
        17
      )
      |> Base.encode16(case: :lower)

  # {name, method, path under the mission, body}
  defp endpoints, do: read_endpoints() ++ dev_endpoints()

  defp read_endpoints do
    [
      {"fleet", :get, "/fleet", nil},
      {"events", :get, "/events?" <> @window, nil},
      {"telemetry latest", :post, "/telemetry/latest",
       %{"point_ids" => ["HK.counter"], "spacecraft_ids" => ["spacecraft-001"]}},
      {"point history", :get, "/telemetry/points/HK.counter/history?" <> @window, nil}
    ]
  end

  defp dev_endpoints do
    [
      {"dev space packet", :post, "/dev/space_packets",
       %{"space_packet" => %{"source_ref" => "station-a", "packet_hex" => packet_hex()}}},
      {"dev tm frame", :post, "/dev/tm_frames",
       %{
         "tm_frame" => %{
           "source_ref" => "station-b",
           "frame_hex" => frame_hex(),
           "frame_size" => 17,
           "ocf_length" => 0
         }
       }}
    ]
  end

  defp call(conn, :get, path, _body), do: get(conn, path)
  defp call(conn, :post, path, body), do: post(conn, path, body || %{})

  test "a person's session reaches every moved read", c do
    for {name, method, path, body} <- read_endpoints() do
      conn = c.user |> TestFixtures.member_conn() |> call(method, c.base <> path, body)
      assert conn.status == 200, "#{name} answered #{conn.status}: #{conn.resp_body}"
      assert %{"data" => _} = Jason.decode!(conn.resp_body)
    end
  end

  test "a service identity is refused on every moved endpoint, and nothing is ingested", c do
    for {name, method, path, body} <- endpoints() do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> c.token)
        |> call(method, c.base <> path, body)

      assert %{"error" => %{"code" => "service_not_allowed"}} = json_response(conn, 403),
             "#{name} let a service through"
    end
  end

  # The success path against an activated Mission Model is in ControlPlaneMissionDataApiTest.
  test "a person's session reaches the real ingest on the dev routes", c do
    for {name, method, path, body} <- dev_endpoints() do
      conn = c.user |> TestFixtures.member_conn() |> call(method, c.base <> path, body)

      # No Mission Model is active for this mission, and the ingest says so: it ran.
      assert %{"error" => %{"code" => "invalid_params", "details" => %{"ingest" => ingest}}} =
               json_response(conn, 422),
             name

      assert ingest =~ "no_active_binding_set"
    end
  end

  test "a malformed dev ingest is a 422 problem, never a crash", c do
    member = fn -> TestFixtures.member_conn(c.user) end

    assert %{"error" => %{"code" => "invalid_params"}} =
             member.() |> post(c.base <> "/dev/space_packets", %{}) |> json_response(422)

    assert %{"error" => %{"code" => "invalid_params"}} =
             member.()
             |> post(c.base <> "/dev/tm_frames", %{"tm_frame" => %{"frame_hex" => "zz"}})
             |> json_response(422)
  end

  test "the old bearer routes are gone" do
    paths =
      for route <- CadenceWeb.Router.__routes__(), do: route.path

    for gone <- ~w(mission_health mission_events telemetry/latest dev/tm_frames dev/space_packets) do
      refute Enum.any?(paths, &(String.starts_with?(&1, "/api/organizations/") and &1 =~ gone)),
             "an old /api/organizations route for #{gone} is still mounted"
    end
  end

  describe "the dev routes are dev and test only" do
    defmodule ProdShapeRouter do
      use Phoenix.Router
      require CadenceWeb.Console.DevIngestRoutes, as: DevIngestRoutes

      scope "/api/v1/missions/:mission_id", CadenceWeb.Console do
        DevIngestRoutes.mount(false)
      end
    end

    defmodule DevShapeRouter do
      use Phoenix.Router
      require CadenceWeb.Console.DevIngestRoutes, as: DevIngestRoutes

      scope "/api/v1/missions/:mission_id", CadenceWeb.Console do
        DevIngestRoutes.mount(true)
      end
    end

    test "a router built the way prod is has no dev route; one built for dev has both" do
      assert Phoenix.Router.routes(ProdShapeRouter) == []

      assert Phoenix.Router.routes(DevShapeRouter) |> Enum.map(& &1.path) |> Enum.sort() == [
               "/api/v1/missions/:mission_id/dev/space_packets",
               "/api/v1/missions/:mission_id/dev/tm_frames"
             ]

      assert DevIngestRoutes.__info__(:module) == DevIngestRoutes
    end

    test "prod config never turns the flag on, and the shared config leaves it off" do
      for file <- ["config/config.exs", "config/prod.exs", "config/runtime.exs"] do
        refute File.read!(Path.expand(file, File.cwd!())) =~ "dev_ingest_routes, true",
               "#{file} enables the dev ingest routes"
      end

      assert Application.get_env(:cadence_web, :dev_ingest_routes) == true
    end
  end
end
