defmodule CadenceWeb.Console.CatalogRevisionSpacecraftAPITest do
  @moduledoc """
  #678: `GET /api/v1/missions/:m/catalog/revisions/:id/spacecraft`, the spacecraft that use a
  catalog revision, paged: `{data: {spacecraft}, meta: {total, next_cursor}}`.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    run =
      mission
      |> TestFixtures.persist_catalog_database!()
      |> TestFixtures.start_catalog_revision_import!(revision_label: "FSW 1")
      |> TestFixtures.complete_catalog_import_run!()

    revision = TestFixtures.fetch_catalog_revision_for_run!(run)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001", scid: 7)

    Repo.insert_all("spacecraft_configuration_revisions", [
      %{
        configuration_revision_id: "cfg-#{System.unique_integer([:positive])}",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        spacecraft_id: craft.spacecraft_id,
        version: 3,
        catalog_revision_id: revision.catalog_revision_id,
        document: %{},
        content_sha256: String.duplicate("a", 64),
        application_basis: "basis",
        created_by: "test",
        inserted_at: DateTime.utc_now()
      }
    ])

    %{
      user: user,
      craft: craft,
      path:
        "/api/v1/missions/#{mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}/spacecraft",
      base: "/api/v1/missions/#{mission.mission_id}/catalog/revisions"
    }
  end

  defp get_json(c, path, status),
    do: c.user |> TestFixtures.member_conn() |> get(path) |> json_response(status)

  test "lists the craft that use the revision, with uses and the saved version", c do
    assert %{
             "data" => %{"spacecraft" => [row]},
             "meta" => %{"total" => 1, "next_cursor" => nil}
           } = get_json(c, c.path, 200)

    assert row == %{
             "id" => c.craft.spacecraft_id,
             "name" => "EARENDIL-001",
             "scid" => 7,
             "uses" => ["saved"],
             "configuration_version" => 3
           }
  end

  test "an unknown revision is 404; a cursor it didn't make is 422", c do
    assert %{"error" => %{"code" => "catalog_revision_not_found"}} =
             get_json(c, c.base <> "/catalog_revision:nope/spacecraft", 404)

    assert %{"error" => %{"code" => "invalid_params"}} =
             get_json(c, c.path <> "?cursor=not-a-cursor", 422)
  end
end
