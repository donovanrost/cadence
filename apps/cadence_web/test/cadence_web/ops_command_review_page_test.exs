defmodule CadenceWeb.OpsCommandReviewPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Commanding.RequestStore
  alias Cadence.CommandReviewFixtures
  alias Cadence.Repo
  alias CadenceWeb.{HostTransportTestSupport, TestFixtures}

  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/features/command-review/producer-consumer-probe.mjs",
           __DIR__
         )
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    c = %{org: org.organization_id, mission: mission.mission_id, user: user, member: member}
    request = CommandReviewFixtures.request!(c)

    Map.merge(c, %{
      request: request,
      path: "/missions/#{c.mission}/ops/commands/requests/#{request.command_request_id}"
    })
  end

  test "actual persisted producer through Vue input records one authorized decision and recovers its receipt",
       c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.review",
        "mission_id" => c.mission
      })

    p = snapshot["ops_page"]
    assert p["status"] == "ready"
    {output, code} = System.cmd("node", [@probe, Jason.encode!(p)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/COMMAND_REVIEW_INPUT=([A-Za-z0-9+\/=]+)/, output)
    input = encoded |> Base.decode64!() |> Jason.decode!()
    assert input["expected_review"] == p["data"]["review"]["expected_review"]

    assert %{"ok" => true, "snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, c.path, p, input)

    assert receipt["request_id"] == c.request.command_request_id
    assert receipt["actor_id"] == c.user.user_id
    assert %{"ok" => true, "snapshot" => recovered} = read(view, c.path, p)
    assert recovered["data"]["operation"]["receipt"] == receipt
    assert recovered["data"]["review"]["request"]["lifecycle_state"] == "approved"
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, c.path, p, input)
    assert [%{command_approval_id: id}] = RequestStore.list_approvals(c.org, c.mission, [])
    assert id == receipt["approval_id"]
  end

  test "path, resource, token and page departure prevent retained action replay", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)

    assert %{"ok" => false} =
             action(view, c.path, Map.put(p, "token", Ecto.UUID.generate()), input(p))

    assert %{"ok" => false} = action(view, c.path <> "?after=foreign", p, input(p))
    other = CommandReviewFixtures.request!(c)
    other_path = "/missions/#{c.mission}/ops/commands/requests/#{other.command_request_id}"
    assert %{"ok" => false} = action(view, other_path, p, input(p))
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission}/ops/commands"})
    assert_reply(view, %{ok: true})
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true, snapshot: %{ops_page: current}})
    refute current["token"] == p["token"]
    assert %{"ok" => false} = action(view, c.path, p, input(p))
    assert RequestStore.list_approvals(c.org, c.mission, []) == []
  end

  test "persisted role revocation is enforced after mounting the review", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)

    Repo.get!(OrganizationMembershipRow, c.member.organization_membership_id)
    |> Ecto.Changeset.change(role: "member")
    |> Repo.update!()

    assert %{"ok" => true, "snapshot" => %{"status" => "rejected"}} =
             action(view, c.path, p, input(p))

    assert %{"ok" => true, "snapshot" => %{"status" => "unavailable"}} = read(view, c.path, p)
    assert RequestStore.list_approvals(c.org, c.mission, []) == []
  end

  test "anonymous users redirect and members cannot read privileged request arguments", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
    user = TestFixtures.persist_user!()
    {:ok, org} = Cadence.Organizations.fetch_organization(c.org)
    TestFixtures.grant_membership!(user, org)
    {:ok, view, _} = live(TestFixtures.member_conn(user), c.path)
    assert page(view)["status"] == "unavailable"
    refute Map.has_key?(page(view), "data")
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp input(p),
    do: %{
      "decision" => "approved",
      "reason" => "Reviewed",
      "expected_review" => p["data"]["review"]["expected_review"]
    }

  defp action(view, path, p, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => "decide",
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp read(view, path, p) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
