defmodule CadenceWeb.ApplicationHostDerivedControllerTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Governance
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
    {:ok, installation} = ApplicationInstallations.install(scope, host, "derived_telemetry")
    prefix = "/api/cadence/application-host/v1/missions/#{mission.mission_id}"

    response =
      get(TestFixtures.member_conn(user), prefix <> "/catalog", %{
        "application_key" => "derived_telemetry"
      })

    catalog = json_response(response, 200)

    %{
      scope: scope,
      host: host,
      installation: installation,
      org: org,
      mission: mission,
      conn: response,
      catalog: catalog,
      prefix: prefix
    }
  end

  test "producer to public editor to authenticated HTTP persists the reviewed expression and replays its receipt",
       c do
    assert [application] = c.catalog["applications"]
    assert application["applicationKey"] == "derived_telemetry"
    assert application["release"]["exposedModule"] == "./DerivedTelemetry"
    assert application["release"]["remoteName"] == "cadence_ops_console"
    assert application["package"]["packageId"] == "cadence.telemetry-applications"
    page = query(c)["trusted_surface"]
    assert page["contract_version"] == 1
    assert page["definitions"]["items"] == []

    script =
      Path.expand(
        "../../../../../frontend/modules/derived-telemetry/src/features/definitions/producer-check.mjs",
        __DIR__
      )

    {output, status} = System.cmd("node", [script, Jason.encode!(page)], stderr_to_stdout: true)
    assert status == 0, output
    [_, encoded] = Regex.run(~r/CADENCE_DERIVED_INPUT=([^\n]+)/, output)
    input = Jason.decode!(encoded)
    assert byte_size(input["expression"]) > 255
    input = Map.put(input, "expression", "HK.voltage" <> String.duplicate("\n", 8_178) <> " + 1")
    assert byte_size(input["expression"]) == 8_192
    action = action(c, input)
    assert {:ok, _} = CadenceWeb.ApplicationActionInput.safe(action)
    saved = send_action(c, action, "derived-save")
    receipt = json_response(saved, 200)
    assert receipt["result"]["version"] == 1
    assert receipt["result"]["expression"] == input["expression"]

    assert {:ok, persisted} =
             Governance.fetch_derived_definition(
               c.org.organization_id,
               c.mission.mission_id,
               receipt["result"]["definitionId"],
               1
             )

    assert persisted.expression == input["expression"]
    assert send_action(c, action, "derived-save").resp_body == saved.resp_body
    stale = send_action(c, action, "derived-stale")
    assert json_response(stale, 422)["code"] == "review_conflict"
    assert send_action(c, action, "derived-stale").resp_body == stale.resp_body

    edit =
      Map.merge(input, %{
        "expected_version" => 1,
        "expected_definition_id" => persisted.derived_definition_id,
        "expression" => "HK.voltage * 5"
      })

    revised = send_action(c, action(c, edit), "derived-edit") |> json_response(200)
    assert revised["result"]["version"] == 2

    assert {:ok, old} =
             Governance.fetch_derived_definition(
               c.org.organization_id,
               c.mission.mission_id,
               persisted.derived_definition_id,
               1
             )

    assert old.expression == input["expression"]

    current =
      query(c, %{"definition" => persisted.derived_definition_id, "version" => "1"})[
        "trusted_surface"
      ]

    assert current["selection"]["inspected"]["version"] == 1
    assert current["selection"]["current"]["version"] == 2
  end

  test "bounds and authorization remain tied to the exact declared action and active installation",
       c do
    input = %{
      "point_id" => "DERIVED.power",
      "point_name" => "Power",
      "expression" => String.duplicate("x", 8193),
      "expected_version" => 0,
      "expected_definition_id" => nil
    }

    assert send_action(c, action(c, input), "too-large")
           |> json_response(422)
           |> Map.fetch!("code") == "invalid_input"

    action = action(c, %{input | "expression" => "HK.voltage * 2"})

    assert send_action(c, Map.put(action, "actionVersion", 2), "wrong-version")
           |> json_response(404)
           |> Map.fetch!("code") == "unsupported_action"

    assert {:ok, _} = ApplicationInstallations.disable(c.scope, c.host, "derived_telemetry")

    assert send_action(c, action, "disabled") |> json_response(404) |> Map.fetch!("code") ==
             "application_unavailable"

    assert Governance.list_derived_definitions(c.org.organization_id, c.mission.mission_id) == []
  end

  defp query(c, params \\ %{}) do
    bridge(c)
    |> post(
      c.prefix <> "/query",
      Jason.encode!(%{
        "applicationKey" => "derived_telemetry",
        "applicationVersion" => 1,
        "surfaceId" => "manage",
        "surfaceVersion" => 1,
        "queryId" => "cadence.derived_telemetry.manage",
        "queryVersion" => 1,
        "scope" => scope(c),
        "params" => params
      })
    )
    |> json_response(200)
  end

  defp action(c, input),
    do: %{
      "applicationKey" => "derived_telemetry",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "actionId" => "save_definition",
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

  defp send_action(c, action, key),
    do:
      bridge(c)
      |> put_req_header("idempotency-key", key)
      |> post(c.prefix <> "/actions", Jason.encode!(action))
end
