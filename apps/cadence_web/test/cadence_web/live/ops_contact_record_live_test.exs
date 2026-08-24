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

    ledger_vue = LiveVue.Test.get_vue(ledger_view, id: "ops-contact-schedule-component")

    assert ledger_vue.component == "OpsContactSchedule"
    assert ledger_vue.ssr == false
    assert ledger_vue.class == "contents"
    assert ledger_vue.slots == %{}
    assert ledger_vue.streams_diff == Jason.decode!(Jason.encode!(ledger_vue.streams_diff))

    assert [ledger_row] = stream_upserts(ledger_vue, "contact_records")
    assert ledger_row["__dom_id"] == "contact-record-realized-contact-record-alpha"
    assert ledger_row["kind"] == "realized"

    assert ledger_row["inspect_action"] == %{
             "id" => "open-contact-record-realized-contact-record-alpha",
             "label" => "Inspect",
             "icon" => "hero-arrow-right",
             "href" =>
               "/missions/#{mission.mission_id}/ops/contacts/records/realized-contact-record-alpha"
           }

    {:ok, record_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/contacts/records/#{realized_contact.realized_contact_id}"
      )

    timeline_href =
      ~p"/missions/#{mission.mission_id}/ops/timeline?#{%{category: "operations", scope_kind: "contact", scope_id: realized_contact.realized_contact_id}}"

    expected_explore_href =
      ~p"/missions/#{mission.mission_id}/ops/explore?#{%{"logical_source" => "telemetry", "scope_kind" => "contact", "scope_id" => realized_contact.realized_contact_id, "time_mode" => "archive", "from" => "2026-08-01T12:01:00Z", "to" => "2026-08-01T12:14:00Z"}}"

    record = contact_record_contract(record_view)

    assert record["id"] == "ops-contact-record-page"
    assert record["header"]["canonical_id"] == realized_contact.realized_contact_id

    assert Enum.map(record["paths"]["rows"], & &1["id"]) == [
             "contact-path-contact-path-alpha"
           ]

    assert record == %{
             "id" => "ops-contact-record-page",
             "header" => %{
               "title" => "Mission contact record",
               "canonical_id" => realized_contact.realized_contact_id,
               "lifecycle" => %{
                 "label" => "completed",
                 "class" => "border-success/40 bg-success/10 text-success"
               },
               "back" => %{
                 "id" => "contact-record-back",
                 "label" => "Contact ledger",
                 "icon" => "hero-arrow-left",
                 "href" => "/missions/#{mission.mission_id}/ops/contacts"
               },
               "actions" => [
                 %{
                   "id" => "contact-record-open-timeline",
                   "label" => "Mission Timeline",
                   "icon" => "hero-clock",
                   "class" => "btn btn-sm btn-ghost",
                   "href" => timeline_href
                 },
                 %{
                   "id" => "contact-record-explore-telemetry",
                   "label" => "Explore this window",
                   "icon" => "hero-chart-bar",
                   "class" => "btn btn-sm btn-primary",
                   "href" => expected_explore_href
                 }
               ]
             },
             "window" => %{
               "id" => "contact-operational-window",
               "eyebrow" => "Operational window",
               "title" => "Planned and realized timing",
               "facts" => [
                 %{"label" => "Planned start", "value" => "2026-08-01 12:00:00Z"},
                 %{"label" => "Planned end", "value" => "2026-08-01 12:15:00Z"},
                 %{"label" => "Realized start", "value" => "2026-08-01 12:01:00Z"},
                 %{"label" => "Realized end", "value" => "2026-08-01 12:14:00Z"}
               ]
             },
             "paths" => %{
               "id" => "contact-paths",
               "list_id" => "contact-path-list",
               "eyebrow" => "Data paths",
               "title" => "Contact transport evidence",
               "empty" => false,
               "empty_state" => %{
                 "id" => "contact-paths-empty",
                 "message" => "No path evidence is attached to this contact record."
               },
               "rows" => [
                 %{
                   "id" => "contact-path-contact-path-alpha",
                   "path_id" => "contact-path-alpha",
                   "source_endpoint_ref" => "source-endpoint-alpha",
                   "direction" => %{"label" => "Direction", "value" => "downlink"},
                   "selection" => %{"label" => "Selection", "value" => "selected"}
                 }
               ]
             },
             "lineage" => %{
               "id" => "contact-identities",
               "eyebrow" => "Canonical identity",
               "title" => "Record lineage",
               "fields" => [
                 %{
                   "label" => "Scheduled",
                   "value" => scheduled_contact.scheduled_contact_id,
                   "class" => "break-all font-mono"
                 },
                 %{
                   "label" => "Realized",
                   "value" => realized_contact.realized_contact_id,
                   "class" => "break-all font-mono"
                 },
                 %{
                   "label" => "Provider ref",
                   "value" => "Not linked",
                   "class" => "break-all font-mono"
                 },
                 %{"label" => "Schedule rev", "value" => "1", "class" => "font-mono"},
                 %{"label" => "Clock mode", "value" => "live", "class" => "font-mono"}
               ]
             },
             "context" => %{
               "id" => "contact-operational-context",
               "eyebrow" => "Operational context",
               "title" => "Intent and sources",
               "intents" => %{
                 "label" => "Contact intents",
                 "empty" => false,
                 "empty_state" => "No declared intent",
                 "values" => ["telemetry downlink"]
               },
               "sources" => %{
                 "label" => "Source endpoints",
                 "empty" => false,
                 "empty_state" => "No source endpoint references",
                 "values" => ["source-endpoint-alpha"]
               }
             }
           }

    assert action_href(record, "contact-record-open-timeline") == timeline_href

    assert decode_query(timeline_href) == %{
             "category" => "operations",
             "scope_id" => realized_contact.realized_contact_id,
             "scope_kind" => "contact"
           }

    explore_href = action_href(record, "contact-record-explore-telemetry")
    assert explore_href == expected_explore_href

    assert decode_query(explore_href) == %{
             "from" => "2026-08-01T12:01:00Z",
             "logical_source" => "telemetry",
             "scope_id" => realized_contact.realized_contact_id,
             "scope_kind" => "contact",
             "time_mode" => "archive",
             "to" => "2026-08-01T12:14:00Z"
           }
  end

  test "scheduled-only record exposes its exact planned window and path evidence contract" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-record-only",
        mission_id: mission.mission_id,
        starts_at: ~U[2026-08-02 09:30:00Z],
        ends_at: ~U[2026-08-02 09:45:00Z],
        source_endpoint_refs: ["scheduled-source-endpoint"],
        contact_intents: [:telemetry_downlink],
        paths: [
          Path.new(%{
            path_id: "scheduled-contact-path",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "scheduled-source-endpoint"
          })
        ]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               organization.organization_id,
               scheduled_contact
             )

    {:ok, record_view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/contacts/records/#{scheduled_contact.scheduled_contact_id}"
      )

    timeline_href =
      ~p"/missions/#{mission.mission_id}/ops/timeline?#{%{category: "operations", scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id}}"

    explore_href =
      ~p"/missions/#{mission.mission_id}/ops/explore?#{%{"logical_source" => "telemetry", "scope_kind" => "contact", "scope_id" => scheduled_contact.scheduled_contact_id, "time_mode" => "archive", "from" => "2026-08-02T09:30:00Z", "to" => "2026-08-02T09:45:00Z"}}"

    record = contact_record_contract(record_view)

    assert record == %{
             "id" => "ops-contact-record-page",
             "header" => %{
               "title" => "Mission contact record",
               "canonical_id" => scheduled_contact.scheduled_contact_id,
               "lifecycle" => %{
                 "label" => "scheduled",
                 "class" => "border-info/40 bg-info/10 text-info"
               },
               "back" => %{
                 "id" => "contact-record-back",
                 "label" => "Contact ledger",
                 "icon" => "hero-arrow-left",
                 "href" => "/missions/#{mission.mission_id}/ops/contacts"
               },
               "actions" => [
                 %{
                   "id" => "contact-record-open-timeline",
                   "label" => "Mission Timeline",
                   "icon" => "hero-clock",
                   "class" => "btn btn-sm btn-ghost",
                   "href" => timeline_href
                 },
                 %{
                   "id" => "contact-record-explore-telemetry",
                   "label" => "Explore this window",
                   "icon" => "hero-chart-bar",
                   "class" => "btn btn-sm btn-primary",
                   "href" => explore_href
                 }
               ]
             },
             "window" => %{
               "id" => "contact-operational-window",
               "eyebrow" => "Operational window",
               "title" => "Planned and realized timing",
               "facts" => [
                 %{"label" => "Planned start", "value" => "2026-08-02 09:30:00Z"},
                 %{"label" => "Planned end", "value" => "2026-08-02 09:45:00Z"},
                 %{"label" => "Realized start", "value" => "Not recorded"},
                 %{"label" => "Realized end", "value" => "Not recorded"}
               ]
             },
             "paths" => %{
               "id" => "contact-paths",
               "list_id" => "contact-path-list",
               "eyebrow" => "Data paths",
               "title" => "Contact transport evidence",
               "empty" => false,
               "empty_state" => %{
                 "id" => "contact-paths-empty",
                 "message" => "No path evidence is attached to this contact record."
               },
               "rows" => [
                 %{
                   "id" => "contact-path-scheduled-contact-path",
                   "path_id" => "scheduled-contact-path",
                   "source_endpoint_ref" => "scheduled-source-endpoint",
                   "direction" => %{"label" => "Direction", "value" => "downlink"},
                   "selection" => %{"label" => "Selection", "value" => "selected"}
                 }
               ]
             },
             "lineage" => %{
               "id" => "contact-identities",
               "eyebrow" => "Canonical identity",
               "title" => "Record lineage",
               "fields" => [
                 %{
                   "label" => "Scheduled",
                   "value" => scheduled_contact.scheduled_contact_id,
                   "class" => "break-all font-mono"
                 },
                 %{
                   "label" => "Realized",
                   "value" => "Not realized",
                   "class" => "break-all font-mono"
                 },
                 %{
                   "label" => "Provider ref",
                   "value" => "Not linked",
                   "class" => "break-all font-mono"
                 },
                 %{"label" => "Schedule rev", "value" => "1", "class" => "font-mono"},
                 %{
                   "label" => "Clock mode",
                   "value" => "Not realized",
                   "class" => "font-mono"
                 }
               ]
             },
             "context" => %{
               "id" => "contact-operational-context",
               "eyebrow" => "Operational context",
               "title" => "Intent and sources",
               "intents" => %{
                 "label" => "Contact intents",
                 "empty" => false,
                 "empty_state" => "No declared intent",
                 "values" => ["telemetry downlink"]
               },
               "sources" => %{
                 "label" => "Source endpoints",
                 "empty" => false,
                 "empty_state" => "No source endpoint references",
                 "values" => ["scheduled-source-endpoint"]
               }
             }
           }

    assert action_href(record, "contact-record-open-timeline") == timeline_href

    assert decode_query(timeline_href) == %{
             "category" => "operations",
             "scope_id" => scheduled_contact.scheduled_contact_id,
             "scope_kind" => "contact"
           }

    assert action_href(record, "contact-record-explore-telemetry") == explore_href

    assert decode_query(explore_href) == %{
             "from" => "2026-08-02T09:30:00Z",
             "logical_source" => "telemetry",
             "scope_id" => scheduled_contact.scheduled_contact_id,
             "scope_kind" => "contact",
             "time_mode" => "archive",
             "to" => "2026-08-02T09:45:00Z"
           }
  end

  test "missing canonical contact record redirects to the mission ledger" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    expected_path = "/missions/#{mission.mission_id}/ops/contacts"

    assert {:error,
            {:live_redirect,
             %{
               to: ^expected_path,
               flash: %{"error" => "That contact record is not available in this mission."}
             }}} =
             live(
               TestFixtures.member_conn(user),
               ~p"/missions/#{mission.mission_id}/ops/contacts/records/missing-contact"
             )
  end

  defp contact_record_contract(view) do
    vue = LiveVue.Test.get_vue(view, id: "ops-contact-record-component")

    assert vue.component == "OpsContactRecord"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert Map.keys(vue.props) == ["record"]

    Map.fetch!(vue.props, "record")
  end

  defp action_href(record, action_id) do
    record["header"]["actions"]
    |> Enum.find(&(&1["id"] == action_id))
    |> Map.fetch!("href")
  end

  defp stream_upserts(vue, stream) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", path, _row] -> String.starts_with?(path, "/#{stream}/")
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp decode_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
