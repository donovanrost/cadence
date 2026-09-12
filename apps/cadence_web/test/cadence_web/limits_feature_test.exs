defmodule CadenceWeb.LimitsFeatureTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias Cadence.Limits.DefinitionLifecycle
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    host = HostContext.mission(mission.mission_id)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "limits")
    prefix = "/api/cadence/application-host/v1/missions/#{mission.mission_id}"

    response =
      get(TestFixtures.member_conn(user), prefix <> "/catalog", %{"application_key" => "limits"})

    %{
      scope: scope,
      host: host,
      installation: installation,
      org: org,
      mission: mission,
      conn: response,
      catalog: json_response(response, 200),
      prefix: prefix
    }
  end

  test "real producer to public editor to authenticated save activates and replays exact receipt",
       c do
    assert [application] = c.catalog["applications"]
    assert application["applicationKey"] == "limits"
    assert application["package"]["packageId"] == "cadence.mission-assurance"
    assert application["release"]["exposedModule"] == "./Limits"
    doc = query(c, "manage", %{"point" => "HK.voltage", "set" => "FLIGHT"})["trusted_surface"]

    script =
      Path.expand(
        "../../../../frontend/modules/limits-and-alarming/src/features/definitions/producer-consumer-probe.mjs",
        __DIR__
      )

    {out, status} = System.cmd("node", [script, Jason.encode!(doc)], stderr_to_stdout: true)
    assert status == 0, out
    [_, encoded] = Regex.run(~r/CADENCE_LIMITS_INPUT=([^\n]+)/, out)
    input = Jason.decode!(encoded)
    first = send_action(c, input, "limits-first")
    receipt = json_response(first, 200)
    assert receipt["result"]["version"] == 1
    assert send_action(c, input, "limits-first").resp_body == first.resp_body
    assert json_response(send_action(c, input, "limits-stale"), 422)["code"] == "review_conflict"
    id = receipt["result"]["definitionId"]

    assert {:ok, v1} =
             Limits.fetch_limit_definition(c.org.organization_id, c.mission.mission_id, id, 1)

    assert [active] =
             DefinitionLifecycle.list_active_statuses(c.org.organization_id, c.mission.mission_id)

    assert active.limit_definition_version == 1
    review = query(c, "manage", %{"definition" => id})["trusted_surface"]["editor"]["review"]

    edit =
      Map.merge(input, %{
        "expected_definition_id" => review["definition_id"],
        "expected_version" => review["version"],
        "expected_activation_event_id" => review["activation_event_id"],
        "yellow_high" => "30"
      })

    assert json_response(send_action(c, edit, "limits-edit"), 200)["result"]["version"] == 2

    assert {:ok, ^v1} =
             Limits.fetch_limit_definition(c.org.organization_id, c.mission.mission_id, id, 1)

    historical =
      query(c, "activity", %{
        "limit_definition_id" => id,
        "limit_definition_version" => "1",
        "point_id" => "HK.voltage"
      })["trusted_surface"]

    assert historical["selection"]["inspected"]["version"] == 1
    assert historical["selection"]["current"]["version"] == 2
    assert historical["selection"]["active"]["version"] == 2
  end

  test "reactivation changes reviewed evidence even when newest immutable version stays the same",
       c do
    first = json_response(send_action(c, input(), "create"), 200)
    id = first["result"]["definitionId"]

    assert {:ok, v1} =
             Limits.fetch_limit_definition(c.org.organization_id, c.mission.mission_id, id, 1)

    review = query(c, "manage", %{"definition" => id})["trusted_surface"]["editor"]["review"]
    second = reviewed_input(review)
    assert json_response(send_action(c, second, "second"), 200)["result"]["version"] == 2
    reviewed = query(c, "manage", %{"definition" => id})["trusted_surface"]["editor"]["review"]
    assert {:ok, ^v1} = Limits.persist_limit_definition(v1, publish_facts?: false)

    assert json_response(send_action(c, reviewed_input(reviewed), "after-reactivation"), 422)[
             "code"
           ] == "review_conflict"

    assert Limits.limit_definition_history(c.org.organization_id, c.mission.mission_id, id, 1).total_count ==
             2
  end

  test "number bounds, reviewed identity and surface admission fail before persistence", c do
    assert json_response(
             send_action(c, Map.put(input(), "red_high", "1e99"), "large-number"),
             422
           )["code"] == "invalid_number"

    assert json_response(send_action(c, Map.put(input(), "red_high", false), "wrong-type"), 422)[
             "code"
           ] == "invalid_number"

    assert json_response(
             send_action(c, Map.put(input(), "limit_set_name", false), "wrong-set"),
             422
           )[
             "code"
           ] == "invalid_field"

    assert json_response(
             send_action(
               c,
               Map.delete(input(), "expected_activation_event_id"),
               "missing-review"
             ),
             422
           )["code"] == "review_required"

    bad =
      bridge(c)
      |> put_req_header("idempotency-key", "wrong-surface")
      |> post(
        c.prefix <> "/actions",
        Jason.encode!(Map.put(action(c, input()), "surfaceId", "activity"))
      )

    assert bad.status in [400, 403, 404, 422]

    assert Limits.limit_definitions_page(c.org.organization_id, c.mission.mission_id).total_count ==
             0

    assert DefinitionLifecycle.list_active_statuses(c.org.organization_id, c.mission.mission_id) ==
             []

    assert {:ok, _} = ApplicationInstallations.disable(c.scope, c.host, "limits")
    disabled = send_action(c, input(), "disabled")
    assert disabled.status in [403, 404]

    assert Limits.limit_definitions_page(c.org.organization_id, c.mission.mission_id).total_count ==
             0
  end

  test "a valid full definition view keeps all rows within explicit workflow output admission",
       c do
    prefix = String.duplicate("x", 225)
    set = String.duplicate("s", 230)

    for i <- 1..25 do
      definition =
        Cadence.Limits.Definition.new(%{
          mission_id: c.mission.mission_id,
          limit_definition_id: "limit-#{i}",
          point_id: prefix <> "#{i}",
          limit_set_name: set,
          thresholds: %{"yellow_high" => 20}
        })

      assert {:ok, _} = Limits.persist_limit_definition(definition, publish_facts?: false)

      assert {:ok, _} =
               Cadence.Governance.persist_derived_definition(
                 Cadence.DerivedTelemetry.Definition.new(%{
                   mission_id: c.mission.mission_id,
                   derived_definition_id: "derived-#{i}",
                   point_id: prefix <> ".derived#{i}",
                   point_name: prefix,
                   expression: "HK.voltage * 2"
                 })
               )
    end

    assert {:ok, first} =
             Limits.fetch_limit_definition(
               c.org.organization_id,
               c.mission.mission_id,
               "limit-1",
               1
             )

    for version <- 2..25,
        do:
          assert(
            {:ok, _} =
              Limits.persist_limit_definition(%{first | version: version}, publish_facts?: false)
          )

    params = %{"definition" => "limit-1", "q" => prefix, "points_q" => prefix}

    request = %Cadence.Applications.SurfaceQueryRequest{
      application_key: "limits",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      query_id: "cadence.limits.manage",
      query_version: 1,
      params: params
    }

    assert {:ok, %{"data" => data}} =
             Cadence.Reads.ApplicationSurfaces.Limits.load(c.scope, c.host, request)

    assert byte_size(Jason.encode!(data)) > 65_536
    transported = query(c, "manage", params)["trusted_surface"]
    assert transported == data
    assert length(transported["definitions"]["items"]) == 25
    assert length(transported["selection"]["history"]["items"]) == 25
    assert length(transported["points"]["items"]) == 25
  end

  defp input,
    do: %{
      "point_id" => "HK.voltage",
      "limit_set_name" => "FLIGHT",
      "red_low" => "",
      "yellow_low" => "",
      "yellow_high" => "31.5",
      "red_high" => "34",
      "expected_definition_id" => nil,
      "expected_version" => 0,
      "expected_activation_event_id" => nil
    }

  defp reviewed_input(r),
    do:
      Map.merge(input(), %{
        "expected_definition_id" => r["definition_id"],
        "expected_version" => r["version"],
        "expected_activation_event_id" => r["activation_event_id"]
      })

  defp query(c, surface, params),
    do:
      bridge(c)
      |> post(
        c.prefix <> "/query",
        Jason.encode!(%{
          "applicationKey" => "limits",
          "applicationVersion" => 1,
          "surfaceId" => surface,
          "surfaceVersion" => 1,
          "queryId" => "cadence.limits.#{surface}",
          "queryVersion" => 1,
          "scope" => scope(c),
          "params" => params
        })
      )
      |> json_response(200)

  defp action(c, input),
    do: %{
      "applicationKey" => "limits",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "actionId" => "save_limit_definition",
      "scope" => scope(c),
      "input" => input
    }

  defp scope(c),
    do: %{
      "organizationId" => c.org.organization_id,
      "missionId" => c.mission.mission_id,
      "spacecraftId" => nil
    }

  defp bridge(c),
    do:
      c.conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cadence-poc-session", c.catalog["session"]["sessionId"])
      |> put_req_header("x-csrf-token", c.catalog["session"]["csrfToken"])

  defp send_action(c, input, key),
    do:
      bridge(c)
      |> put_req_header("idempotency-key", key)
      |> post(c.prefix <> "/actions", Jason.encode!(action(c, input)))
end
