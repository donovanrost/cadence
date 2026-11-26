defmodule CadenceWeb.Console.ContactPlanOldActorRowsTest do
  @moduledoc """
  #466 (#462): contact-plan reads never fall back to a person's email. A decision row written
  before #466 keeps its stored email (#116); the reads name the person by the stored display name
  only, so a row without one reads with `name: nil`, never with the email.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Management.Contacts.Store.{
    ContactPlanApprovalRow,
    ContactPlanRow,
    ContactPlanVersionRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    # A user row always has a display name (NOT NULL); the old-form decision row below stores
    # none, so before #466 the reads named this person by their email.
    nameless =
      TestFixtures.persist_user!(display_name: "Nadia", email: "nameless-466@example.test")

    second_admin = TestFixtures.persist_user!(display_name: "Bea")
    member = TestFixtures.persist_user!(display_name: "Mira")
    nameless_membership = TestFixtures.grant_membership!(nameless, org, role: :organization_admin)
    _second = TestFixtures.grant_membership!(second_admin, org, role: :organization_admin)
    member_membership = TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      mission: mission,
      nameless: nameless,
      nameless_membership: nameless_membership,
      second_admin: second_admin,
      member: member,
      member_membership: member_membership,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  test "an old-form decision row: plan_not_pending and the plan's approval name nobody by email",
       c do
    plan_id =
      ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission).plan.contact_plan_id

    submit!(c, c.member, plan_id)
    nameless_id = c.nameless.user_id

    # A send-back as it was stored before #466, with the decider's email in the actor document
    # and no display name. Decision rows are append-only, so it is inserted as written then.
    send_back_with_old_form_actor!(c, plan_id, %{
      "kind" => "user",
      "id" => nameless_id,
      "user_id" => nameless_id,
      "display_name" => nil,
      "email" => c.nameless.email
    })

    conn = post_as(c, c.second_admin, plan_id, "approve", %{"operation_id" => "op-second"})
    body = response(conn, 409)
    refute body =~ c.nameless.email

    assert %{"code" => "plan_not_pending", "details" => %{"decided_by" => decided_by}} =
             Jason.decode!(body)["error"]

    assert decided_by == %{"id" => nameless_id, "name" => nil}

    detail = c.second_admin |> TestFixtures.member_conn() |> get("#{c.base}/#{plan_id}")
    detail_body = response(detail, 200)
    refute detail_body =~ c.nameless.email

    assert %{"kind" => "user", "id" => ^nameless_id, "name" => nil} =
             Jason.decode!(detail_body)["data"]["approval"]["actor"]
  end

  # contact_plan_overview's author lookup (by user id) loses its `|| email` fallback too. A
  # stored user always has a display name, so this pins the name and that no email is sent.
  test "a plan's author is named by display name and their email is never sent", c do
    plan_id =
      ContactPlanningFixtures.plan_fixture(c.org, c.nameless, c.nameless_membership, c.mission).plan.contact_plan_id

    body = c.member |> TestFixtures.member_conn() |> get("#{c.base}/#{plan_id}") |> response(200)
    refute body =~ c.nameless.email
    assert %{"kind" => "user", "name" => "Nadia"} = Jason.decode!(body)["data"]["author"]
  end

  defp send_back_with_old_form_actor!(c, plan_id, document) do
    org_id = c.org.organization_id
    now = DateTime.utc_now()

    version =
      Repo.one!(
        from(v in ContactPlanVersionRow,
          where: v.organization_id == ^org_id and v.contact_plan_id == ^plan_id,
          order_by: [desc: v.version],
          limit: 1
        )
      )

    {1, _} =
      Repo.insert_all(ContactPlanApprovalRow, [
        %{
          contact_plan_approval_id: "contact-plan-approval-466-#{plan_id}",
          organization_id: org_id,
          mission_id: c.mission.mission_id,
          contact_plan_id: plan_id,
          contact_plan_version: version.version,
          decision: "rejected",
          content_sha256: version.content_sha256,
          reason: "Sent back before #466",
          actor_kind: "user",
          actor_id: document["id"],
          actor_document: JsonDocument.wrap_value(document),
          decided_at: now,
          exceptions_document: [],
          inserted_at: now
        }
      ])

    # What a send-back does to the plan (ContactPlanApprovals): back to draft.
    {1, _} =
      Repo.update_all(
        from(p in ContactPlanRow,
          where: p.organization_id == ^org_id and p.contact_plan_id == ^plan_id
        ),
        set: [
          lifecycle_state: "draft",
          lifecycle_changed_by: document["id"],
          lifecycle_changed_at: now
        ]
      )
  end

  defp submit!(c, user, plan_id) do
    c
    |> post_as(user, plan_id, "submit", %{"operation_id" => "op-submit"})
    |> json_response(200)
  end

  defp post_as(c, user, plan_id, action, body) do
    body = Map.put_new(body, "expected_version", current_version(c, plan_id))
    user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/#{action}", body)
  end

  defp current_version(c, plan_id) do
    c.second_admin
    |> TestFixtures.member_conn()
    |> get("#{c.base}/#{plan_id}")
    |> json_response(200)
    |> get_in(["data", "version"])
  end
end
