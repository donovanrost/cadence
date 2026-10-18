defmodule CadenceWeb.OpsRequirementDeclarationPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.OpsConsole.Actions.RequirementDeclarationInput
  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Reads.ApplicationSurfaces.Planning.RequirementDeclaration
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-requirements/declaration-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :member)
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
        display_name: "Declaration spacecraft"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    %{
      org: org,
      user: user,
      scope: scope,
      mission: mission,
      craft: craft,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/requirements/new"
    }
  end

  test "native declaration validates without writes and saves once with the actual governed receipt",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.requirement-declaration"
    assert original["status"] == "ready"
    [["validate", validation], ["save", input]] = calls = native(%{snapshot: original})
    validated = action(view, c.path, original, "validate", validation)["snapshot"]
    assert validated["receipt"]["result"] == %{"valid" => true, "feedback" => []}
    assert requirements(c) == []
    receipt = action(view, c.path, original, "save", input)["snapshot"]
    assert receipt["status"] == "completed"
    [{requirement, _}] = requirements(c)
    result = receipt["receipt"]["result"]
    assert result["requirement_id"] == requirement.contact_requirement_id
    assert result["actor_id"] == c.user.user_id
    assert result["requirement_version"] == 1
    assert calls == native(%{snapshot: original, operations: [validated, receipt]})
    assert action(view, c.path, original, "save", input)["snapshot"]["status"] == "rejected"

    assert action(view, c.path, original, "save", Map.put(input, "sequence", 3))["snapshot"][
             "status"
           ] == "rejected"

    assert length(requirements(c)) == 1
    recovered = read(view, c.path, original)["snapshot"]
    assert recovered["data"]["operation"] == receipt
    assert recovered["data"]["model"]["horizon"] == original["data"]["model"]["horizon"]
    assert page(view) == original

    {:ok, _, version} =
      ContactRequirements.fetch(
        c.org.organization_id,
        c.mission.mission_id,
        requirement.contact_requirement_id
      )

    assert version.content_sha256 == result["content_sha256"]

    {:ok, expected_start, 0} =
      DateTime.from_iso8601(input["payload"]["contact_requirement"]["earliest_start"] <> "Z")

    assert DateTime.compare(version.earliest_start, expected_start) == :eq
  end

  test "domain validation rejects impossible horizons and outcomes before persistence and permits repair",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    input = values(c)

    invalids = [
      {Map.put(input, "latest_end", "2027-01-01T00:00:00"), "horizon_order"},
      {Map.put(input, "minimum_data_volume_bytes", ""), "volume_required"},
      {Map.put(input, "preferred_duration_seconds", "1"), "duration_order"},
      {Map.put(input, "spacecraft_id", "foreign-spacecraft"), "spacecraft_unavailable"},
      {Map.put(input, "earliest_start", "2027-01-01T01:00:37-07:00"), "invalid_datetime"},
      {Map.put(input, "minimum_duration_seconds", "2.5"), "invalid_number"},
      {Map.merge(input, %{"allowed_providers" => "one", "excluded_providers" => "one"}),
       "conflicting_constraints"}
    ]

    Enum.with_index(invalids, 1)
    |> Enum.each(fn {{form, code}, sequence} ->
      result = action(view, c.path, original, "validate", command(sequence, form))["snapshot"]
      assert result["status"] == "completed"
      assert result["receipt"]["result"] == %{"valid" => false, "feedback" => [code]}
      assert requirements(c) == []
    end)

    bad =
      action(view, c.path, original, "save", command(8, Map.put(input, "rationale", "")))[
        "snapshot"
      ]

    assert bad["status"] == "rejected"
    assert requirements(c) == []
    saved = action(view, c.path, original, "save", command(9, input))["snapshot"]
    assert saved["status"] == "completed"
    assert length(requirements(c)) == 1
  end

  test "bounded choice paging is read only, keeps its horizon and permits a prior-page selection",
       c do
    for n <- 1..25 do
      craft =
        Spacecraft.new(%{
          spacecraft_id: Cadence.Ids.new("spacecraft"),
          mission_id: c.mission.mission_id,
          display_name: "Choice #{n}"
        })

      assert {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(c.org.organization_id, craft)
    end

    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert length(original["data"]["model"]["spacecraft"]["entries"]) == 25

    choices =
      action(view, c.path, original, "spacecraft-page", %{
        "sequence" => 1,
        "payload" => %{"page" => 2}
      })["snapshot"]

    assert choices["receipt"]["result"]["spacecraft"]["page"] == 2
    assert length(choices["receipt"]["result"]["spacecraft"]["entries"]) == 1
    refreshed = read(view, c.path, original)["snapshot"]
    assert refreshed["data"]["model"]["spacecraft"]["page"] == 2
    assert refreshed["data"]["model"]["horizon"] == original["data"]["model"]["horizon"]
    assert requirements(c) == []
    selected = hd(original["data"]["model"]["spacecraft"]["entries"])["id"]

    saved =
      action(
        view,
        c.path,
        original,
        "save",
        command(2, Map.put(values(c), "spacecraft_id", selected))
      )["snapshot"]

    assert saved["status"] == "completed"
  end

  test "captured reads reject injected selectors, departed tokens and revoked sessions", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"],
      "input" => %{"page" => 2}
    })

    assert_reply(view, %{ok: false})
    assert action(view, c.path, original, "unknown", command(1, values(c)))["ok"] == false
    render_hook(view, "host:context", %{"path" => String.replace_suffix(c.path, "/new", "")})
    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    current = page(view)
    refute current["token"] == original["token"]
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "path" => c.path,
      "id" => current["id"],
      "token" => current["token"],
      "event" => "save",
      "input" => command(1, values(c))
    })

    assert_redirect(view, "/sign-in")
    assert requirements(c) == []
  end

  test "empty missions and mismatched scopes cannot declare, and normalization preserves UTC seconds",
       c do
    empty = TestFixtures.persist_mission!(c.org)

    {:ok, model} =
      RequirementDeclaration.load(
        c.scope,
        empty.mission_id,
        RequirementDeclaration.initial_horizon(),
        1
      )

    refute model.can_declare
    assert model.spacecraft.entries == []

    assert {:error, :scope_mismatch} =
             RequirementDeclaration.choices(
               %{c.scope | mission_id: "foreign"},
               c.mission.mission_id,
               1
             )

    assert {:error, :invalid_page} =
             RequirementDeclaration.choices(c.scope, c.mission.mission_id, 0)

    assert {:ok, attrs} = RequirementDeclarationInput.parse(values(c))
    assert attrs.earliest_start == ~U[2027-01-01 01:00:37Z]
    assert {:ok, _, _} = ContactRequirements.prepare_create(c.scope, c.mission.mission_id, attrs)
    assert requirements(c) == []

    assert {:error, :malformed_input} =
             RequirementDeclarationInput.admit(%{
               "contact_requirement" => Map.put(values(c), "provider_effect", true)
             })
  end

  test "native required fields reject empty and whitespace rationale before validation or creation",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for {rationale, sequence} <- [{"", 1}, {"   ", 2}] do
      input = command(sequence, Map.put(values(c), "rationale", rationale))
      op = action(view, c.path, original, "validate", input)["snapshot"]
      assert op["receipt"]["result"] == %{"valid" => false, "feedback" => ["required_fields"]}
      assert requirements(c) == []
    end

    op =
      action(view, c.path, original, "save", command(3, Map.put(values(c), "rationale", "   ")))[
        "snapshot"
      ]

    assert op["status"] == "rejected"
    assert op["feedback"] == ["required_fields"]
    assert requirements(c) == []
  end

  test "native text bounds admit long UTF8 rationale without widening evidence", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    rationale = String.duplicate("界", 200)
    payload = %{"contact_requirement" => Map.put(values(c), "rationale", rationale)}

    op =
      action(view, c.path, original, "save", %{"sequence" => 1, "payload" => payload})["snapshot"]

    assert op["status"] == "completed"
    assert op["input"]["contact_requirement"]["rationale"] == rationale
  end

  defp values(c) do
    %{
      "spacecraft_id" => c.craft.spacecraft_id,
      "contact_intent" => "payload_downlink",
      "earliest_start" => "2027-01-01T01:00:37",
      "latest_end" => "2027-01-02T01:00:37",
      "success_measure" => "minimum_data_volume",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "1000000000",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "allowed_providers" => "",
      "excluded_providers" => "",
      "allowed_stations" => "",
      "excluded_stations" => "",
      "rationale" => "Reviewed declaration"
    }
  end

  defp command(sequence, values),
    do: %{"sequence" => sequence, "payload" => %{"contact_requirement" => values}}

  defp requirements(c), do: ContactRequirements.list(c.org.organization_id, c.mission.mission_id)

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
    assert [_, json] = Regex.run(~r/DECLARATION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
  end
end
