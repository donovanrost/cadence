defmodule CadenceWeb.Console.CommandGroupAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{CommandAuthoringFixtures, ExactCommandAuthoringFixtures}
  alias Cadence.Reads.CommandGroups
  alias CadenceWeb.Console.CommandGroupJSON
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    requester = TestFixtures.persist_user!(display_name: "Requester")
    approver = TestFixtures.persist_user!(display_name: "Approver")
    TestFixtures.grant_membership!(requester, org, role: :organization_admin)
    TestFixtures.grant_membership!(approver, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    crafts =
      for i <- 1..2 do
        craft = TestFixtures.persist_spacecraft!(mission, display_name: "SC-#{i}")

        endpoint =
          CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
            spacecraft_id: craft.spacecraft_id
          })

        # A booked pass with a confirmed uplink, so preflight's hard contact HOLD clears (#60).
        Cadence.CommandGroupFixtures.commandable_pass!(
          org.organization_id,
          mission.mission_id,
          craft.spacecraft_id
        )

        {craft.spacecraft_id, endpoint.source_endpoint_id}
      end

    %{
      org: org,
      requester: requester,
      approver: approver,
      mission: mission,
      ids: model.commands_by_name,
      crafts: crafts
    }
  end

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}"

  # #117 step 4a: a GO carries the review token the decider saw, read from the group itself.
  defp go(c, id, extra \\ %{}) do
    data = c.approver |> as() |> get(base(c) <> "/command-groups/#{id}") |> json_response(200)
    Map.merge(%{"kind" => "go", "expected_review" => data["data"]["review_token"]}, extra)
  end

  defp as(user), do: TestFixtures.member_conn(user)

  defp body(c, command, args, extra \\ %{}) do
    Map.merge(
      %{
        "title" => "Load shed",
        "targets" =>
          Enum.map(c.crafts, fn {id, endpoint} ->
            %{"spacecraft_id" => id, "source_endpoint_id" => endpoint}
          end),
        "commands" => [
          %{"command_id" => c.ids[command], "argument_values_json" => Jason.encode!(args)}
        ]
      },
      extra
    )
  end

  defp preflight(c, body),
    do:
      as(c.requester) |> post(base(c) <> "/command-groups/preflight", body) |> json_response(200)

  # Submits with the preflight's digest, acknowledging every acknowledgeable HOLD it shows.
  defp create(c, body) do
    pre = preflight(c, body)["data"]

    acks =
      for %{"result" => "hold", "ackable" => true} = check <- pre["checks"],
          do: %{"key" => check["key"], "hold_basis" => check["hold_basis"], "note" => "Seen."}

    as(c.requester)
    |> post(
      base(c) <> "/command-groups",
      Map.merge(body, %{"preflight_digest" => pre["digest"], "acknowledged_holds" => acks})
    )
  end

  defp submit_raw(c, body, acks) do
    pre = preflight(c, body)["data"]

    as(c.requester)
    |> post(
      base(c) <> "/command-groups",
      Map.merge(body, %{"preflight_digest" => pre["digest"], "acknowledged_holds" => acks})
    )
  end

  describe "HOLDs hold (DECISIONS #60)" do
    test "an unacknowledged conflicts HOLD refuses the submit; acknowledging it arms and audits",
         c do
      first = body(c, "SET_SIGNED", %{"counter" => 1})
      assert json_response(create(c, first), 201)

      second = body(c, "SET_SIGNED", %{"counter" => 2})
      pre = preflight(c, second)["data"]

      assert %{"result" => "hold", "ackable" => true, "hold_basis" => basis} =
               Enum.find(pre["checks"], &(&1["key"] == "conflicts"))

      assert %{"result" => "go", "ackable" => nil} =
               Enum.find(pre["checks"], &(&1["key"] == "contact"))

      assert %{
               "error" => %{
                 "code" => "holds_unacknowledged",
                 "details" => %{"holds" => [%{"key" => "conflicts", "ackable" => true}]}
               }
             } = c |> submit_raw(second, []) |> json_response(422)

      # An acknowledgement of a different basis (a changed HOLD) doesn't count.
      stale = [%{"key" => "conflicts", "hold_basis" => "stale", "note" => "Seen."}]

      assert %{"error" => %{"code" => "holds_unacknowledged"}} =
               c |> submit_raw(second, stale) |> json_response(422)

      assert %{
               "error" => %{"code" => "invalid_params", "details" => %{"acknowledged_holds" => _}}
             } =
               c
               |> submit_raw(second, [
                 %{"key" => "conflicts", "hold_basis" => basis, "note" => " "}
               ])
               |> json_response(422)

      ack = [
        %{"key" => "conflicts", "hold_basis" => basis, "note" => "Queued behind the load shed."}
      ]

      assert %{"data" => %{"events" => events}} =
               c |> submit_raw(second, ack) |> json_response(201)

      assert %{
               "kind" => "hold_acknowledged",
               "actor" => %{"actor_kind" => "user"},
               "payload" => %{
                 "key" => "conflicts",
                 "note" => "Queued behind the load shed.",
                 "hold_basis" => ^basis,
                 "preflight_digest" => digest
               }
             } = Enum.find(events, &(&1["kind"] == "hold_acknowledged"))

      assert is_binary(digest)
    end

    test "no commandable contact in the release window is a hard HOLD", c do
      # After every booked pass ends: nothing can release in the window.
      late = DateTime.utc_now() |> DateTime.add(2 * 86_400) |> DateTime.to_iso8601()
      draft = body(c, "SET_SIGNED", %{"counter" => 1}, %{"not_before" => late})
      pre = preflight(c, draft)["data"]

      assert %{
               "result" => "hold",
               "ackable" => false,
               "hold_basis" => basis,
               "per_target" => [%{"reason" => "no_commandable_contact"} | _]
             } = Enum.find(pre["checks"], &(&1["key"] == "contact"))

      ack = [%{"key" => "contact", "hold_basis" => basis, "note" => "Will book one."}]

      assert %{"error" => %{"code" => "holds_unacknowledged", "details" => %{"holds" => holds}}} =
               c |> submit_raw(draft, ack) |> json_response(422)

      assert [%{"key" => "contact", "ackable" => false}] = holds
    end

    test "two_person is not a HOLD: it reads second_go until the second GO", c do
      pre = preflight(c, body(c, "SET_COUNTER", %{"amount" => 1}, %{"log_entry" => "x"}))["data"]
      assert pre["second_go_required"] == true

      assert %{"result" => "second_go", "ackable" => nil} =
               Enum.find(pre["checks"], &(&1["key"] == "two_person"))
    end

    test "GO carries the submitter's ack while the HOLD is unchanged (#61)", c do
      assert json_response(create(c, body(c, "SET_SIGNED", %{"counter" => 1})), 201)

      # Submitted behind the queued group, acknowledging the conflicts HOLD.
      pending = body(c, "SET_COUNTER", %{"amount" => 1}, %{"log_entry" => "x"})
      %{"data" => %{"id" => id}} = c |> create(pending) |> json_response(201)

      assert %{"data" => %{"state" => "queued", "events" => events}} =
               as(c.approver)
               |> post(base(c) <> "/command-groups/#{id}/decision", go(c, id))
               |> json_response(200)

      # Only the submitter's acknowledgement; the approver needed none.
      assert [%{"actor" => %{"user_id" => requester_id}}] =
               Enum.filter(events, &(&1["kind"] == "hold_acknowledged"))

      assert requester_id == c.requester.user_id
    end

    test "a HOLD new since submit needs the approver's own ack at GO (#61)", c do
      pending = body(c, "SET_COUNTER", %{"amount" => 1}, %{"log_entry" => "x"})
      %{"data" => %{"id" => id}} = c |> create(pending) |> json_response(201)

      # More work lands on the same lanes after the submit.
      assert json_response(create(c, body(c, "SET_SIGNED", %{"counter" => 1})), 201)

      go = as(c.approver) |> post(base(c) <> "/command-groups/#{id}/decision", go(c, id))

      assert %{"error" => %{"code" => "holds_unacknowledged", "details" => %{"holds" => holds}}} =
               json_response(go, 422)

      assert [%{"key" => "conflicts", "ackable" => true, "hold_basis" => basis}] = holds

      ack = [
        %{"key" => "conflicts", "hold_basis" => basis, "note" => "The load shed goes first."}
      ]

      assert %{"data" => %{"state" => "queued", "events" => events}} =
               as(c.approver)
               |> post(
                 base(c) <> "/command-groups/#{id}/decision",
                 go(c, id, %{"acknowledged_holds" => ack})
               )
               |> json_response(200)

      assert %{
               "actor" => %{"user_id" => approver_id},
               "payload" => %{"key" => "conflicts", "at_decision" => true}
             } = Enum.find(events, &(&1["kind"] == "hold_acknowledged"))

      assert approver_id == c.approver.user_id
    end
  end

  test "a plain member submits a small group and it's queued; another member GOes a hazardous one (#62)",
       c do
    org = Cadence.Organizations.fetch_organization(c.mission.organization_id) |> elem(1)
    member = TestFixtures.persist_user!(display_name: "Plain Member")
    second = TestFixtures.persist_user!(display_name: "Second Member")
    TestFixtures.grant_membership!(member, org, role: :member)
    TestFixtures.grant_membership!(second, org, role: :member)

    small = body(c, "SET_SIGNED", %{"counter" => 1})
    pre = as(member) |> post(base(c) <> "/command-groups/preflight", small) |> json_response(200)

    assert %{"data" => %{"state" => "queued", "requested_by" => %{"user_id" => requester}}} =
             as(member)
             |> post(
               base(c) <> "/command-groups",
               Map.put(small, "preflight_digest", pre["data"]["digest"])
             )
             |> json_response(201)

    assert requester == member.user_id

    hazardous = body(c, "SET_COUNTER", %{"amount" => 1}, %{"log_entry" => "x"})

    pre =
      as(member) |> post(base(c) <> "/command-groups/preflight", hazardous) |> json_response(200)

    acks =
      for %{"result" => "hold", "ackable" => true} = check <- pre["data"]["checks"],
          do: %{"key" => check["key"], "hold_basis" => check["hold_basis"], "note" => "Seen."}

    %{"data" => %{"id" => id, "state" => "approval_pending"}} =
      as(member)
      |> post(
        base(c) <> "/command-groups",
        Map.merge(hazardous, %{
          "preflight_digest" => pre["data"]["digest"],
          "acknowledged_holds" => acks
        })
      )
      |> json_response(201)

    assert %{"error" => %{"code" => "command_group_self_approval_not_allowed"}} =
             as(member)
             |> post(base(c) <> "/command-groups/#{id}/decision", go(c, id))
             |> json_response(403)

    assert %{"data" => %{"state" => "queued"}} =
             as(second)
             |> post(base(c) <> "/command-groups/#{id}/decision", go(c, id))
             |> json_response(200)
  end

  test "M26 verifier series: honest when there's nothing to plot; unknown groups 404", c do
    %{"data" => %{"id" => id}} =
      c |> create(body(c, "SET_SIGNED", %{"counter" => 1})) |> json_response(201)

    assert %{
             "data" => %{
               "point" => nil,
               "reason" => reason,
               "targets" => [],
               "target_count" => 2,
               "truncated" => false,
               "summary" => %{"met" => 0, "not_met" => 0, "pending" => 0},
               "telemetry" => "ok",
               "verifier" => %{"position" => 0, "command_name" => _}
             }
           } =
             as(c.requester)
             |> get(base(c) <> "/command-groups/#{id}/verifier-series")
             |> json_response(200)

    assert reason in ["verified_by_uplink_acknowledgement", "no_verifier"]

    assert %{"error" => %{"code" => "command_group_not_found"}} =
             as(c.requester)
             |> get(base(c) <> "/command-groups/nope/verifier-series")
             |> json_response(404)
  end

  test "preflight, submit and show a routine group", c do
    pre = preflight(c, body(c, "SET_SIGNED", %{"counter" => 1}))["data"]
    assert pre["valid"] == true
    assert pre["members"] == 2
    assert Enum.find(pre["checks"], &(&1["key"] == "two_person"))["result"] == "go"

    data =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 1}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert data["state"] == "queued"
    assert [%{"stage" => "queued_for_contact", "members" => [_]}, _] = data["targets"]
    assert [%{"argument_values_json" => ~s({"counter":1})}] = data["commands"]
    assert is_binary(data["review_token"])
  end

  # #795: the show carries the first pages and their totals; `targets` and `events` page the rest.
  test "a group's targets and events are paged, filtered, and bound to their group", c do
    group =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 1}))
      |> json_response(201)
      |> Map.fetch!("data")

    id = group["id"]
    [{first_id, _}, {second_id, _}] = c.crafts

    assert %{"total" => 2, "next_cursor" => nil, "revision" => revision} = group["targets_page"]
    assert is_integer(revision)
    assert [%{"index" => 0, "spacecraft_id" => ^first_id}, %{"index" => 1}] = group["targets"]
    assert %{"total" => 1, "next_cursor" => nil} = group["events_page"]
    assert [%{"kind" => "submitted"}] = group["events"]

    # The paged variants the console moves onto: the first pages, and a push without the lists.
    {:ok, view} =
      CommandGroups.get(c.org.organization_id, c.mission.mission_id, id, nil)

    assert [%{index: 0}, %{index: 1}] =
             CommandGroupJSON.show_first_page(view).targets

    pushed = CommandGroupJSON.push(view)
    refute Map.has_key?(pushed, :targets) or Map.has_key?(pushed, :events)
    assert %{total: 2} = pushed.targets_page
    assert %{total: 1} = pushed.events_page
    assert pushed.progress == %{queued_for_contact: 2}

    page = fn query ->
      as(c.requester)
      |> get(base(c) <> "/command-groups/#{id}/targets" <> query)
      |> json_response(200)
    end

    assert %{
             "data" => %{"targets" => [%{"spacecraft_id" => ^first_id}]},
             "meta" => %{"total" => 2, "next_cursor" => cursor}
           } = page.("?limit=1")

    assert %{
             "data" => %{"targets" => [%{"spacecraft_id" => ^second_id}]},
             "meta" => %{"total" => 2, "next_cursor" => nil}
           } = page.("?limit=1&cursor=#{cursor}")

    assert %{
             "data" => %{"targets" => [%{"spacecraft_id" => ^second_id}]},
             "meta" => %{"total" => 1}
           } =
             page.("?stage=queued_for_contact&q=#{second_id}")

    assert %{"data" => %{"targets" => []}, "meta" => %{"total" => 0}} = page.("?stage=verified")

    assert %{"data" => %{"events" => [%{"kind" => "submitted"}]}, "meta" => %{"total" => 1}} =
             as(c.requester)
             |> get(base(c) <> "/command-groups/#{id}/events?limit=1")
             |> json_response(200)

    # A cursor belongs to its group and its list: anywhere else it's a 422, never another page.
    other =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 2}, %{"operation_id" => "second"}))
      |> json_response(201)
      |> get_in(["data", "id"])

    for path <- ["/command-groups/#{other}/targets", "/command-groups/#{id}/events"] do
      assert %{"error" => %{"code" => "invalid_params", "details" => %{"cursor" => _}}} =
               as(c.requester)
               |> get(base(c) <> path <> "?cursor=#{cursor}")
               |> json_response(422)
    end

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"limit" => _}}} =
             as(c.requester)
             |> get(base(c) <> "/command-groups/#{id}/targets?limit=0")
             |> json_response(422)

    assert %{"error" => %{"code" => "command_group_not_found"}} =
             as(c.requester)
             |> get(base(c) <> "/command-groups/nope/targets")
             |> json_response(404)

    # Another mission's group is not found, whatever the cursor.
    foreign = TestFixtures.persist_mission!(c.org)

    assert %{"error" => %{"code" => code}} =
             as(c.requester)
             |> get(
               "/api/v1/missions/#{foreign.mission_id}/command-groups/#{id}/targets?cursor=#{cursor}"
             )
             |> json_response(404)

    assert code in ["command_group_not_found", "mission_not_found"]
  end

  test "per-target values override the command's for those targets and are echoed back", c do
    [{first, _}, {second, _}] = c.crafts
    same = body(c, "SET_SIGNED", %{"counter" => 1})

    per_target =
      update_in(same, ["commands", Access.at(0)], fn command ->
        Map.put(command, "per_target", [
          %{"spacecraft_id" => second, "argument_values_json" => ~s({"counter":2})}
        ])
      end)

    # The digest covers each member's values, so the override changes it.
    refute preflight(c, same)["data"]["digest"] == preflight(c, per_target)["data"]["digest"]

    data = c |> create(per_target) |> json_response(201) |> Map.fetch!("data")

    assert [%{"argument_values_json" => ~s({"counter":1}), "per_target" => [override]}] =
             data["commands"]

    assert override == %{"spacecraft_id" => second, "argument_values_json" => ~s({"counter":2})}
    refute override["spacecraft_id"] == first

    duplicate =
      put_in(per_target, ["commands", Access.at(0), "per_target"], [
        %{"spacecraft_id" => second, "argument_values_json" => "{}"},
        %{"spacecraft_id" => second, "argument_values_json" => "{}"}
      ])

    assert as(c.requester)
           |> post(base(c) <> "/command-groups/preflight", duplicate)
           |> json_response(422)
  end

  test "a hazardous group goes through the second operator's GO", c do
    data =
      c
      |> create(body(c, "SET_COUNTER", %{"amount" => 2}, %{"log_entry" => "Reset"}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert data["state"] == "approval_pending"
    id = data["id"]

    assert %{"error" => %{"code" => "command_group_self_approval_not_allowed"}} =
             as(c.requester)
             |> post(base(c) <> "/command-groups/#{id}/decision", go(c, id))
             |> json_response(403)

    assert %{
             "data" => %{
               "groups" => [
                 %{"id" => ^id, "awaiting_me" => true, "progress" => nil, "finished" => nil}
               ]
             }
           } =
             as(c.approver)
             |> get(base(c) <> "/command-groups?awaiting_me=true")
             |> json_response(200)

    review =
      as(c.approver) |> get(base(c) <> "/command-groups/#{id}/preflight") |> json_response(200)

    assert Enum.find(review["data"]["checks"], &(&1["key"] == "changed_since_submit"))["result"] ==
             "go"

    decided =
      as(c.approver)
      |> post(base(c) <> "/command-groups/#{id}/decision", %{
        "kind" => "go",
        "expected_review" => data["review_token"]
      })
      |> json_response(200)

    assert decided["data"]["state"] == "queued"
  end

  test "abort, cancel and policies", c do
    data =
      c
      |> create(body(c, "SET_SIGNED", %{"counter" => 3}))
      |> json_response(201)
      |> Map.fetch!("data")

    [%{"members" => [%{"request_id" => request_id}]} | _] = data["targets"]

    assert %{"data" => %{"state" => "canceled"}} =
             as(c.approver)
             |> post(base(c) <> "/command-requests/#{request_id}/cancel", %{
               "reason" => "Not needed"
             })
             |> json_response(200)

    aborted =
      as(c.approver)
      |> post(base(c) <> "/command-groups/#{data["id"]}/abort", %{"reason" => "Stand down"})
      |> json_response(200)

    assert aborted["data"]["state"] == "aborted"
    assert aborted["data"]["abort_result"] == %{"canceled" => 1, "already_started" => []}

    noted =
      as(c.requester)
      |> post(base(c) <> "/command-groups/#{data["id"]}/notes", %{
        "note" => "Logged for the shift"
      })
      |> json_response(200)

    assert Enum.any?(noted["data"]["events"], &(&1["kind"] == "note"))

    assert %{"error" => %{"code" => "note_required"}} =
             as(c.requester)
             |> post(base(c) <> "/command-groups/#{data["id"]}/notes", %{"note" => " "})
             |> json_response(422)

    assert %{"data" => %{"policies" => policies}} =
             as(c.requester) |> get(base(c) <> "/command-policies") |> json_response(200)

    assert %{"parameters" => %{"threshold" => 10}} =
             Enum.find(policies, &(&1["key"] == "fleet_reach"))
  end

  test "errors: stale preflight, bad params, replay, unknown group", c do
    stale =
      as(c.requester)
      |> post(
        base(c) <> "/command-groups",
        Map.put(body(c, "SET_SIGNED", %{"counter" => 1}), "preflight_digest", "old")
      )

    assert %{"error" => %{"code" => "preflight_stale"}} = json_response(stale, 409)

    bad =
      as(c.requester)
      |> post(base(c) <> "/command-groups/preflight", %{"targets" => [], "commands" => []})

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"targets" => _}}} =
             json_response(bad, 422)

    replay = body(c, "SET_SIGNED", %{"counter" => 4}, %{"operation_id" => "op-9"})
    assert json_response(create(c, replay), 201)

    assert %{
             "error" => %{
               "code" => "duplicate_operation",
               "details" => %{"command_group_id" => _}
             }
           } = json_response(create(c, replay), 409)

    assert %{
             "data" => %{
               "groups" => [%{"state" => "queued", "progress" => progress, "finished" => false}]
             }
           } =
             as(c.requester)
             |> get(base(c) <> "/command-groups?operation_id=op-9")
             |> json_response(200)

    # Rows carry delivery too (qa #28): nothing has reached its contact yet.
    assert [{"queued_for_contact", _count}] = Map.to_list(progress)

    assert %{"error" => %{"code" => "command_group_not_found"}} =
             as(c.requester) |> get(base(c) <> "/command-groups/nope") |> json_response(404)
  end

  test "command endpoints by POST: a list in the body, each id once, no silent cut", c do
    [{id, endpoint} | _] = c.crafts

    data =
      as(c.requester)
      |> post(base(c) <> "/command-endpoints", %{"spacecraft_ids" => [id, id]})
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"spacecraft_id" => ^id, "endpoints" => [%{"id" => ^endpoint}]}] =
             data["spacecraft"]

    Application.put_env(:cadence, :command_group_bounds, max_targets: 2)
    on_exit(fn -> Application.delete_env(:cadence, :command_group_bounds) end)

    assert %{
             "error" => %{
               "code" => "command_group_too_large",
               "details" => %{"max_targets" => 2, "targets" => 3}
             }
           } =
             as(c.requester)
             |> post(base(c) <> "/command-endpoints", %{"spacecraft_ids" => ["a", "b", "c"]})
             |> json_response(422)

    assert %{"error" => %{"code" => "invalid_params"}} =
             as(c.requester)
             |> post(base(c) <> "/command-endpoints", %{"spacecraft_ids" => ["a", 7]})
             |> json_response(422)

    # The GET (until the console moves off it) is just as loud.
    assert %{"error" => %{"code" => "command_group_too_large"}} =
             as(c.requester)
             |> get(base(c) <> "/command-endpoints?spacecraft_ids=a,b,c")
             |> json_response(422)
  end

  test "command endpoints: route resolution and candidates per spacecraft", c do
    [{id, endpoint} | _] = c.crafts

    data =
      as(c.requester)
      |> get(base(c) <> "/command-endpoints?spacecraft_ids=#{id}")
      |> json_response(200)
      |> Map.fetch!("data")

    # The fixture spacecraft have endpoints but no routing rules.
    assert [
             %{
               "spacecraft_id" => ^id,
               "failure" => "no_uplink_route",
               "resolved_source_endpoint_id" => nil
             } = row
           ] =
             data["spacecraft"]

    assert [%{"id" => ^endpoint, "managed" => false}] = row["endpoints"]

    # Without an explicit endpoint, preflight says the same thing.
    pre =
      preflight(
        c,
        Map.put(body(c, "SET_SIGNED", %{"counter" => 1}), "targets", [%{"spacecraft_id" => id}])
      )

    identity = Enum.find(pre["data"]["checks"], &(&1["key"] == "identity"))

    assert %{
             "result" => "no_go",
             "per_target" => [%{"reason" => "no_uplink_route", "routes" => []}]
           } = identity
  end
end
