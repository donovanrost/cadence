defmodule CadenceWeb.Console.SpacecraftWorkspaceAPITest do
  @moduledoc """
  (B) a spacecraft's configuration workspace in the console (director 11-17; ux U94):
  GET …/configuration/workspace, PUT …/draft, POST …/submit, GET …/catalogs/:id/packets.
  Change sets are the only writer of the switches (DECISIONS #109): the document never carries
  them, they read in `switches`, and a draft that sends one is refused, field-keyed.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.SpacecraftStore
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission)

    %{
      user: user,
      mission: mission,
      craft: craft,
      path:
        "/api/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"
    }
  end

  test "the snapshot: no switch keys in the document; the switches read off the craft", c do
    data = workspace(c)

    assert %{
             "spacecraft_id" => _,
             "section" => "overview",
             "saved_version" => nil,
             "active" => nil,
             "review" => nil,
             "external_changes" => false,
             "approval" => %{
               "requirement" => requirement,
               "policy_token" => policy_token,
               "source" => "inherited",
               "can_request" => true,
               "can_review" => true,
               # #595: gates editing (Drafts.save's own check).
               "can_save" => true
             },
             # #595: the craft's own profile; this one has none.
             "profile" => nil,
             "fleet_total" => 1,
             "fleet" => [%{"has_changes" => false}]
           } = data

    assert requirement in ["direct", "independent"] and is_binary(policy_token)

    assert Enum.sort(Map.keys(data["document"])) ==
             ~w(catalog_revision_id handled_apids protocol telemetry_source_endpoint_id)

    off = %{"value" => false, "set" => false, "revision" => nil}
    assert data["switches"] == %{"telemetry_enabled" => off, "commanding_enabled" => off}

    # A change set sets telemetry on; commanding stays unset.
    {:ok, _} =
      SpacecraftStore.put_switches(
        c.mission.organization_id,
        c.mission.mission_id,
        c.craft.spacecraft_id,
        %{telemetry_enabled: true}
      )

    assert %{
             "telemetry_enabled" => %{"value" => true, "set" => true, "revision" => nil},
             "commanding_enabled" => ^off
           } = workspace(c)["switches"]
  end

  test "the snapshot names the craft's own profile (#595, U94's Open profile)", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Bus A")

    craft =
      TestFixtures.persist_spacecraft!(c.mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    path =
      "/api/v1/missions/#{c.mission.mission_id}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get(path)
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["profile"] == %{"id" => profile.spacecraft_type_id, "name" => "Bus A"}
    # A profile that names no catalog revision leaves it to the spacecraft (DECISIONS #65).
    assert data["catalog_set_by"] == "spacecraft"
  end

  test "a profile that names a catalog revision sets it: catalog_set_by is profile (#595b)", c do
    revision =
      CatalogFixtures.persist_imported_revision!(c.mission.organization_id, c.mission.mission_id)

    profile =
      TestFixtures.persist_spacecraft_profile!(c.mission,
        display_name: "Bus B",
        catalog_revision_id: revision.catalog_revision_id
      )

    craft =
      TestFixtures.persist_spacecraft!(c.mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    path =
      "/api/v1/missions/#{c.mission.mission_id}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get(path)
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["catalog_set_by"] == "profile"
    assert data["profile"] == %{"id" => profile.spacecraft_type_id, "name" => "Bus B"}
  end

  test "a draft with a switch key is refused, field-keyed, and nothing is saved", c do
    data = workspace(c)
    document = Map.merge(data["document"], %{"telemetry_enabled" => true})

    assert %{
             "error" => %{
               "code" => "invalid_params",
               "message" =>
                 "Not saved: Telemetry and Commanding are changed with a change set, not in a spacecraft's configuration.",
               "details" =>
                 %{
                   "document.telemetry_enabled" =>
                     "Change this with a change set, from the spacecraft's Operation panel."
                 } = details
             }
           } = put_draft(c, data["token"], document) |> json_response(422)

    assert map_size(details) == 1
    assert workspace(c)["saved_version"] == nil
  end

  test "a draft saves and answers the fresh snapshot; a stale token is refused", c do
    data = workspace(c)

    saved = put_draft(c, data["token"], data["document"]) |> json_response(200)
    assert %{"data" => %{"saved_version" => 1, "token" => token}} = saved
    assert token != data["token"]
    refute Map.has_key?(saved["data"]["document"], "telemetry_enabled")

    assert %{"error" => %{"code" => "spacecraft_configuration_changed"}} =
             put_draft(c, data["token"], data["document"]) |> json_response(409)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"document" => _}}} =
             put_draft(c, token, %{"protocol" => "x"}) |> json_response(422)
  end

  test "the workspace GET uses the same statement count at 5 and 50 spacecraft", c do
    [neighbour | _] = add_spacecraft(c, 2..5)
    neighbour_workspace = %{c | path: workspace_path(c, neighbour)}
    draft = workspace(neighbour_workspace)

    assert %{"data" => %{"saved_version" => 1}} =
             neighbour_workspace
             |> put_draft(draft["token"], draft["document"])
             |> json_response(200)

    {small, small_count} = count_request(c, &get(&1, c.path))
    add_spacecraft(c, 6..50)
    {large, large_count} = count_request(c, &get(&1, c.path))

    assert large_count == small_count, "5 craft: #{small_count}, 50 craft: #{large_count}"
    assert small["fleet_total"] == 5
    assert large["fleet_total"] == 50

    for result <- [small, large] do
      assert Enum.find(result["fleet"], &(&1["id"] == neighbour.spacecraft_id))["has_changes"]
      refute Enum.find(result["fleet"], &(&1["id"] == c.craft.spacecraft_id))["has_changes"]
    end
  end

  test "the draft PUT uses the same statement count at 5 and 50 spacecraft", c do
    add_spacecraft(c, 2..5)
    initial = workspace(c)
    document = initial["document"]

    assert %{"data" => %{"saved_version" => 1, "token" => token}} =
             c |> put_draft(initial["token"], document) |> json_response(200)

    {small, small_count} = count_draft_put(c, token, document)
    add_spacecraft(c, 6..50)
    {large, large_count} = count_draft_put(c, small["token"], document)

    assert large_count == small_count, "5 craft: #{small_count}, 50 craft: #{large_count}"
    assert %{"saved_version" => 2, "fleet_total" => 5, "document" => ^document} = small
    assert %{"saved_version" => 3, "fleet_total" => 50, "document" => ^document} = large
  end

  test "submit: before a save, then without a catalog, is refused; activate applies on a direct mission",
       c do
    data = workspace(c)

    assert %{"error" => %{"code" => "spacecraft_configuration_review_unavailable"}} =
             submit(c, data, "review") |> json_response(409)

    assert %{"data" => data} = put_draft(c, data["token"], data["document"]) |> json_response(200)

    assert %{"error" => %{"code" => "spacecraft_catalog_required"}} =
             submit(c, data, "review") |> json_response(422)

    assert %{"error" => %{"code" => "invalid_params"}} =
             submit(c, data, "approve") |> json_response(422)

    {_craft, revision, _endpoint} =
      CatalogFixtures.setup_imported_mission!(c.mission.organization_id, c.mission.mission_id)

    scope = CatalogFixtures.user_scope(c.mission.organization_id, "lead")
    policy = ActivationPolicy.load(c.mission.organization_id, c.mission.mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, c.mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    data = workspace(c)
    document = Map.put(data["document"], "catalog_revision_id", revision.catalog_revision_id)
    assert %{"data" => data} = put_draft(c, data["token"], document) |> json_response(200)

    assert %{"data" => %{"state" => "active", "execution_id" => execution}} =
             submit(c, data, "activate") |> json_response(200)

    assert is_binary(execution)

    assert %{"active" => %{"version" => 2, "document" => active_doc}} = workspace(c)
    assert active_doc["catalog_revision_id"] == revision.catalog_revision_id
    refute Map.has_key?(active_doc, "telemetry_enabled")
  end

  test "D2 (#543): the composition behind the document's catalog revision, beside it", c do
    data = workspace(c)
    assert %{"composition" => nil, "active" => nil} = data

    revision =
      CatalogFixtures.persist_imported_revision!(c.mission.organization_id, c.mission.mission_id)

    document = Map.put(data["document"], "catalog_revision_id", revision.catalog_revision_id)
    assert %{"data" => saved} = put_draft(c, data["token"], document) |> json_response(200)
    assert saved["document"]["catalog_revision_id"] == revision.catalog_revision_id

    assert %{
             "composition_id" => composition_id,
             "number" => number,
             "imported_layers" => [%{"mount" => "/", "catalog_revision" => %{"id" => catalog_id}}]
           } = saved["composition"]

    assert is_binary(composition_id) and is_integer(number)
    assert catalog_id == revision.catalog_revision_id

    # #595b: each catalog row says the model gate's state (the fixture approves it), and a craft
    # without a profile catalog sets its own.
    assert %{"approval_status" => "approved"} =
             Enum.find(saved["catalogs"], &(&1["id"] == revision.catalog_revision_id))

    assert saved["catalog_set_by"] == "spacecraft"
  end

  test "packets for an unknown catalog; an unknown craft; an unknown section", c do
    assert %{"error" => %{"code" => "catalog_revision_not_found"}} =
             conn(c) |> get(c.path <> "/catalogs/nope/packets") |> json_response(404)

    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             conn(c)
             |> get(String.replace(c.path, c.craft.spacecraft_id, "nobody"))
             |> json_response(404)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"section" => _}}} =
             conn(c) |> get(c.path <> "?section=nope") |> json_response(422)
  end

  test "someone outside the mission's organization: not found on every route, and nothing saved",
       c do
    outsider = TestFixtures.persist_user!()

    TestFixtures.grant_membership!(outsider, TestFixtures.persist_org!(),
      role: :organization_admin
    )

    token = workspace(c)["token"]
    conn = fn -> TestFixtures.member_conn(outsider) end

    # The console's mission scope refuses before the workspace (operate_mission); it answers
    # not found, so another organization can't learn the mission exists.
    for response <- [
          conn.() |> get(c.path),
          conn.() |> put(c.path <> "/draft", %{"token" => token, "document" => %{}}),
          conn.()
          |> post(c.path <> "/submit", %{
            "token" => token,
            "policy_token" => "p",
            "intent" => "review"
          }),
          conn.() |> get(c.path <> "/catalogs/any/packets")
        ] do
      assert %{"error" => %{"code" => "mission_not_found"}} = json_response(response, 404)
    end

    assert workspace(c)["saved_version"] == nil
  end

  defp add_spacecraft(c, range) do
    Enum.map(range, &TestFixtures.persist_spacecraft!(c.mission, display_name: "Fleet #{&1}"))
  end

  defp workspace_path(c, craft),
    do: String.replace(c.path, c.craft.spacecraft_id, craft.spacecraft_id)

  defp count_draft_put(c, token, document) do
    count_request(c, &put(&1, c.path <> "/draft", %{"token" => token, "document" => document}))
  end

  defp count_request(c, request) do
    conn = conn(c)

    TestFixtures.count_statements(fn ->
      conn |> request.() |> json_response(200) |> Map.fetch!("data")
    end)
  end

  defp conn(c), do: TestFixtures.member_conn(c.user)

  defp workspace(c), do: conn(c) |> get(c.path) |> json_response(200) |> Map.fetch!("data")

  defp put_draft(c, token, document),
    do: conn(c) |> put(c.path <> "/draft", %{"token" => token, "document" => document})

  defp submit(c, data, intent) do
    conn(c)
    |> post(c.path <> "/submit", %{
      "token" => data["token"],
      "policy_token" => data["approval"]["policy_token"],
      "intent" => intent
    })
  end
end
