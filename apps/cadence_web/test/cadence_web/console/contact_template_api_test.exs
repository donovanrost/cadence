defmodule CadenceWeb.Console.ContactTemplateAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    crafts =
      for {name, plane} <- [{"SC-1", 1}, {"SC-2", 1}, {"SC-3", 2}] do
        TestFixtures.persist_spacecraft!(mission,
          display_name: name,
          metadata: %{"plane" => plane}
        )
      end

    %{
      admin: admin,
      member: member,
      crafts: crafts,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-planning"
    }
  end

  defp call(user, :get, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp call(user, :post, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  defp body(target, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Plane 1 downlinks",
        "target" => target,
        "document" => %{
          "schedule" => %{
            "type" => "fixed_interval",
            "anchor_at" => "2026-01-01T00:00:00Z",
            "interval_seconds" => 21_600,
            "window_offset_seconds" => 0,
            "window_duration_seconds" => 21_600
          },
          "requirement" => %{
            "service_direction" => "downlink",
            "contact_intent" => "recurring_payload_downlink",
            "success_measure" => "minimum_duration",
            "minimum_duration_seconds" => 300,
            "preferred_duration_seconds" => 300,
            "minimum_data_volume_bytes" => nil,
            "contact_count" => 1,
            "minimum_separation_seconds" => 0,
            "priority" => "routine",
            "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
            "station_constraints_document" => %{"allowed" => [], "excluded" => []},
            "policy_constraints_document" => %{},
            "approval_policy_document" => %{"mode" => "manual"},
            "rationale" => "API test",
            "metadata" => %{}
          },
          "catch_up_policy" => %{
            "maximum_occurrences_per_run" => 8,
            "maximum_lookback_seconds" => 86_400
          }
        }
      },
      overrides
    )
  end

  test "preview, create, read, version and summarize a plane template", c do
    plane = %{"kind" => "plane", "plane" => 1}

    preview =
      c.admin |> call(:post, c.base <> "/templates/preview", body(plane)) |> json_response(200)

    assert %{"spacecraft_count" => 2, "occurrences" => 4, "contacts" => 8, "warnings" => []} =
             preview["data"]

    nobody =
      c.admin
      |> call(:post, c.base <> "/templates/preview", body(%{"kind" => "plane", "plane" => 9}))
      |> json_response(200)

    assert [%{"code" => "applies_to_nobody"}] = nobody["data"]["warnings"]

    created = c.admin |> call(:post, c.base <> "/templates", body(plane)) |> json_response(201)
    assert %{"id" => id, "version" => 1} = created["data"]

    [row] =
      c.member
      |> call(:get, c.base <> "/templates")
      |> json_response(200)
      |> get_in(["data", "templates"])

    assert %{
             "id" => ^id,
             "name" => "Plane 1 downlinks",
             "applies_to" => "plane 1",
             "applies_to_count" => 2,
             "rule_summary" => "1 downlink ≥ 5 min each · every 6h00",
             "target" => ^plane
           } = row

    detail = c.member |> call(:get, c.base <> "/templates/" <> id) |> json_response(200)
    assert detail["data"]["document"]["schedule"]["interval_seconds"] == 21_600

    assert [%{"version" => 1, "actor" => %{"kind" => "user", "name" => "Ada"}}] =
             detail["data"]["versions"]

    stale =
      call(
        c.admin,
        :post,
        c.base <> "/templates/" <> id,
        Map.put(body(plane), "expected_version", 7)
      )

    assert json_response(stale, 409)["error"]["code"] == "version_conflict"

    renamed =
      c.admin
      |> call(:post, c.base <> "/templates/" <> id, %{
        "name" => "Plane 1 (renamed)",
        "expected_version" => 1
      })
      |> json_response(201)

    assert renamed["data"]["version"] == 2

    summary = c.admin |> call(:get, c.base) |> json_response(200) |> Map.fetch!("data")
    assert %{"spacecraft_total" => 3, "covered" => 2} = summary["coverage"]
    assert [%{"group" => "none", "count" => 1}] = summary["not_covered"]
    assert summary["permissions"] == ["planning.edit", "planning.approve"]
  end

  test "bad targets and members are refused; unknown templates are 404", c do
    bad = call(c.admin, :post, c.base <> "/templates", body(%{"kind" => "plane", "plane" => "1"}))
    assert %{"code" => "invalid_params"} = json_response(bad, 422)["error"]

    unknown =
      call(
        c.admin,
        :post,
        c.base <> "/templates",
        body(%{"kind" => "spacecraft_ids", "spacecraft_ids" => ["ghost"]})
      )

    assert %{"code" => "invalid_params", "details" => %{"spacecraft_ids" => ["ghost"]}} =
             json_response(unknown, 422)["error"]

    member =
      call(c.member, :post, c.base <> "/templates", body(%{"kind" => "plane", "plane" => 1}))

    assert json_response(member, 403)["error"]["code"] == "forbidden"

    assert json_response(call(c.admin, :get, c.base <> "/templates/nope"), 404)["error"]["code"] ==
             "template_not_found"
  end
end
