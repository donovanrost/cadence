defmodule CadenceWeb.Console.PlanningPolicyAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()

    [ada, bob, mia] =
      for name <- ~w(Ada Bob Mia), do: TestFixtures.persist_user!(display_name: name)

    TestFixtures.grant_membership!(ada, org, role: :organization_admin)
    TestFixtures.grant_membership!(bob, org, role: :organization_admin)
    TestFixtures.grant_membership!(mia, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      ada: ada,
      bob: bob,
      mia: mia,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-planning/policy"
    }
  end

  defp call(user, :get, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp call(user, :post, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  defp document do
    ContactPlanningFixtures.policy_attrs()
    |> Map.new(fn
      {:horizon_document, v} -> {"horizon", v}
      {:scoring_document, v} -> {"scoring", v}
      {:resource_policy_document, v} -> {"resources", v}
      {:budget_quota_document, v} -> {"budgets", v}
      {:redundancy_document, v} -> {"redundancy", v}
      {:automation_repair_document, v} -> {"automation", v}
    end)
  end

  test "an empty mission has no policy but a schema and defaults", c do
    data = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")

    assert %{"document" => nil, "version" => nil, "pending" => nil} = data

    assert Enum.any?(
             data["schema"],
             &(&1["path"] == "automation.mode" and &1["group"] == "automation")
           )

    assert data["defaults"]["horizon"]["max_horizon_seconds"] == 604_800
    assert data["permissions"] == ["planning.edit", "planning.approve"]
  end

  # Lead 11-14: the saver's reason is stored on the version, shown on pending and in the audit.
  test "a save's reason is stored on its version, read on pending and in the audit", c do
    long = String.duplicate("x", 501)

    assert %{"details" => %{"reason" => _}} =
             c.ada
             |> call(:post, c.base, %{"document" => document(), "reason" => long})
             |> json_response(422)
             |> Map.fetch!("error")

    c.ada
    |> call(:post, c.base, %{
      "document" => document(),
      "reason" => "  Wider horizon for the campaign "
    })
    |> json_response(201)

    pending = c.ada |> call(:get, c.base) |> json_response(200) |> get_in(["data", "pending"])
    assert pending["reason"] == "Wider horizon for the campaign"

    audit =
      c.ada
      |> call(:get, "/api/console/v1/organizations/#{c.org.organization_id}/audit?kinds=contacts")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert %{
             "kind" => "contacts",
             "reason" => "Wider horizon for the campaign",
             "actor" => %{"kind" => "user", "name" => "Ada"},
             "target" => %{"kind" => "planning_policy", "label" => "Planning policy"}
           } = Enum.find(audit, &(&1["action"] == "Proposed planning policy v1"))

    c.ada
    |> call(:post, c.base, %{"document" => document(), "expected_version" => 1})
    |> json_response(201)

    second = c.ada |> call(:get, c.base) |> json_response(200) |> get_in(["data", "pending"])
    assert %{"version" => 2, "reason" => nil} = second
  end

  test "save is pending until another admin approves", c do
    saved =
      c.ada
      |> call(:post, c.base, %{"document" => document(), "reason" => "Start"})
      |> json_response(201)

    assert saved["data"] == %{"version" => 1, "state" => "pending_approval"}

    data = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"version" => 1, "active_version" => nil, "pending" => %{"version" => 1}} = data

    assert data["pending"]["requested_by"] == %{
             "kind" => "user",
             "id" => c.ada.user_id,
             "name" => "Ada"
           }

    decision = %{"decision" => "approve", "comment" => "Looks right"}
    conn = call(c.ada, :post, c.base <> "/1/decision", decision)
    assert json_response(conn, 409)["error"]["code"] == "reviewer_is_author"

    assert c.bob |> call(:post, c.base <> "/1/decision", decision) |> json_response(200) ==
             %{"data" => %{"version" => 1, "state" => "active"}}

    data = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"active_version" => 1, "pending" => nil} = data

    stale = call(c.ada, :post, c.base, %{"document" => document(), "expected_version" => 7})

    assert %{"code" => "version_conflict", "details" => %{"expected_version" => 1}} =
             json_response(stale, 409)["error"]
  end

  test "a rejected version is not pending and the active document stays shown", c do
    call(c.ada, :post, c.base, %{"document" => document()}) |> json_response(201)

    approve = %{"decision" => "approve", "comment" => "ok"}
    c.bob |> call(:post, c.base <> "/1/decision", approve) |> json_response(200)

    edited = put_in(document(), ["budgets", "max_contacts"], 1001)

    assert call(c.ada, :post, c.base, %{"document" => edited, "expected_version" => 1})
           |> json_response(201)
           |> get_in(["data", "version"]) == 2

    pending = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert pending["pending"]["version"] == 2
    assert pending["pending"]["document"]["budgets"]["max_contacts"] == 1001
    refute pending["document"]["budgets"]["max_contacts"] == 1001

    reject = %{"decision" => "reject", "comment" => "No"}

    assert c.bob |> call(:post, c.base <> "/2/decision", reject) |> json_response(200) ==
             %{"data" => %{"version" => 2, "state" => "rejected"}}

    data = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"version" => 2, "active_version" => 1, "pending" => nil} = data
    assert data["document"] == pending["document"]
  end

  test "invalid fields are reported by path; members can't edit", c do
    bad = put_in(document(), ["horizon", "max_horizon_seconds"], -5)
    conn = call(c.ada, :post, c.base, %{"document" => bad})
    assert %{"code" => "invalid_params", "details" => details} = json_response(conn, 422)["error"]
    assert Map.has_key?(details, "horizon.max_horizon_seconds")

    assert c.mia |> call(:get, c.base) |> json_response(200) |> get_in(["data", "permissions"]) ==
             []

    conn = call(c.mia, :post, c.base, %{"document" => document()})
    assert json_response(conn, 403)["error"]["code"] in ["forbidden"]
  end
end
