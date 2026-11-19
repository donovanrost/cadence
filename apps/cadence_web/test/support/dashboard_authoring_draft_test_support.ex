defmodule CadenceWeb.DashboardAuthoringDraftTestSupport do
  @moduledoc false
  # A persisted dashboard and its author's scope, for the console's dashboard API tests. Authoring
  # is stateless (StatelessAuthoring): the legacy page's server-held draft went with L8a.

  import ExUnit.Assertions
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{DocumentCodec, Documents}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  def authoring_draft_setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)
    [placement] = base.placements

    placement = %{
      placement
      | widget_def: %{
          placement.widget_def
          | binding: Map.put(placement.widget_def.binding, :overlays, [])
        }
    }

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "staging-" <> Ecto.UUID.generate(),
        placements: [placement]
    }

    assert {:ok, document} = Documents.persist(org.organization_id, document)
    %{org: org, user: user, mission: mission, scope: scope, document: document}
  end

  def versions(c),
    do:
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

  def fetch(c) do
    assert {:ok, document} =
             Documents.fetch_for_mode(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               :edit
             )

    document
  end
end
