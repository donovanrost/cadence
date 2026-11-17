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
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
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
        })
      )

    %{
      admin: admin,
      member: member,
      identity: identity,
      version: v1.version,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-planning/grants"
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

  test "read, issue and revoke a grant; expired is computed; members read but can't manage", c do
    data = json_response(get_json(c.admin, c.base), 200)["data"]

    assert %{"grants" => [], "policy_version" => version, "permissions" => ["grants.manage"]} =
             data

    assert version == c.version
    assert [%{"name" => "Planner bot", "state" => "active"}] = data["service_identities"]

    assert %{
             "maximum_horizon_seconds" => _,
             "maximum_contacts" => _,
             "maximum_execution_concurrency" => _
           } = data["limits"]

    assert %{"grant" => grant} = json_response(post_json(c.admin, c.base, body(c)), 201)["data"]

    assert %{
             "state" => "active",
             "service_identity" => %{"name" => "Planner bot"},
             "approved_by" => %{"name" => "Ada"},
             "reason" => "Night shift automation",
             "sha256" => sha
           } = grant

    assert "approve" in grant["allowed_actions"]

    assert %{"permissions" => [], "grants" => [_]} =
             json_response(get_json(c.member, c.base), 200)["data"]

    assert json_response(post_json(c.member, c.base, body(c)), 403)

    revoke = "#{c.base}/#{grant["id"]}/revoke"

    assert %{"code" => "grant_changed"} =
             json_response(
               post_json(c.admin, revoke, %{"reason" => "x", "sha256" => "stale"}),
               409
             )["error"]

    # Drift sweep: a missing sha256 is a field error on sha256.
    assert %{"code" => "invalid_params", "details" => %{"sha256" => "is required"}} =
             json_response(post_json(c.admin, revoke, %{"reason" => "x"}), 422)["error"]

    assert %{
             "grant" => %{
               "state" => "revoked",
               "revoked_by" => %{"name" => "Ada"},
               "revocation_reason" => "Done"
             }
           } =
             json_response(
               post_json(c.admin, revoke, %{"reason" => "Done", "sha256" => sha}),
               200
             )["data"]
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
end
