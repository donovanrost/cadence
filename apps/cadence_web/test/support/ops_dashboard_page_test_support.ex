defmodule CadenceWeb.OpsDashboardPageTestSupport do
  @moduledoc false
  # Shared dashboard setup for the console's dashboard API and channel tests (the legacy page's
  # host-protocol helpers went with it, L8a).

  import ExUnit.Assertions
  alias Cadence.Dashboards.{CurrentVersions, DocumentCodec, Documents}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  def dashboard_page_setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "dashboard-" <> Ecto.UUID.generate(),
        metadata: %{secret: "private-authoring-metadata"}
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    path = "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}"

    %{
      org: org,
      mission: mission,
      user: user,
      document: document,
      conn: TestFixtures.member_conn(user),
      path: path,
      edit: path <> "/edit"
    }
  end

  def save(c, document, version) do
    assert {:ok, _} =
             CurrentVersions.save(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               document,
               expected_version: version,
               created_by: c.user.user_id
             )
  end
end
