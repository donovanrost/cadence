defmodule CadenceWeb.OpsFleetPolicyPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}
  alias Cadence.FleetStartFixtures
  alias Cadence.Reads.ApplicationSurfaces.Planning.FleetPolicyModel
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/policy-workflow-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    attrs =
      FleetStartFixtures.policy_attrs()
      |> put_in([:automation_repair_document, "mode"], "bounded_automatic")
      |> put_in([:automation_repair_document, "automatic_submission"], true)

    {:ok, policy, v1} = FleetPlanningPolicies.create(scope, mission.mission_id, attrs)

    {:ok, _, _, _} =
      FleetPlanningPolicies.approve(
        scope,
        mission.mission_id,
        policy.fleet_planning_policy_id,
        1,
        v1.content_sha256,
        "Reviewed initial boundary"
      )

    {:ok, _, v2} =
      FleetPlanningPolicies.version(
        scope,
        mission.mission_id,
        policy.fleet_planning_policy_id,
        1,
        %{horizon_document: Map.put(v1.horizon_document, "requirement_concurrency", 8)}
      )

    c = %{
      org: org,
      mission: mission,
      user: user,
      scope: scope,
      policy: policy,
      v1: v1,
      v2: v2,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/planning/policy"
    }

    {:ok, %{service_identity: identity}} = identity(c, "Automation")
    c = Map.put(c, :identity, identity)
    {:ok, grant} = grant(c)
    Map.put(c, :grant, grant)
  end

  for event <- ~w(save-policy approve-policy issue-grant revoke-grant) do
    @event event
    test "real producer and native #{@event} complete through the authenticated contribution",
         c do
      if @event == "issue-grant", do: identity(c, "A new authority")
      {:ok, view, _} = live(c.conn, c.path)
      original = page(view)
      assert original["status"] == "ready"
      assert original["data"]["model"]["current"]["reference"]["policy_version"] == 2
      assert original["data"]["model"]["active"]["reference"]["policy_version"] == 1
      commands = native(%{snapshot: original, action: @event})

      operation =
        Enum.reduce(commands, nil, fn [event, input], _ ->
          action(view, c.path, original, event, input)["snapshot"]
        end)

      assert operation["action"] == @event
      assert operation["status"] == "completed"
      assert operation["receipt"]["receiptId"]
      assert native(%{snapshot: original, action: @event, operation: operation}) == commands
      [_, input] = List.last(commands)
      assert action(view, c.path, original, @event, input)["snapshot"]["status"] == "rejected"
      recovered = read(view, c.path, original)["snapshot"]
      assert recovered["data"]["operation"] == operation
      assert recovered["data"]["sequence"] == input["sequence"]
      assert page(view) == original
      assert_effect(c, @event, operation)
    end
  end

  test "an unconfigured mission creates its first exact draft through the native contribution",
       c do
    mission = TestFixtures.persist_mission!(c.org)
    path = "/missions/#{mission.mission_id}/ops/planning/policy"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["data"]["model"]["state"] == "unconfigured"
    assert original["data"]["model"]["current"] == nil
    commands = native(%{snapshot: original, action: "save-policy"})

    operation =
      Enum.reduce(commands, nil, fn [event, input], _ ->
        action(view, path, original, event, input)["snapshot"]
      end)

    assert operation["status"] == "completed"
    assert operation["receipt"]["result"]["fleetPlanningPolicyVersion"] == 1
    assert native(%{snapshot: original, action: "save-policy", operation: operation}) == commands
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["model"]["state"] == "draft"
    assert refreshed["data"]["model"]["active"] == nil
    {:ok, _, version} = FleetPlanningPolicies.fetch(c.org.organization_id, mission.mission_id)
    assert version.version == 1
    assert version.horizon_document["requirement_concurrency"] == 5
  end

  test "stale and foreign review references are rejected before creating policy or grant effects",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    ref = original["data"]["model"]["current"]["reference"]

    for {override, index} <-
          Enum.with_index(
            [
              %{"mission_id" => "foreign"},
              %{"content_sha256" => String.duplicate("a", 64)},
              %{"policy_version" => 1}
            ],
            1
          ) do
      payload = %{
        "decision" => %{"reason" => "Review", "policy_evidence" => Map.merge(ref, override)}
      }

      reply =
        action(view, c.path, original, "approve-policy", %{
          "sequence" => index,
          "payload" => payload
        })

      assert reply["snapshot"]["status"] == "rejected"
    end

    {:ok, _, active} =
      FleetPlanningPolicies.fetch_active(c.org.organization_id, c.mission.mission_id)

    assert active.version == 1
    evidence = original["data"]["model"]["grants"]["entries"] |> hd() |> Map.fetch!("reference")

    payload = %{
      "revocation" => %{
        "automation_grant_id" => c.grant.automation_grant_id,
        "reason" => "Review"
      },
      "grant_evidence" => Map.put(evidence, "content_sha256", String.duplicate("a", 64))
    }

    assert action(view, c.path, original, "revoke-grant", %{"sequence" => 4, "payload" => payload})[
             "snapshot"
           ]["status"] == "rejected"

    {:ok, grant} =
      AutomationGrants.fetch(
        c.org.organization_id,
        c.mission.mission_id,
        c.grant.automation_grant_id
      )

    assert grant.lifecycle_state == :active
  end

  test "bounded reads preserve captured pages, expose no credentials and do not perform effects",
       c do
    for n <- 1..25 do
      assert {:ok, %{service_identity: identity}} = identity(c, "Identity #{n}")
      assert {:ok, _} = grant(%{c | identity: identity})
    end

    path = c.path <> "?grants_page=2&identities_page=2"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    model = original["data"]["model"]
    assert length(model["grants"]["entries"]) == 1
    assert length(model["identities"]["entries"]) == 1
    assert model["grants"]["active_count"] == 26
    assert Enum.all?(model["identities"]["entries"], &(Enum.sort(Map.keys(&1)) == ~w(id name)))
    assert read(view, path, original)["snapshot"] == original

    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"],
      "input" => %{"grants_page" => 1}
    })

    assert_reply(view, %{ok: false})
    {:ok, _, latest} = FleetPlanningPolicies.fetch(c.org.organization_id, c.mission.mission_id)
    assert latest.version == 2
    assert length(AutomationGrants.list(c.org.organization_id, c.mission.mission_id)) == 26
  end

  test "ordinary rejected grant bounds can be corrected without duplicating authority", c do
    assert {:ok, _} = identity(c, "A new authority")
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    commands = native(%{snapshot: original, action: "issue-grant"})
    [_, input] = List.last(commands)

    too_large =
      input
      |> Map.put("sequence", 1)
      |> put_in(["payload", "grant", "maximum_horizon_duration"], "2d")

    assert action(view, c.path, original, "issue-grant", too_large)["snapshot"]["status"] ==
             "rejected"

    assert length(AutomationGrants.list(c.org.organization_id, c.mission.mission_id)) == 1

    assert action(view, c.path, original, "issue-grant", Map.put(input, "sequence", 2))[
             "snapshot"
           ]["status"] == "completed"

    assert length(AutomationGrants.list(c.org.organization_id, c.mission.mission_id)) == 2
  end

  test "an operator can read the policy but cannot acquire administrative form or action authority",
       c do
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, c.org, role: :member)

    scope =
      Scope.new(%{
        user: user,
        organization_id: c.org.organization_id,
        organization_membership: membership
      })

    {:ok, view, _} = live(TestFixtures.member_conn(user), c.path)
    original = page(view)

    assert original["data"]["model"]["permissions"] == %{
             "edit" => false,
             "approve" => false,
             "grants" => false
           }

    assert original["data"]["model"]["identities"]["entries"] == []

    payload = %{
      "decision" => %{
        "reason" => "No authority",
        "policy_evidence" => original["data"]["model"]["current"]["reference"]
      }
    }

    assert action(view, c.path, original, "approve-policy", %{
             "sequence" => 1,
             "payload" => payload
           })["snapshot"]["status"] == "rejected"

    assert {:error, :scope_mismatch} =
             FleetPolicyModel.load(%{scope | mission_id: "foreign"}, c.mission.mission_id, %{})

    assert {:error, :scope_mismatch} =
             AutomationGrants.list_page(%{scope | mission_id: "foreign"}, c.mission.mission_id, 1)
  end

  test "malformed pages are unavailable, departed tokens expire and revoked sessions cannot read",
       c do
    {:ok, view, _} = live(c.conn, c.path <> "?grants_page=0")
    assert has_element?(view, "#application-shell")
    assert page(view)["status"] == "unavailable"
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    original = page(view)
    render_hook(view, "host:context", %{"path" => "/missions"})
    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    refute page(view)["token"] == original["token"]
    current = page(view)
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => current["id"],
      "token" => current["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  defp assert_effect(c, "save-policy", op) do
    {:ok, _, v} = FleetPlanningPolicies.fetch(c.org.organization_id, c.mission.mission_id)
    assert v.version == 3
    assert v.horizon_document["requirement_concurrency"] == 5
    assert v.scoring_document == c.v2.scoring_document
    assert v.resource_policy_document == c.v2.resource_policy_document
    assert v.content_sha256 == op["receipt"]["result"]["contentSha256"]
  end

  defp assert_effect(c, "approve-policy", op) do
    {:ok, _, v} = FleetPlanningPolicies.fetch_active(c.org.organization_id, c.mission.mission_id)
    assert v.version == 2
    assert v.content_sha256 == op["receipt"]["result"]["contentSha256"]
  end

  defp assert_effect(c, event, op) when event in ~w(issue-grant revoke-grant) do
    {:ok, g} =
      AutomationGrants.fetch(
        c.org.organization_id,
        c.mission.mission_id,
        op["receipt"]["result"]["automationGrantId"]
      )

    assert Atom.to_string(g.lifecycle_state) == op["receipt"]["result"]["lifecycleState"]
  end

  defp identity(c, name),
    do:
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: c.org.organization_id,
          mission_id: c.mission.mission_id,
          display_name: name,
          capabilities: [:mission_admin]
        })
      )

  defp grant(c),
    do:
      AutomationGrants.issue(c.scope, c.mission.mission_id, %{
        service_identity_id: c.identity.service_identity_id,
        allowed_actions: [:plan, :repair],
        maximum_horizon_seconds: 3601,
        maximum_contacts: 10,
        maximum_execution_concurrency: 2,
        valid_until: DateTime.add(DateTime.utc_now(), 7, :day),
        approval_reason: "Reviewed bounded authority"
      })

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, page) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, commands] = Regex.run(~r/POLICY_CONTRIBUTION_COMMANDS=([^\n]+)/, output)
    Jason.decode!(commands)
  end
end
