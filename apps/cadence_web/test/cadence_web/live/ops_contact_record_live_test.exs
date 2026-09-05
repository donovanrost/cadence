defmodule CadenceWeb.OpsContactRecordLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact}
  alias CadenceWeb.TestFixtures

  test "contact record mounts with the canonical contact subject" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    contact_id = "realized-contact-federated"

    scheduled =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-federated",
        mission_id: mission.mission_id,
        starts_at: ~U[2026-08-01 12:00:00Z],
        ends_at: ~U[2026-08-01 12:15:00Z],
        source_endpoint_refs: ["source-endpoint-federated"],
        contact_intents: [],
        paths: [
          Path.new(%{
            path_id: "path-federated",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-federated"
          })
        ]
      })

    realized =
      RealizedContact.new(%{
        realized_contact_id: contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: scheduled.scheduled_contact_id,
        source_endpoint_refs: scheduled.source_endpoint_refs,
        contact_intents: [],
        paths: scheduled.paths,
        lifecycle_state: :completed,
        realized_at: ~U[2026-08-01 12:01:00Z],
        metadata: %{}
      })

    assert {:ok, _} = Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled)
    assert {:ok, _} = Cadence.Contacts.persist_realized_contact(org.organization_id, realized)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts/records/#{contact_id}")

    assert_surface(
      view,
      "ops-contact-record-component",
      "contact_record",
      mission,
      %{"contact_id" => contact_id}
    )
  end

  test "missing contact records redirect to the authenticated ledger" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    ledger_path = "/missions/#{mission.mission_id}/ops/contacts"

    assert {:error, {:live_redirect, %{to: ^ledger_path}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts/records/missing")
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "contact-record")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
