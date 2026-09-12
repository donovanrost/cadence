defmodule CadenceWeb.OpsRequirementTemplatePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.OpsConsole.Actions.RequirementTemplateInput
  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirementTemplates, as: Templates
  alias Cadence.Reads.ApplicationSurfaces.Planning.TemplateLedger
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-requirements/template-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    craft =
      Spacecraft.new(%{
        spacecraft_id: Cadence.Ids.new("spacecraft"),
        mission_id: mission.mission_id,
        display_name: "Template spacecraft"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    %{
      org: org,
      user: user,
      scope: scope,
      mission: mission,
      craft: craft,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/requirement-templates"
    }
  end

  test "native form validation creates no rows and its creation receipt binds the actual version",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.requirement-templates"
    assert original["data"]["model"]["can_manage"]
    calls = native(%{snapshot: original, action: "create-template"})
    assert length(calls) == 3

    operations =
      Enum.map(calls, fn [event, input] ->
        op = action(view, c.path, original, event, input)["snapshot"]
        assert op["status"] == "completed"

        if event == "validate-template" do
          assert rows(c) == []
        end

        op
      end)

    [{template, version}] = rows(c)
    receipt = List.last(operations)
    assert receipt["receipt"]["result"]["reference"] == Templates.reference(template, version)

    assert calls ==
             native(%{snapshot: original, action: "create-template", operations: operations})

    [event, input] = List.last(calls)
    assert action(view, c.path, original, event, input)["snapshot"]["status"] == "rejected"
    assert length(rows(c)) == 1
    refreshed = read(view, c.path, original)["snapshot"]
    assert refreshed["data"]["operation"] == receipt
    assert refreshed["data"]["model"]["defaults"] == original["data"]["model"]["defaults"]
    assert page(view) == original
  end

  test "native lifecycle actions use displayed evidence and admit real pause, activation and closure receipts",
       c do
    {template, _} = create(c)
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for event <- ~w(pause-template activate-template close-template) do
      current = read(view, c.path, original)["snapshot"]
      [[^event, input]] = native(%{snapshot: current, action: event})

      assert input["payload"]["reference"] ==
               hd(current["data"]["model"]["templates"]["entries"])["reference"]

      receipt = action(view, c.path, original, event, input)["snapshot"]
      assert receipt["status"] == "completed"

      assert [[event, input]] ==
               native(%{snapshot: current, action: event, operations: [receipt]})

      assert action(view, c.path, original, event, input)["snapshot"]["status"] == "rejected"

      {:ok, updated, version} =
        Templates.fetch(
          c.org.organization_id,
          c.mission.mission_id,
          template.contact_requirement_template_id
        )

      assert receipt["receipt"]["result"]["reference"] == Templates.reference(updated, version)
    end

    assert [{%{lifecycle_state: :closed}, _}] = rows(c)
  end

  test "reviewed evidence rejects same-version lifecycle changes and concurrent duplicate decisions under the lock",
       c do
    {template, version} = create(c)
    reference = Templates.reference(template, version)
    id = template.contact_requirement_template_id

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Templates.pause(c.scope, c.mission.mission_id, id, 1, "Reviewed pause",
            reviewed_evidence: reference
          )
        end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, :stale_contact_requirement_template_evidence}, &1)
           ) == 1

    assert {:ok, _} = Templates.activate(c.scope, c.mission.mission_id, id, 1, "Other activation")

    assert {:error, :stale_contact_requirement_template_evidence} =
             Templates.pause(c.scope, c.mission.mission_id, id, 1, "Old reviewed state",
               reviewed_evidence: reference
             )

    {:ok, current, current_version} =
      Templates.fetch(c.org.organization_id, c.mission.mission_id, id)

    current_reference = Templates.reference(current, current_version)

    assert {:ok, _, _} =
             Templates.version(c.scope, c.mission.mission_id, id, 1, %{
               catch_up_policy_document: %{
                 "maximum_occurrences_per_run" => 2,
                 "maximum_lookback_seconds" => 3600
               }
             })

    assert {:error, :stale_contact_requirement_template_version} =
             Templates.close(c.scope, c.mission.mission_id, id, 1, "Old version",
               reviewed_evidence: current_reference
             )
  end

  test "captured pagination bounds ledgers and choice reads without changing the editor defaults",
       c do
    for n <- 1..26 do
      create(c)

      if n > 1 do
        craft =
          Spacecraft.new(%{
            spacecraft_id: Cadence.Ids.new("spacecraft"),
            mission_id: c.mission.mission_id,
            display_name: "Choice #{n}"
          })

        assert {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(c.org.organization_id, craft)
      end
    end

    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert length(original["data"]["model"]["templates"]["entries"]) == 25
    assert original["data"]["model"]["templates"]["more"]
    assert length(original["data"]["model"]["spacecraft"]["entries"]) == 25

    for {event, sequence} <- [{"templates-page", 1}, {"spacecraft-page", 2}] do
      op =
        action(view, c.path, original, event, %{
          "sequence" => sequence,
          "payload" => %{"page" => 2}
        })["snapshot"]

      assert op["receipt"]["result"] == %{"page" => 2}
    end

    refreshed = read(view, c.path, original)["snapshot"]
    assert length(refreshed["data"]["model"]["templates"]["entries"]) == 1
    assert length(refreshed["data"]["model"]["spacecraft"]["entries"]) == 1
    assert refreshed["data"]["model"]["defaults"] == original["data"]["model"]["defaults"]
    assert length(rows(c)) == 26
  end

  test "operators read the ledger but cannot create templates or change their lifecycle", c do
    {template, version} = create(c)
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, c.org, role: :member)
    {:ok, view, _} = live(TestFixtures.member_conn(member), c.path)
    original = page(view)
    refute original["data"]["model"]["can_manage"]
    assert native(%{snapshot: original}) == []

    for {event, payload, sequence} <- [
          {"create-template", %{"template" => values(c)}, 1},
          {"pause-template", %{"reference" => Templates.reference(template, version)}, 2}
        ] do
      op =
        action(view, c.path, original, event, %{"sequence" => sequence, "payload" => payload})[
          "snapshot"
        ]

      assert op["status"] == "rejected"
      assert op["feedback"] == ["forbidden"]
    end

    assert [{%{lifecycle_state: :active}, _}] = rows(c)
  end

  test "domain validation rejects invalid recurrence and malformed or foreign inputs without creating rows",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for {values, sequence} <-
          Enum.with_index(
            [
              Map.put(values(c), "interval_minutes", "0"),
              Map.put(values(c), "rationale", ""),
              Map.put(values(c), "spacecraft_id", "foreign"),
              Map.put(values(c), "anchor_at", "2027-01-01T01:00:37-07:00")
            ],
            1
          ) do
      op =
        action(view, c.path, original, "validate-template", %{
          "sequence" => sequence,
          "payload" => %{"template" => values}
        })["snapshot"]

      assert op["status"] == "completed"
      refute op["receipt"]["result"]["valid"]
      assert rows(c) == []
    end

    assert {:ok, attrs} =
             RequirementTemplateInput.parse(
               Map.merge(values(c), %{"schedule_type" => "daily", "time_utc" => "12:34"})
             )

    assert attrs.schedule_document["time_utc"] == "12:34:00"
    assert {:ok, _, _} = Templates.prepare_create(c.scope, c.mission.mission_id, attrs)
    assert rows(c) == []

    assert {:error, :scope_mismatch} =
             TemplateLedger.load(
               %{c.scope | mission_id: "foreign"},
               c.mission.mission_id,
               TemplateLedger.defaults(),
               %{templates: 1, spacecraft: 1}
             )
  end

  test "page tokens reject injected reads, departure and revoked authentication", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"],
      "page" => 2
    })

    assert_reply(view, %{ok: false})

    render_hook(view, "host:context", %{
      "path" => "/missions/#{c.mission.mission_id}/ops/requirements"
    })

    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    current = page(view)
    refute current["token"] == original["token"]
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => current["id"],
      "token" => current["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  test "native text bounds admit long UTF8 rationale without widening evidence", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    rationale = String.duplicate("界", 200)
    payload = %{"template" => Map.put(values(c), "rationale", rationale)}

    op =
      action(view, c.path, original, "create-template", %{"sequence" => 1, "payload" => payload})[
        "snapshot"
      ]

    assert op["status"] == "completed"
    assert op["input"]["template"]["rationale"] == rationale
  end

  defp values(c),
    do: %{
      "spacecraft_id" => c.craft.spacecraft_id,
      "schedule_type" => "fixed_interval",
      "anchor_at" => "2027-01-01T01:00:37",
      "time_utc" => "01:00:37",
      "interval_minutes" => "360",
      "window_offset_minutes" => "0",
      "window_duration_minutes" => "30",
      "contact_intent" => "payload_downlink",
      "success_measure" => "minimum_duration",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "approval_mode" => "manual",
      "maximum_occurrences_per_run" => "100",
      "maximum_lookback_hours" => "168",
      "rationale" => "Reviewed recurring need"
    }

  defp create(c) do
    {:ok, attrs} = RequirementTemplateInput.parse(values(c))
    {:ok, template, version} = Templates.create(c.scope, c.mission.mission_id, attrs)
    {template, version}
  end

  defp rows(c), do: Templates.list(c.org.organization_id, c.mission.mission_id)

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
    assert [_, json] = Regex.run(~r/TEMPLATE_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
  end
end
