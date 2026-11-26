defmodule CadenceWeb.Console.ProfileDetailAPITest do
  @moduledoc """
  #246 (qa, 11-18 conversion slot): the profile detail read sends its catalog revision as
  `{id, number, label}`, as the profile list does and the console's reader requires ("catalog rev
  N", U65). `{id}` alone made the profile page unreadable for a profile with a catalog revision.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias CadenceWeb.TestFixtures

  test "a profile with a catalog revision reads it with its number and label; without one, null" do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    revision =
      CatalogFixtures.persist_imported_revision!(org.organization_id, mission.mission_id)

    with_catalog =
      TestFixtures.persist_spacecraft_profile!(mission,
        catalog_revision_id: revision.catalog_revision_id
      )

    without = TestFixtures.persist_spacecraft_profile!(mission)
    base = "/api/v1/missions/#{mission.mission_id}/profiles/"

    read = fn id ->
      user |> TestFixtures.member_conn() |> get(base <> id) |> json_response(200)
    end

    number = revision.revision_number
    label = "rev #{number}"
    id = revision.catalog_revision_id

    assert %{
             "data" => %{
               "profile" => %{"catalog_revision" => catalog, "composition" => composition}
             }
           } = read.(with_catalog.spacecraft_type_id)

    assert catalog == %{"id" => id, "number" => number, "label" => label}
    # D2 (#543): beside it, the composition behind that catalog revision (the import's own).
    assert_import_composition(composition, revision)

    assert %{"data" => %{"profile" => %{"catalog_revision" => nil, "composition" => nil}}} =
             read.(without.spacecraft_type_id)
  end

  test "D2 (#543): the profile list sends the composition beside the catalog revision" do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    revision =
      CatalogFixtures.persist_imported_revision!(org.organization_id, mission.mission_id)

    with_catalog =
      TestFixtures.persist_spacecraft_profile!(mission,
        catalog_revision_id: revision.catalog_revision_id
      )

    without = TestFixtures.persist_spacecraft_profile!(mission)

    rows =
      user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{mission.mission_id}/profiles")
      |> json_response(200)
      |> get_in(["data", "profiles"])
      |> Map.new(&{&1["id"], &1})

    row = rows[with_catalog.spacecraft_type_id]
    number = revision.revision_number

    assert row["catalog_revision"] == %{
             "id" => revision.catalog_revision_id,
             "number" => number,
             "label" => "rev #{number}"
           }

    assert_import_composition(row["composition"], revision)

    assert %{"catalog_revision" => nil, "composition" => nil} =
             rows[without.spacecraft_type_id]
  end

  # The profile's catalog_revision_id has no foreign key: an id naming none of this mission's
  # catalog revisions (another mission's, or one left over after a reset) keeps its id and reads
  # number and label null, as the profile list does; the console reads it as unnumbered.
  test "an id naming none of the mission's catalog revisions reads number and label null" do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    other = TestFixtures.persist_mission!(org)

    elsewhere =
      CatalogFixtures.persist_imported_revision!(org.organization_id, other.mission_id)

    profile =
      TestFixtures.persist_spacecraft_profile!(mission,
        catalog_revision_id: elsewhere.catalog_revision_id
      )

    path = "/api/v1/missions/#{mission.mission_id}/profiles/#{profile.spacecraft_type_id}"

    # Nor a composition (D2, #543): another mission's catalog revision is never looked up.
    assert %{"data" => %{"profile" => %{"catalog_revision" => catalog, "composition" => nil}}} =
             user |> TestFixtures.member_conn() |> get(path) |> json_response(200)

    assert catalog == %{"id" => elsewhere.catalog_revision_id, "number" => nil, "label" => nil}
  end

  # An import's own composition (D1/D2): one layer at '/', named by the catalog revision.
  defp assert_import_composition(composition, revision) do
    assert %{
             "composition_id" => composition_id,
             "number" => number,
             "imported_layers" => [%{"mount" => "/", "catalog_revision" => %{"id" => catalog_id}}]
           } = composition

    assert is_binary(composition_id) and is_integer(number)
    assert catalog_id == revision.catalog_revision_id
  end
end
