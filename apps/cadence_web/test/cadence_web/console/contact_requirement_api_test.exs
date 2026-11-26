defmodule CadenceWeb.Console.ContactRequirementAPITest do
  @moduledoc "BACKLOG 8g: console one-off contact requirements (list, show, schema, writes)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ContactPlanning.ContactRequirements
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    [sc1, sc2] =
      for name <- ["SC-1", "SC-2"],
          do: TestFixtures.persist_spacecraft!(mission, display_name: name)

    %{
      org: org,
      mission: mission,
      member: member,
      sc1: sc1,
      sc2: sc2,
      base: "/api/v1/missions/#{mission.mission_id}/contact-planning/requirements"
    }
  end

  defp get_json(c, path), do: c.member |> TestFixtures.member_conn() |> get(c.base <> path)

  defp post_json(c, path, body),
    do: c.member |> TestFixtures.member_conn() |> post(c.base <> path, body)

  defp content(spacecraft, overrides) do
    Map.merge(
      %{
        "spacecraft_id" => spacecraft.spacecraft_id,
        "earliest_start" => "2027-01-02T00:00:00Z",
        "latest_end" => "2027-01-02T12:00:00Z",
        "service_direction" => "downlink",
        "success_measure" => "minimum_duration",
        "minimum_duration_seconds" => 300,
        "preferred_duration_seconds" => 600,
        "contact_count" => 2,
        "priority" => "high",
        "rationale" => "Payload dump"
      },
      overrides
    )
  end

  defp create!(c, spacecraft, overrides \\ %{}) do
    response = post_json(c, "", %{"content" => content(spacecraft, overrides)})
    assert %{"id" => id, "version" => 1} = json_response(response, 201)["data"]
    id
  end

  test "the form schema adds the spacecraft, the window and max_gap_seconds", c do
    data = json_response(get_json(c, "/schema"), 200)["data"]
    by_path = Map.new(data["fields"], &{&1["path"], &1})

    assert %{"required" => true, "type" => "reference"} = by_path["spacecraft_id"]
    assert %{"required" => true, "type" => "datetime"} = by_path["latest_end"]
    assert by_path["rationale"]["required"] == true

    assert %{"unit" => "s", "range" => %{"min" => 600, "max" => 604_800}, "advanced" => true} =
             by_path["max_gap_seconds"]

    assert by_path["minimum_duration_seconds"]["visible_when"]["path"] == "success_measure"
    refute Enum.any?(data["fields"], &String.starts_with?(&1["path"], "requirement."))
    assert %{"allowed" => []} = data["defaults"]["provider_constraints_document"]
  end

  test "create, show, list, and a new version: omitted keys carry over, null clears", c do
    id = create!(c, c.sc1)
    _other = create!(c, c.sc2)

    shown = json_response(get_json(c, "/#{id}"), 200)["data"]

    assert %{
             "id" => ^id,
             "state" => "active",
             "version" => 1,
             "template_id" => nil,
             "template_version" => nil,
             "spacecraft" => %{"name" => "SC-1"},
             "content" => %{"contact_count" => 2, "preferred_duration_seconds" => 600},
             "state_changed" => nil,
             "rule_summary" => "2 downlinks ≥ 5 min each",
             "versions" => [%{"version" => 1, "actor" => %{"name" => "Mia"}}]
           } = shown

    sc1 = c.sc1.spacecraft_id

    assert %{"requirements" => [%{"id" => ^id}], "next_page" => nil} =
             json_response(get_json(c, "?spacecraft_id=#{sc1}&state=active"), 200)["data"]

    assert %{"requirements" => []} =
             json_response(get_json(c, "?source=template"), 200)["data"]

    assert %{"requirements" => [_], "next_page" => 2} =
             json_response(get_json(c, "?source=one_off&limit=1"), 200)["data"]

    response =
      post_json(c, "/#{id}", %{
        "expected_version" => 1,
        "content" => %{"priority" => "critical", "preferred_duration_seconds" => nil}
      })

    assert %{"id" => ^id, "version" => 2} = json_response(response, 201)["data"]

    assert %{"version" => 2, "content" => content, "versions" => [%{"version" => 2}, _v1]} =
             json_response(get_json(c, "/#{id}"), 200)["data"]

    # Changed, cleared by an explicit null, and carried over when omitted.
    assert content["priority"] == "critical"
    assert content["preferred_duration_seconds"] == nil
    assert content["contact_count"] == 2

    # The newest change lists first.
    assert %{"requirements" => [%{"id" => ^id} | _]} = json_response(get_json(c, ""), 200)["data"]
  end

  test "a stale expected_version is a conflict that names the current one", c do
    id = create!(c, c.sc1)

    assert json_response(
             post_json(c, "/#{id}", %{"expected_version" => 1, "content" => %{}}),
             201
           )

    response = post_json(c, "/#{id}", %{"expected_version" => 1, "content" => %{}})

    assert %{"code" => "version_conflict", "details" => %{"expected_version" => 2}} =
             json_response(response, 409)["error"]
  end

  test "validation is 422 keyed by field", c do
    invalid = fn body -> json_response(post_json(c, "", body), 422)["error"]["details"] end

    assert %{"latest_end" => _} =
             invalid.(%{"content" => content(c.sc1, %{"latest_end" => "2027-01-01T00:00:00Z"})})

    assert %{"content.bogus" => "unknown field"} =
             invalid.(%{"content" => content(c.sc1, %{"bogus" => 1})})

    assert %{"spacecraft_id" => "unknown spacecraft"} =
             invalid.(%{"content" => content(c.sc1, %{"spacecraft_id" => "spacecraft-nope"})})

    assert %{"content" => _} = invalid.(%{"content" => "nope"})

    assert %{"rationale" => _} =
             invalid.(%{"content" => Map.delete(content(c.sc1, %{}), "rationale")})

    assert %{"state" => _} = json_response(get_json(c, "?state=paused"), 422)["error"]["details"]

    id = create!(c, c.sc1)

    assert %{"expected_version" => _} =
             json_response(post_json(c, "/#{id}", %{"content" => %{}}), 422)["error"]["details"]
  end

  test "close and cancel are final, need a reason, and say who ended it", c do
    id = create!(c, c.sc1)

    assert %{"reason" => "is required"} =
             json_response(
               post_json(c, "/#{id}/close", %{"expected_version" => 1, "reason" => " "}),
               422
             )[
               "error"
             ]["details"]

    too_long = String.duplicate("x", 2_001)

    assert %{"reason" => "must be at most 2000 characters"} =
             json_response(
               post_json(c, "/#{id}/close", %{"expected_version" => 1, "reason" => too_long}),
               422
             )["error"]["details"]

    assert %{"details" => %{"expected_version" => 1}} =
             json_response(
               post_json(c, "/#{id}/close", %{"expected_version" => 3, "reason" => "x"}),
               409
             )[
               "error"
             ]

    assert %{"id" => ^id, "state" => "closed", "version" => 1} =
             json_response(
               post_json(c, "/#{id}/close", %{"expected_version" => 1, "reason" => "Done"}),
               200
             )[
               "data"
             ]

    assert %{
             "state" => "closed",
             "state_changed" => %{"reason" => "Done", "by" => %{"name" => "Mia"}, "at" => _}
           } = json_response(get_json(c, "/#{id}"), 200)["data"]

    # Final: neither cancel nor a new version applies, and the 409 says how it ended.
    for {path, body} <- [
          {"/#{id}/cancel", %{"expected_version" => 1, "reason" => "Oops"}},
          {"/#{id}", %{"expected_version" => 1, "content" => %{}}}
        ] do
      assert %{
               "code" => "requirement_not_active",
               "details" => %{
                 "state" => "closed",
                 "state_changed" => %{"by" => %{"name" => "Mia"}}
               }
             } = json_response(post_json(c, path, body), 409)["error"]
    end

    other = create!(c, c.sc2)

    assert %{"state" => "canceled"} =
             json_response(
               post_json(c, "/#{other}/cancel", %{
                 "expected_version" => 1,
                 "reason" => "Withdrawn"
               }),
               200
             )[
               "data"
             ]

    assert %{"requirements" => [%{"id" => ^other, "state_changed" => %{"reason" => "Withdrawn"}}]} =
             json_response(get_json(c, "?state=canceled"), 200)["data"]

    # Nothing is active any more.
    assert %{"requirements" => []} = json_response(get_json(c, "?state=active"), 200)["data"]
  end

  test "null constraint lists mean no constraint (qa P4: Advanced untouched)", c do
    untouched = %{"allowed" => nil, "excluded" => nil}

    id =
      create!(c, c.sc1, %{
        "provider_constraints_document" => untouched,
        "station_constraints_document" => nil
      })

    assert %{"provider_constraints_document" => %{"allowed" => [], "excluded" => []}} =
             json_response(get_json(c, "/#{id}"), 200)["data"]["content"]
  end

  test "max_gap_seconds round-trips; null clears it; out of range is 422 on the field", c do
    id = create!(c, c.sc1, %{"max_gap_seconds" => 3_600})

    assert %{"content" => %{"max_gap_seconds" => 3_600}, "rule_summary" => summary} =
             json_response(get_json(c, "/#{id}"), 200)["data"]

    assert summary == "2 downlinks ≥ 5 min each · gaps ≤ 1h00"

    assert json_response(
             post_json(c, "/#{id}", %{
               "expected_version" => 1,
               "content" => %{"max_gap_seconds" => nil}
             }),
             201
           )

    assert %{
             "content" => %{"max_gap_seconds" => nil},
             "rule_summary" => "2 downlinks ≥ 5 min each"
           } =
             json_response(get_json(c, "/#{id}"), 200)["data"]

    for {gap, message} <- [
          {60, "must be between 600 and 604800 seconds"},
          # The window is 12 h.
          {86_400, "must not be longer than the window"}
        ] do
      response = post_json(c, "", %{"content" => content(c.sc1, %{"max_gap_seconds" => gap})})
      assert %{"max_gap_seconds" => ^message} = json_response(response, 422)["error"]["details"]
    end
  end

  test "by-template counts a day's generated requirements per template, active ones too", c do
    admin_user = TestFixtures.persist_user!(display_name: "Ada")
    TestFixtures.grant_membership!(admin_user, c.org, role: :organization_admin)

    {:ok, admin} =
      Cadence.Auth.authenticate_browser_session(TestFixtures.member_session_token!(admin_user),
        current_organization_id: c.org.organization_id
      )

    template_id = template!(c, admin_user)

    ids =
      for sc <- [c.sc1, c.sc2] do
        {:ok, requirement, _version} =
          ContactRequirements.create(admin, c.mission.mission_id, %{
            "spacecraft_id" => sc.spacecraft_id,
            "earliest_start" => "2030-06-01T06:00:00Z",
            "latest_end" => "2030-06-01T12:00:00Z",
            "contact_intent" => "recurring_payload_downlink",
            "rationale" => "Generated",
            "metadata" => %{"generation" => %{"contact_requirement_template_id" => template_id}}
          })

        requirement.contact_requirement_id
      end

    assert json_response(
             post_json(c, "/#{hd(ids)}/cancel", %{
               "expected_version" => 1,
               "reason" => "Not needed"
             }),
             200
           )

    # A one-off the same day isn't a template's.
    _one_off =
      create!(c, c.sc1, %{
        "earliest_start" => "2030-06-01T01:00:00Z",
        "latest_end" => "2030-06-01T03:00:00Z"
      })

    assert %{
             "day" => "2030-06-01",
             "templates" => [
               %{
                 "template" => %{
                   "id" => ^template_id,
                   "name" => "Daily dump",
                   "state" => "active"
                 },
                 "count" => 2,
                 "active_count" => 1
               }
             ]
           } = json_response(get_json(c, "/by-template?day=2030-06-01"), 200)["data"]

    assert %{"templates" => []} =
             json_response(get_json(c, "/by-template?day=2030-06-02"), 200)["data"]

    assert %{"day" => _} =
             json_response(get_json(c, "/by-template?day=June"), 422)["error"]["details"]

    # The list's source filter agrees.
    assert %{"requirements" => [_, _]} =
             json_response(get_json(c, "?source=template"), 200)["data"]
  end

  defp template!(c, admin_user) do
    body = %{
      "name" => "Daily dump",
      "target" => %{"kind" => "spacecraft_ids", "spacecraft_ids" => [c.sc1.spacecraft_id]},
      "document" => %{
        "schedule" => %{
          "type" => "fixed_interval",
          "anchor_at" => "2030-01-01T00:00:00Z",
          "interval_seconds" => 86_400,
          "window_offset_seconds" => 0,
          "window_duration_seconds" => 21_600
        },
        "requirement" => %{
          "service_direction" => "downlink",
          "contact_intent" => "recurring_payload_downlink",
          "success_measure" => "minimum_duration",
          "minimum_duration_seconds" => 300,
          "contact_count" => 1,
          "minimum_separation_seconds" => 0,
          "priority" => "routine"
        },
        "catch_up_policy" => %{
          "maximum_occurrences_per_run" => 8,
          "maximum_lookback_seconds" => 86_400
        }
      }
    }

    admin_user
    |> TestFixtures.member_conn()
    |> post("/api/v1/missions/#{c.mission.mission_id}/contact-planning/templates", body)
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  test "an unknown requirement is 404", c do
    assert %{"code" => "requirement_not_found"} =
             json_response(get_json(c, "/contact_requirement-nope"), 404)["error"]

    assert %{"code" => "requirement_not_found"} =
             json_response(
               post_json(c, "/contact_requirement-nope", %{
                 "expected_version" => 1,
                 "content" => %{}
               }),
               404
             )["error"]
  end
end
