defmodule CadenceWeb.Console.ContactGrantAPITest do
  @moduledoc "§11 L3: automation grants for the console Policy tab."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.FleetStartFixtures
  alias Cadence.PolicyReviewer
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    admin = TestFixtures.persist_user!(display_name: "Ada")
    # #283: a second org admin approves proposals under 'independent'.
    approver = TestFixtures.persist_user!(display_name: "Bea")
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    {:ok, scope} =
      Auth.authenticate_browser_session(TestFixtures.member_session_token!(admin),
        current_organization_id: org.organization_id
      )

    attrs =
      FleetStartFixtures.policy_attrs()
      |> put_in([:automation_repair_document, "mode"], "bounded_automatic")
      |> put_in([:automation_repair_document, "automatic_submission"], true)

    {:ok, policy, v1} = FleetPlanningPolicies.create(scope, mission.mission_id, attrs)

    {:ok, _, _, _} =
      FleetPlanningPolicies.approve(
        PolicyReviewer.reviewer(scope),
        mission.mission_id,
        policy.fleet_planning_policy_id,
        v1.version,
        v1.content_sha256,
        "Reviewed"
      )

    {:ok, %{service_identity: identity}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "Planner bot",
          capabilities: [:mission_admin]
        }),
        %Auth.Scope{
          actor_kind: :user,
          organization_id: org.organization_id,
          user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
        }
      )

    %{
      admin: admin,
      approver: approver,
      member: member,
      identity: identity,
      version: v1.version,
      mission: mission,
      org: org,
      base: "/api/v1/missions/#{mission.mission_id}/contact-planning/grants"
    }
  end

  defp get_json(user, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp post_json(user, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  defp body(c, overrides \\ %{}) do
    Map.merge(
      %{
        "service_identity_id" => c.identity.service_identity_id,
        "maximum_horizon_seconds" => 3_600,
        "maximum_contacts" => 10,
        "maximum_execution_concurrency" => 1,
        "valid_days" => 7,
        "reason" => "Night shift automation",
        "policy_version" => c.version
      },
      overrides
    )
  end

  test "propose, approve (replayable) and revoke a grant; members read but can't manage", c do
    data = json_response(get_json(c.admin, c.base), 200)["data"]

    assert %{
             "grants" => [],
             "policy_version" => version,
             "permissions" => ["grants.manage"],
             "approval_setting" => "independent"
           } = data

    assert version == c.version
    assert [%{"name" => "Planner bot", "state" => "active"}] = data["service_identities"]

    assert %{
             "maximum_horizon_seconds" => _,
             "maximum_contacts" => _,
             "maximum_execution_concurrency" => _
           } = data["limits"]

    # #283 (U105): under 'independent' issuing proposes; it authorizes nothing yet.
    assert %{"grant" => grant} = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]

    assert %{
             "state" => "proposed",
             "service_identity" => %{"name" => "Planner bot"},
             "proposed_by" => %{"name" => "Ada"},
             "approved_by" => nil,
             "valid_from" => nil,
             "validity_seconds" => 604_800,
             "reason" => "Night shift automation",
             "viewer_can_decide" => false,
             "cannot_decide_because" => "proposer",
             "sha256" => sha
           } = grant

    assert "approve" in grant["allowed_actions"]

    # The flags are the viewer's: the second admin may decide, the member may not.
    [for_bea] = json_response(get_json(c.approver, c.base), 200)["data"]["grants"]
    assert %{"viewer_can_decide" => true, "cannot_decide_because" => nil} = for_bea

    assert %{"permissions" => [], "grants" => [for_mia]} =
             json_response(get_json(c.member, c.base), 200)["data"]

    assert for_mia["cannot_decide_because"] == "not_admin"
    assert json_response(post_json(c.member, c.base, body(c)), 403)

    approve = "#{c.base}/#{grant["id"]}/approve"

    assert %{"code" => "automation_grant_self_approval_forbidden", "details" => details} =
             json_response(
               post_json(c.admin, approve, %{"sha256" => sha, "operation_id" => "op-ada"}),
               403
             )["error"]

    assert %{"because" => "proposed", "grantee" => %{"name" => "Planner bot"}} = details

    request = %{"sha256" => sha, "operation_id" => "op-bea-1"}

    assert %{"grant" => active, "replayed" => false} =
             json_response(post_json(c.approver, approve, request), 200)["data"]

    assert %{"state" => "active", "approved_by" => %{"name" => "Bea"}} = active
    assert active["valid_from"]

    # The same request again answers the original; anything else on that id is refused.
    assert %{"grant" => ^active, "replayed" => true} =
             json_response(post_json(c.approver, approve, request), 200)["data"]

    assert %{"code" => "duplicate_operation"} =
             json_response(
               post_json(c.approver, approve, %{request | "sha256" => String.duplicate("0", 64)}),
               409
             )["error"]

    # A second approval of a decided grant says who decided it.
    assert %{"code" => "automation_grant_not_proposed", "details" => not_proposed} =
             json_response(
               post_json(c.admin, approve, %{"sha256" => sha, "operation_id" => "op-ada-2"}),
               409
             )["error"]

    assert %{"state" => "active", "decided_by" => _, "decided_at" => _} = not_proposed

    # Revoke is one admin, at once; no current hash or reason needed (a tightening).
    revoke = "#{c.base}/#{grant["id"]}/revoke"

    assert %{"grant" => %{"state" => "revoked", "revoked_by" => %{"name" => "Ada"}}} =
             json_response(post_json(c.admin, revoke, %{}), 200)["data"]

    # A retry answers 200 with the revoked grant, never a refusal (api-ops on #497).
    assert %{"grant" => %{"state" => "revoked", "revoked_by" => %{"name" => "Ada"}}} =
             json_response(post_json(c.approver, revoke, %{}), 200)["data"]
  end

  # ca-security on #497: who may decide is checked before any lock or replay, so a member can't
  # probe grant ids (403, never 404) or replay an admin's answer.
  test "a member is refused 403 before any lookup or replay", c do
    %{"grant" => grant} = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]
    approve = "#{c.base}/#{grant["id"]}/approve"
    request = %{"sha256" => grant["sha256"], "operation_id" => "op-shared"}

    assert json_response(post_json(c.approver, approve, request), 200)

    for path <- [approve, "#{c.base}/no-such-grant/approve"] do
      assert %{"code" => "forbidden"} =
               json_response(post_json(c.member, path, request), 403)["error"]
    end
  end

  test "reject needs a reason; narrow takes access away at once", c do
    %{"grant" => proposal} = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]
    reject = "#{c.base}/#{proposal["id"]}/reject"

    assert %{"code" => "invalid_params", "details" => %{"reason" => "Say why."}} =
             json_response(post_json(c.approver, reject, %{"operation_id" => "op-r1"}), 422)[
               "error"
             ]

    assert %{"grant" => %{"state" => "rejected", "rejection_reason" => "Too broad"}} =
             json_response(
               post_json(c.approver, reject, %{"reason" => "Too broad", "operation_id" => "op-r2"}),
               200
             )["data"]

    %{"grant" => grant} = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]

    %{"grant" => _active} =
      json_response(
        post_json(c.approver, "#{c.base}/#{grant["id"]}/approve", %{
          "sha256" => grant["sha256"],
          "operation_id" => "op-a"
        }),
        200
      )["data"]

    narrow = "#{c.base}/#{grant["id"]}/narrow"

    assert %{"grant" => %{"state" => "active", "maximum_contacts" => 3}} =
             json_response(
               post_json(c.admin, narrow, %{
                 "changes" => %{"maximum_contacts" => 3},
                 "operation_id" => "op-n1"
               }),
               200
             )["data"]

    assert %{
             "code" => "automation_grant_not_narrower",
             "details" => %{"fields" => ["maximum_contacts"]}
           } =
             json_response(
               post_json(c.admin, narrow, %{
                 "changes" => %{"maximum_contacts" => 9},
                 "operation_id" => "op-n2"
               }),
               422
             )["error"]
  end

  test "a stale policy version, limits beyond the policy and missing fields are refused", c do
    assert %{"code" => "policy_changed", "details" => %{"active_version" => version}} =
             json_response(
               post_json(c.admin, c.base, body(c, %{"policy_version" => c.version + 5})),
               409
             )["error"]

    assert version == c.version

    assert %{"maximum_horizon_seconds" => _} =
             json_response(
               post_json(c.admin, c.base, body(c, %{"maximum_horizon_seconds" => 999_999_999})),
               422
             )["error"]["details"]

    assert %{"reason" => _, "valid_days" => _} =
             json_response(
               post_json(c.admin, c.base, body(c, %{"reason" => "", "valid_days" => 0})),
               422
             )["error"]["details"]
  end

  # #499 end to end: a mission tightened to 'independent' through the console's settings save
  # lists the single-approval grant first (409, nothing written), suspends it once acknowledged,
  # and a second org admin resumes it (replayable); its original approver can't.
  test "a tightening lists, then suspends, a single-approval grant; another admin resumes it",
       c do
    org_settings = "/api/v1/organizations/#{c.org.organization_id}/settings"
    mission_settings = "/api/v1/missions/#{c.mission.mission_id}/settings"
    assert json_response(save_setting(c.admin, org_settings, "direct", true), 201)

    grant = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]["grant"]
    assert grant["state"] == "active"

    assert %{"error" => %{"code" => "approval_tightening_suspends_grants", "details" => details}} =
             json_response(save_setting(c.admin, mission_settings, "independent"), 409)

    assert %{"grants" => [listed], "digest" => digest} = details
    assert listed["id"] == grant["id"]
    assert listed["mission"]["id"] == c.mission.mission_id
    assert listed["service"] == %{"id" => c.identity.service_identity_id, "name" => "Planner bot"}

    assert json_response(
             save_setting(c.admin, mission_settings, "independent", nil, digest),
             201
           )

    [suspended] = json_response(get_json(c.admin, c.base), 200)["data"]["grants"]
    assert suspended["state"] == "suspended"

    assert %{
             "by" => %{"kind" => "user", "name" => "Ada"},
             "level" => "mission",
             "settings_revision" => revision
           } = suspended["suspension"]

    assert is_binary(revision)

    resume = "#{c.base}/#{grant["id"]}/resume"
    request = %{"sha256" => suspended["sha256"], "operation_id" => "op-resume"}

    assert %{"error" => %{"code" => "automation_grant_self_approval_forbidden"}} =
             json_response(
               post_json(c.admin, resume, %{request | "operation_id" => "op-ada"}),
               403
             )

    assert %{"grant" => %{"state" => "active"}, "replayed" => false} =
             json_response(post_json(c.approver, resume, request), 200)["data"]

    assert %{"replayed" => true} =
             json_response(post_json(c.approver, resume, request), 200)["data"]
  end

  defp save_setting(user, base, requirement, allow_override \\ nil, acknowledged \\ nil) do
    read = user |> TestFixtures.member_conn() |> get(base) |> json_response(200)
    section = Enum.find(read["data"]["sections"], &(&1["key"] == "cadence.governance"))

    values =
      if is_nil(allow_override),
        do: %{"approval_requirement" => requirement},
        else: %{"approval_requirement" => requirement, "allow_override" => allow_override}

    body =
      %{
        "values" => values,
        "expected_version" => section["version"] && section["version"]["version"]
      }
      |> then(
        &if(acknowledged, do: Map.put(&1, "acknowledged_suspensions", acknowledged), else: &1)
      )

    user |> TestFixtures.member_conn() |> put(base <> "/cadence.governance", body)
  end
end
