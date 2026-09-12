defmodule CadenceWeb.OpsCommandQueuePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Auth.Scope
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Control.Commanding.QueueSubmission
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/features/queue-submission/producer-consumer-probe.mjs",
           __DIR__
         )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = CommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: member
      })

    {:ok, catalog} = RequestAuthoring.load(scope, mission.mission_id, %{})

    input = %{
      "expected_basis" => catalog["basis"]["token"],
      "command_id" => model.commands_by_name["COMMAND_2"],
      "source_endpoint_ref" => target.source_endpoint_id,
      "argument_values_json" => Jason.encode!(%{"amount" => 2}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }

    {:ok, held} = RequestAuthoring.preview(scope, mission.mission_id, input)

    {:ok, receipt} =
      RequestAuthoring.create(scope, mission.mission_id, held, %{"expected_preview" => held.token})

    request = receipt["request_id"]

    %{
      org: org,
      user: user,
      member: member,
      scope: scope,
      mission: mission.mission_id,
      request: request,
      path: "/missions/#{mission.mission_id}/ops/commands/requests/#{request}/queue"
    }
  end

  test "actual Phoenix producer through Vue queues once and reads the exact receipt", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)
    assert p["status"] == "ready"
    input = probe(p)
    assert input == %{"expected_queue" => p["data"]["preview"]["token"]}

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, c.path, p, input)

    assert receipt["request_id"] == c.request
    assert receipt["actor_id"] == c.user.user_id
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, c.path, p, input)
    assert %{"snapshot" => current} = read(view, c.path, p)
    assert current["data"]["operation"]["receipt"] == receipt
    assert probe(current) == %{"receipt" => receipt}
    assert Repo.get!(CommandRequestRow, c.request).lifecycle_state == "queued"

    assert Repo.aggregate(
             from(row in CommandQueueEntryRow, where: row.mission_id == ^c.mission),
             :count
           ) == 1
  end

  test "a retained unconfirmed host operation recovers only its exact persisted submission", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)
    held = :sys.get_state(view.pid).socket.assigns.ops_command_queue_session.held

    assert {:ok, receipt} =
             QueueSubmission.submit(c.scope, c.mission, held, %{"expected_queue" => held.token})

    unconfirm(view)
    assert %{"snapshot" => current} = read(view, c.path, p)
    assert current["data"]["operation"] == %{"status" => "completed", "receipt" => receipt}
  end

  test "an existing queue from another operation does not resolve this host's uncertain attempt",
       c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)
    {:ok, %{held: other}} = QueueSubmission.load(c.scope, c.mission, c.request)

    assert {:ok, _} =
             QueueSubmission.submit(c.scope, c.mission, other, %{"expected_queue" => other.token})

    unconfirm(view)
    assert %{"snapshot" => current} = read(view, c.path, p)
    assert current["data"]["operation"] == %{"status" => "unconfirmed"}
    assert current["data"]["model"]["availability"] == "queued"
  end

  test "retained tokens, changed paths and revoked manager rights cannot queue", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)
    input = %{"expected_queue" => p["data"]["preview"]["token"]}
    assert %{"ok" => false} = action(view, c.path, Map.put(p, "token", "wrong"), input)
    assert %{"ok" => false} = action(view, c.path <> "?other=value", p, input)

    Repo.get!(OrganizationMembershipRow, c.member.organization_membership_id)
    |> Ecto.Changeset.change(role: "member")
    |> Repo.update!()

    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, c.path, p, input)
    assert %{"snapshot" => %{"status" => "unavailable"}} = read(view, c.path, p)
    refute Repo.exists?(from(row in CommandQueueEntryRow, where: row.mission_id == ^c.mission))
  end

  test "anonymous visitors redirect and ordinary members cannot read command queue details", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, c.org)
    {:ok, view, _} = live(TestFixtures.member_conn(member), c.path)
    assert page(view)["status"] == "unavailable"
    refute Map.has_key?(page(view), "data")
  end

  defp unconfirm(view) do
    :sys.replace_state(view.pid, fn state ->
      session = %{
        state.socket.assigns.ops_command_queue_session
        | operation: %{status: "unconfirmed"}
      }

      %{
        state
        | socket: Phoenix.Component.assign(state.socket, :ops_command_queue_session, session)
      }
    end)
  end

  defp probe(p) do
    {output, code} = System.cmd("node", [@probe, Jason.encode!(p)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/COMMAND_QUEUE_INPUT=([A-Za-z0-9+\/=]+)/, output)
    encoded |> Base.decode64!() |> Jason.decode!()
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp action(view, path, p, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => "submit",
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
