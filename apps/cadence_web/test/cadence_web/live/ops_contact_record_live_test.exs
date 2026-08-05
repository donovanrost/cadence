defmodule CadenceWeb.OpsContactRecordLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact}
  alias CadenceWeb.TestFixtures

  test "contact ledger opens canonical realized record and hands its window to Explore" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-record-alpha",
        mission_id: mission.mission_id,
        starts_at: ~U[2026-08-01 12:00:00Z],
        ends_at: ~U[2026-08-01 12:15:00Z],
        source_endpoint_refs: ["source-endpoint-alpha"],
        contact_intents: [:telemetry_downlink],
        paths: [
          Path.new(%{
            path_id: "contact-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha"
          })
        ]
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-contact-record-alpha",
        mission_id: mission.mission_id,
        scheduled_contact_id: scheduled_contact.scheduled_contact_id,
        source_endpoint_refs: scheduled_contact.source_endpoint_refs,
        contact_intents: scheduled_contact.contact_intents,
        paths: scheduled_contact.paths,
        lifecycle_state: :completed,
        realized_at: ~U[2026-08-01 12:01:00Z],
        metadata: %{"completed_at" => "2026-08-01T12:14:00Z"}
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               organization.organization_id,
               scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               organization.organization_id,
               realized_contact
             )

    conn = TestFixtures.member_conn(user)
    {:ok, ledger_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    assert has_element?(
             ledger_view,
             ~s(#contact-record-realized-contact-record-alpha[data-contact-record-kind="realized"])
           )

    assert has_element?(
             ledger_view,
             ~s(#open-contact-record-realized-contact-record-alpha[href="/missions/#{mission.mission_id}/ops/contacts/records/realized-contact-record-alpha"])
           )

    {:ok, record_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/contacts/records/#{realized_contact.realized_contact_id}"
      )

    assert has_element?(record_view, "#ops-contact-record-page")
    assert has_element?(record_view, "#contact-record-id", realized_contact.realized_contact_id)
    assert has_element?(record_view, "#contact-path-contact-path-alpha")

    [explore_href] =
      record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#contact-record-explore-telemetry")
      |> LazyHTML.attribute("href")

    explore_query = explore_href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert explore_query == %{
             "from" => "2026-08-01T12:01:00Z",
             "logical_source" => "telemetry",
             "scope_id" => realized_contact.realized_contact_id,
             "scope_kind" => "contact",
             "time_mode" => "archive",
             "to" => "2026-08-01T12:14:00Z"
           }
  end

  test "missing canonical contact record redirects to the mission ledger" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    expected_path = "/missions/#{mission.mission_id}/ops/contacts"

    assert {:error, {:live_redirect, %{to: ^expected_path, flash: %{"error" => _message}}}} =
             live(
               TestFixtures.member_conn(user),
               ~p"/missions/#{mission.mission_id}/ops/contacts/records/missing-contact"
             )
  end
end
