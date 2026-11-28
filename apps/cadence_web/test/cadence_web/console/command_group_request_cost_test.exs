defmodule CadenceWeb.Console.CommandGroupRequestCostTest do
  @moduledoc """
  #1051: what one request of the command group flow costs, counted as the queries of the request
  (the Repo's telemetry in the test's own process), for a 15-target group on a 50-craft fleet
  activation. The ceilings are a few over today's counts; the counts don't move with the number of
  members or craft (`Cadence.Commanding.Groups.FlatQueriesTest` guards that), so what a ceiling
  catches is a stage that starts reading again what an earlier one read. GO answers with the
  decision summary, not the full show.
  """
  use CadenceWeb.ConnCase, async: false

  @fleet 50
  @targets 15
  @ceilings %{preflight: 50, create: 85, go: 78}

  alias Cadence.{CommandAuthoringFixtures, ExactCommandAuthoringFixtures}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    requester = TestFixtures.persist_user!(display_name: "Requester")
    approver = TestFixtures.persist_user!(display_name: "Approver")
    TestFixtures.grant_membership!(requester, org, role: :organization_admin)
    TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    total = @fleet
    targets_n = @targets

    crafts =
      for i <- 1..total do
        craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-#{i}")

        endpoint =
          CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
            spacecraft_id: craft.spacecraft_id,
            source_endpoint_id:
              Cadence.SourceEndpoints.managed_source_endpoint_id(craft.spacecraft_id)
          })

        if i <= targets_n do
          Cadence.CommandGroupFixtures.commandable_pass!(
            org.organization_id,
            mission.mission_id,
            craft.spacecraft_id
          )
        end

        {craft.spacecraft_id, endpoint.source_endpoint_id}
      end

    Cadence.CommandGroupFixtures.pin_fleet!(%{
      mission: mission.mission_id,
      spacecraft: Enum.map(crafts, &elem(&1, 0))
    })

    crafts = Enum.take(crafts, targets_n)

    %{
      org: org,
      requester: requester,
      approver: approver,
      mission: mission,
      ids: model.commands_by_name,
      crafts: crafts
    }
  end

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}"

  # #117 step 4a: a GO carries the review token the decider saw, read from the group itself.
  defp go(c, id) do
    data = c.approver |> as() |> get(base(c) <> "/command-groups/#{id}") |> json_response(200)
    %{"kind" => "go", "expected_review" => data["data"]["review_token"]}
  end

  defp as(user), do: TestFixtures.member_conn(user)

  defp body(c, command, args) do
    %{
      "title" => "Load shed",
      "log_entry" => "Reset",
      "targets" =>
        Enum.map(c.crafts, fn {id, endpoint} ->
          %{"spacecraft_id" => id, "source_endpoint_id" => endpoint}
        end),
      "commands" => [
        %{"command_id" => c.ids[command], "argument_values_json" => Jason.encode!(args)}
      ]
    }
  end

  defp preflight(c, body),
    do:
      as(c.requester) |> post(base(c) <> "/command-groups/preflight", body) |> json_response(200)

  test "preflight, create and GO stay under their ceilings", c do
    b = body(c, "SET_COUNTER", %{"amount" => 2})
    # The first request of a session pays for authenticating it, as no later one does.
    as(c.requester) |> get(base(c) <> "/command-groups") |> json_response(200)

    {preflight_n, pre} = count_queries(fn -> preflight(c, b) end)

    {create_n, conn} =
      count_queries(fn ->
        as(c.requester)
        |> post(
          base(c) <> "/command-groups",
          Map.merge(b, %{
            "preflight_digest" => pre["data"]["digest"],
            "acknowledged_holds" => []
          })
        )
      end)

    id = json_response(conn, 201)["data"]["id"]
    decision = go(c, id)

    {go_n, conn} =
      count_queries(fn ->
        as(c.approver) |> post(base(c) <> "/command-groups/#{id}/decision", decision)
      end)

    assert %{"data" => %{"state" => "queued"}} = json_response(conn, 200)

    for {name, n} <- [preflight: preflight_n, create: create_n, go: go_n] do
      assert n <= @ceilings[name], "#{name} took #{n} queries, ceiling #{@ceilings[name]}"
    end
  end

  defp count_queries(fun) do
    me = self()
    handler = "request-cost-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, :query) end,
      nil
    )

    try do
      result = fun.()
      {drain(0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end
end
