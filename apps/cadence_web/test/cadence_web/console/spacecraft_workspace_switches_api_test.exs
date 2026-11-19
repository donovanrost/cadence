defmodule CadenceWeb.Console.SpacecraftWorkspaceSwitchesAPITest do
  @moduledoc """
  (B) and DECISIONS #109 at the console edge (api-ops' review): the PUT fills both switch keys
  with false only so the document decodes; Drafts.save stores the craft's own values, so a craft
  a change set set to true/true (EARENDIL's case) saves and activates true/true. A change set that
  flips a switch after the draft was saved makes submit a 409 with ux's words, not a bare 422.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.Active
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.SpacecraftStore
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    {craft, revision, endpoint} =
      CatalogFixtures.setup_imported_mission!(org.organization_id, mission.mission_id)

    %{
      user: user,
      mission: mission,
      craft: craft,
      catalog: revision.catalog_revision_id,
      endpoint: endpoint.source_endpoint_id,
      path:
        "/api/console/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"
    }
  end

  test "a craft a change set set to true/true saves and activates true/true (the PUT's false never lands)",
       c do
    switches!(c, %{telemetry_enabled: true, commanding_enabled: true})
    direct!(c)

    data = workspace(c)

    document =
      Map.merge(data["document"], %{
        "catalog_revision_id" => c.catalog,
        "telemetry_source_endpoint_id" => c.endpoint,
        "handled_apids" => [42]
      })

    assert %{"data" => saved} = put_draft(c, data["token"], document) |> json_response(200)

    assert %{"telemetry_enabled" => true, "commanding_enabled" => true} =
             Drafts.latest(org(c), mid(c), c.craft.spacecraft_id).document

    assert %{"data" => %{"state" => "active"}} =
             submit(c, saved, "activate") |> json_response(200)

    {:ok, active} = Active.load(c.mission)

    assert %{"telemetry_enabled" => true, "commanding_enabled" => true} =
             active.entries[c.craft.spacecraft_id]["document"]
  end

  # #272 (fe-setup's #269 review): the console path can't go around review. The client picks the
  # intent, but on a mission whose setting requires review an 'activate' is refused one layer
  # down (activation_policy_changed); this pins it at the route, with nothing applied.
  test "on a mission that requires review, submit with intent activate is a 409 and applies nothing",
       c do
    data = workspace(c)

    document =
      Map.merge(data["document"], %{
        "catalog_revision_id" => c.catalog,
        "telemetry_source_endpoint_id" => c.endpoint,
        "handled_apids" => [42]
      })

    assert %{"data" => saved} = put_draft(c, data["token"], document) |> json_response(200)

    assert %{"error" => %{"code" => "activation_policy_changed"}} =
             submit(c, saved, "activate") |> json_response(409)

    {:ok, active} = Active.load(c.mission)
    refute Map.has_key?(active.entries, c.craft.spacecraft_id)
  end

  test "a change set flips a switch after the draft was saved: submit is a 409 in ux's words",
       c do
    data = workspace(c)
    document = Map.put(data["document"], "catalog_revision_id", c.catalog)
    assert %{"data" => saved} = put_draft(c, data["token"], document) |> json_response(200)

    switches!(c, %{commanding_enabled: true})

    assert %{"error" => %{"code" => "spacecraft_switch_set_by_change_set", "message" => message}} =
             submit(c, saved, "review") |> json_response(409)

    assert message ==
             "Not sent: a change set turned Telemetry or Commanding on or off for " <>
               "#{c.craft.display_name} after this draft was saved. Save the draft again, then send it."

    # Saving again takes the craft's switch, and the submit goes through.
    assert %{"data" => resaved} =
             put_draft(c, saved["token"], saved["document"]) |> json_response(200)

    assert %{"data" => %{"state" => "approval_pending"}} =
             submit(c, resaved, "review") |> json_response(200)
  end

  test "refusals name the craft, never its id (ux U94)", c do
    data = workspace(c)

    assert %{
             "error" => %{"code" => "spacecraft_configuration_review_unavailable", "message" => m}
           } =
             submit(c, data, "review") |> json_response(409)

    assert m == "Not sent: save the draft and choose which version to keep first."

    assert %{"data" => saved} =
             put_draft(c, data["token"], data["document"]) |> json_response(200)

    assert %{"error" => %{"code" => "spacecraft_configuration_changed", "message" => changed}} =
             put_draft(c, data["token"], data["document"]) |> json_response(409)

    assert changed =~ "someone saved #{c.craft.display_name}'s configuration"

    assert %{"error" => %{"code" => "spacecraft_catalog_required", "message" => required}} =
             submit(c, saved, "review") |> json_response(422)

    assert required == "Not sent: choose a catalog revision first."
  end

  defp switches!(c, switches) do
    {:ok, _} = SpacecraftStore.put_switches(org(c), mid(c), c.craft.spacecraft_id, switches)
  end

  defp direct!(c) do
    scope = CatalogFixtures.user_scope(org(c), "lead")
    policy = ActivationPolicy.load(org(c), mid(c))

    {:ok, _} =
      ActivationPolicy.save(scope, mid(c), policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })
  end

  defp org(c), do: c.mission.organization_id
  defp mid(c), do: c.mission.mission_id
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
