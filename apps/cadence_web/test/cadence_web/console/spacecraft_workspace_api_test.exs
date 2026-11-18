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
        "/api/console/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/configuration/workspace"
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
               "can_review" => true
             },
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
