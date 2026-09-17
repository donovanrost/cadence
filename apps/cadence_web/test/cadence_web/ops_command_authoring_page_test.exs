defmodule CadenceWeb.OpsCommandAuthoringPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandRequestRow, RequestStore}
  alias Cadence.Repo
  alias CadenceWeb.{HostTransportTestSupport, TestFixtures}

  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/features/command-authoring/producer-consumer-probe.mjs",
           __DIR__
         )
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = CommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    path =
      "/missions/#{mission.mission_id}/ops/commands/new?" <>
        URI.encode_query(%{
          "command" => model.commands_by_name["COMMAND_1"],
          "target" => target.source_endpoint_id
        })

    %{
      org: org,
      user: user,
      member: member,
      mission: mission.mission_id,
      model: model,
      target: target,
      path: path
    }
  end

  test "actual producer through Vue previews and creates one durable request and recovers its receipt",
       c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.authoring",
        "mission_id" => c.mission
      })

    p = snapshot["ops_page"]
    assert p["status"] == "ready"
    preview_input = probe(p)

    assert Jason.decode!(preview_input["argument_values_json"]) == %{
             "amount" => 2,
             "delay_s" => 5
           }

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, c.path, p, "preview", preview_input)

    refute Repo.get(CommandRequestRow, preview["request_id"])

    assert Jason.decode!(preview["resolved_argument_values_json"]) == %{
             "amount" => 2,
             "delay_s" => 5
           }

    assert %{"snapshot" => refreshed} = read(view, c.path, p)
    assert refreshed["data"]["preview"] == preview
    create_input = probe(refreshed)
    assert create_input == %{"expected_preview" => preview["token"]}

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, c.path, p, "create", create_input)

    assert receipt["request_id"] == preview["request_id"]

    assert {:ok, request} =
             RequestStore.fetch_request(c.org.organization_id, c.mission, receipt["request_id"])

    assert request.requested_by == %{"actor_kind" => "user", "user_id" => c.user.user_id}
    assert request.lifecycle_state == :approval_pending

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, c.path, p, "create", create_input)

    assert %{"snapshot" => recovered} = read(view, c.path, p)
    assert recovered["data"]["operation"]["receipt"] == receipt

    assert Repo.aggregate(
             from(row in CommandRequestRow, where: row.mission_id == ^c.mission),
             :count
           ) == 1
  end

  test "token, path, selection and departure prevent retained preview or create actions", c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)

    assert %{"ok" => false} =
             action(view, c.path, Map.put(p, "token", "wrong"), "preview", input(p))

    assert %{"ok" => false} =
             action(view, c.path <> "&command_query=other", p, "preview", input(p))

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(
               view,
               c.path,
               p,
               "preview",
               Map.put(input(p), "command_id", c.model.commands_by_name["COMMAND_2"])
             )

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, c.path, p, "preview", input(p))

    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission}/ops/commands"})
    assert_reply(view, %{ok: true})
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true, snapshot: %{ops_page: current}})
    refute current["token"] == p["token"]

    assert %{"ok" => false} =
             action(view, c.path, p, "create", %{"expected_preview" => preview["token"]})

    refute Repo.get(CommandRequestRow, preview["request_id"])
  end

  test "refresh invalidates a preview after activation changes, and role revocation removes access",
       c do
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), c.path)
    p = page(view)

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, c.path, p, "preview", input(p))

    activation = Repo.get!(ActiveBindingSetRow, c.mission)
    Repo.update!(Ecto.Changeset.change(activation, generation: activation.generation + 1))
    assert %{"snapshot" => changed} = read(view, c.path, p)
    assert changed["data"]["preview"] == nil

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, c.path, p, "create", %{"expected_preview" => preview["token"]})

    Repo.get!(OrganizationMembershipRow, c.member.organization_membership_id)
    |> Ecto.Changeset.change(role: "member")
    |> Repo.update!()

    assert %{"snapshot" => %{"status" => "unavailable"}} = read(view, c.path, p)

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, c.path, p, "preview", input(changed))

    refute Repo.get(CommandRequestRow, preview["request_id"])
  end

  test "anonymous users redirect and members cannot read the privileged catalog", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, c.org)
    {:ok, view, _} = live(TestFixtures.member_conn(user), c.path)
    assert page(view)["status"] == "unavailable"
    refute Map.has_key?(page(view), "data")
  end

  test "a mission without an active command model renders setup guidance and cannot create", c do
    mission = TestFixtures.persist_mission!(c.org)
    path = "/missions/#{mission.mission_id}/ops/commands/new"
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    p = page(view)
    assert p["status"] == "ready"
    assert p["data"]["state"] == "command_model_required"
    assert p["data"]["context"] == p["context"]
    assert p["data"]["actor_id"] == c.user.user_id
    assert probe(p) == %{"prerequisite" => "command_model_required"}
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, path, p, "preview", %{})

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, path, p, "create", %{"expected_preview" => "forged"})

    assert Repo.aggregate(
             from(row in CommandRequestRow, where: row.mission_id == ^mission.mission_id),
             :count
           ) == 0

    CommandAuthoringFixtures.activate!(c.org.organization_id, mission.mission_id)
    assert %{"snapshot" => refreshed} = read(view, path, p)
    assert refreshed["status"] == "ready"
    assert refreshed["data"]["catalog"]["context"]["missionId"] == mission.mission_id
    refute Map.has_key?(refreshed["data"], "state")
  end

  defp probe(p) do
    {output, code} = System.cmd("node", [@probe, Jason.encode!(p)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/COMMAND_AUTHORING_INPUT=([A-Za-z0-9+\/=]+)/, output)
    encoded |> Base.decode64!() |> Jason.decode!()
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp input(p) do
    c = p["data"]["catalog"]

    %{
      "expected_basis" => c["basis"]["token"],
      "source_endpoint_ref" => c["query"]["target"],
      "command_id" => c["query"]["command"],
      "argument_values_json" => Jason.encode!(%{"amount" => 2}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }
  end

  defp action(view, path, p, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => event,
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
