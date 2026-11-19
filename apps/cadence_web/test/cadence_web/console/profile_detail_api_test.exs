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
    base = "/api/console/v1/missions/#{mission.mission_id}/profiles/"

    read = fn id ->
      user |> TestFixtures.member_conn() |> get(base <> id) |> json_response(200)
    end

    number = revision.revision_number
    label = "rev #{number}"
    id = revision.catalog_revision_id

    assert %{"data" => %{"profile" => %{"catalog_revision" => catalog}}} =
             read.(with_catalog.spacecraft_type_id)

    assert catalog == %{"id" => id, "number" => number, "label" => label}

    assert %{"data" => %{"profile" => %{"catalog_revision" => nil}}} =
             read.(without.spacecraft_type_id)
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

    path = "/api/console/v1/missions/#{mission.mission_id}/profiles/#{profile.spacecraft_type_id}"

    assert %{"data" => %{"profile" => %{"catalog_revision" => catalog}}} =
             user |> TestFixtures.member_conn() |> get(path) |> json_response(200)

    assert catalog == %{"id" => elsewhere.catalog_revision_id, "number" => nil, "label" => nil}
  end
end
