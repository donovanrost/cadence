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

  test "save is pending until another admin approves", c do
    saved =
      c.ada
      |> call(:post, c.base, %{"document" => document(), "reason" => "Start"})
      |> json_response(201)

    assert saved["data"] == %{"version" => 1, "state" => "pending_approval"}

    data = c.ada |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"version" => 1, "active_version" => nil, "pending" => %{"version" => 1}} = data

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
