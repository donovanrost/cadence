defmodule CadenceWeb.OpsContactDetailLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportStore
  alias Cadence.Contacts.ContactStore.ScheduledContactRow

  alias Cadence.Contacts.{
    ProviderReservation,
    ProviderReservationChanges,
    ProviderReservations,
    ScheduledContact,
    ScheduledContactRevisions
  }

  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.GroundNetworks.ProviderAudit
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  test "reservation rows navigate to the authenticated detail record" do
    {conn, _user, org, mission} = signed_in(:member)
    setup = persist_contact!(org, mission, :baseline)

    {:ok, schedule_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    schedule_vue =
      LiveVue.Test.get_vue(schedule_view, id: "ops-contact-schedule-component")

    reservation_id = setup.reservation.provider_reservation_id

    reservation_row =
      schedule_vue
      |> stream_rows("provider_reservations")
      |> Enum.find(&(&1["id"] == reservation_id))

    assert %{"id" => ^reservation_id} = reservation_row

    assert reservation_row["detail_action"] == %{
             "id" => "open-reservation-#{reservation_id}",
             "label" => "Open provider reservation",
             "icon" => "hero-arrow-right",
             "href" => "/missions/#{mission.mission_id}/ops/contacts/#{reservation_id}"
           }

    assert_json_safe(schedule_vue)

    detail_href = reservation_row["detail_action"]["href"]
    assert {:ok, detail_view, _html} = live(conn, detail_href)

    vue = detail_vue(detail_view)

    assert vue.component == "OpsContactDetail"
    assert vue.class == "contents"
    assert vue.ssr == false

    assert vue.handlers == %{
             "acknowledge-provider-change" => JS.push("acknowledge-provider-change"),
             "approve-provider-change" => JS.push("approve-provider-change"),
             "reject-provider-change" => JS.push("reject-provider-change")
           }

    assert vue.props |> Map.keys() |> Enum.sort() == ["page"]
    assert_member_page_contract(vue.props["page"], mission, setup)

    assert stream_mutations(vue, "provider_changes") == [
             ["replace", "/provider_changes", []]
           ]

    expected_audit = expected_audit_rows(org, mission, setup)

    assert stream_mutations(vue, "provider_audit_entries") ==
             expected_stream_reset("provider_audit_entries", expected_audit)

    assert_json_safe(vue)
  end

  test "organization admin approves the current proposal through a reasoned form" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :approval)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    initial_vue = detail_vue(view)
    page = initial_vue.props["page"]
    [change_row] = stream_rows(initial_vue, "provider_changes")

    assert page["admin_diagnostics"] == expected_admin_diagnostics(setup)
    assert change_row == expected_change_row(change, :admin)

    assert stream_mutations(initial_vue, "provider_changes") ==
             expected_stream_reset("provider_changes", [change_row])

    assert_json_safe(initial_vue)

    render_hook(view, "approve-provider-change", %{
      "approval" => %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "The shifted window remains clear of commanding"
      }
    })

    assert {:ok, scheduled} =
             Cadence.Contacts.fetch_scheduled_contact(
               org.organization_id,
               mission.mission_id,
               setup.reservation.scheduled_contact_id
             )

    assert scheduled.current_revision == 2

    assert [_initial, _accepted] =
             ScheduledContactRevisions.list(
               org.organization_id,
               setup.reservation.scheduled_contact_id
             )

    refreshed_vue = detail_vue(view)
    [refreshed_change] = stream_rows(refreshed_vue, "provider_changes")

    refute Map.has_key?(refreshed_change, "decision_forms")
    assert refreshed_change["lifecycle_state"] == "approved"

    refreshed_changes = stream_rows(refreshed_vue, "provider_changes")

    assert stream_mutations(refreshed_vue, "provider_changes") ==
             expected_stream_reset("provider_changes", refreshed_changes)

    expected_audit = expected_audit_rows(org, mission, setup)

    assert stream_mutations(refreshed_vue, "provider_audit_entries") ==
             expected_stream_reset("provider_audit_entries", expected_audit)

    assert_json_safe(refreshed_vue)
  end

  test "ordinary mission members may inspect but cannot see decision or diagnostic controls" do
    {conn, _user, org, mission} = signed_in(:member)
    setup = persist_contact!(org, mission, :approval)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    vue = detail_vue(view)
    page = vue.props["page"]
    [change_row] = stream_rows(vue, "provider_changes")

    refute Map.has_key?(page, "admin_diagnostics")
    assert change_row == expected_change_row(change, :member)
    refute Map.has_key?(change_row, "decision_forms")

    encoded_contract = Jason.encode!(%{"props" => vue.props, "streams_diff" => vue.streams_diff})
    refute encoded_contract =~ change.proposal_hash
    refute encoded_contract =~ "config://simulator"
    refute encoded_contract =~ "credential_ref"
    assert_json_safe(vue)

    render_hook(view, "approve-provider-change", %{
      "approval" => %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "A member must not be able to authorize this revision"
      }
    })

    assert [unchanged] =
             ProviderReservationChanges.list_for_reservation(
               org.organization_id,
               setup.reservation.provider_reservation_id
             )

    assert unchanged.lifecycle_state == :pending_approval
  end

  test "already-effective provider facts use acknowledgment and contingency language" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :acknowledgment)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    initial_vue = detail_vue(view)
    [change_row] = stream_rows(initial_vue, "provider_changes")
    forms = change_row["decision_forms"]

    assert forms["approval"] == nil
    assert forms["rejection"] == nil
    assert forms["acknowledgment"] ==
             expected_decision_form(change, :acknowledgment)

    render_hook(view, "acknowledge-provider-change", %{
      "acknowledgment" => %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "Flight opened a replacement-pass contingency"
      }
    })

    refreshed_vue = detail_vue(view)
    [refreshed_change] = stream_rows(refreshed_vue, "provider_changes")
    refute Map.has_key?(refreshed_change, "decision_forms")
    assert refreshed_change["lifecycle_state"] == "acknowledged"
    assert_json_safe(refreshed_vue)
  end

  test "configuration conflicts show remediation and never render approval" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :configuration_failure)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    vue = detail_vue(view)
    [change_row] = stream_rows(vue, "provider_changes")

    assert change_row["remediation"] == %{
             "id" => "configuration-remediation-#{change.provider_reservation_change_id}",
             "heading" => "Never approvable from Contact data",
             "copy" =>
               "Reconcile the Mission Provider, Transport, credential, and delivery-profile configuration before retrying. Cadence has not rewritten execution."
           }

    refute Map.has_key?(change_row, "decision_forms")
    assert_json_safe(vue)
  end

  test "organization admin rejects only the server-provided current proposal hash" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :approval)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    [change_row] = view |> detail_vue() |> stream_rows("provider_changes")
    assert change_row["decision_forms"]["rejection"] == expected_decision_form(change, :rejection)

    render_hook(view, "reject-provider-change", %{
      "rejection" => %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "The revised window conflicts with commanding"
      }
    })

    [rejected_change] = view |> detail_vue() |> stream_rows("provider_changes")
    assert rejected_change["lifecycle_state"] == "rejected"
    refute Map.has_key?(rejected_change, "decision_forms")
  end

  defp detail_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-contact-detail-component")
  end

  defp stream_mutations(vue, stream_name) do
    stream_path = "/#{stream_name}"

    Enum.filter(vue.streams_diff, fn
      ["replace", ^stream_path, _items] -> true
      ["upsert", path, _item] -> String.starts_with?(path, stream_path <> "/")
      ["remove", path] -> String.starts_with?(path, stream_path <> "/")
      _operation -> false
    end)
  end

  defp stream_rows(vue, stream_name) do
    vue
    |> stream_mutations(stream_name)
    |> Enum.flat_map(fn
      ["upsert", _path, row] -> [row]
      _operation -> []
    end)
  end

  defp expected_stream_reset(stream_name, rows) do
    [["replace", "/#{stream_name}", []]] ++
      Enum.map(rows, &["upsert", "/#{stream_name}/-", &1])
  end

  defp assert_member_page_contract(page, mission, setup) do
    reservation = setup.reservation

    assert page |> Map.keys() |> Enum.sort() ==
             ~w(audit binding_chain changes header id lifecycle navigation values)

    assert page["id"] == "ops-contact-detail"

    assert page["navigation"] == %{
             "id" => "back-to-contact-schedule",
             "label" => "Contact ledger",
             "href" => "/missions/#{mission.mission_id}/ops/contacts"
           }

    assert page["header"] == %{
             "heading" => "Provider reservation",
             "reservation_id" => reservation.provider_reservation_id,
             "state" => %{
               "label" => to_string(reservation.lifecycle_state),
               "class" => "border-success/40 bg-success/10 text-success"
             },
             "facts" => [
               %{"label" => "Provider rev", "value" => to_string(reservation.provider_revision)},
               %{"label" => "Schedule rev", "value" => "1"},
               %{"label" => "Decision work", "value" => "none"}
             ]
           }

    assert page["values"]["id"] == "contact-values-matrix"
    assert page["values"]["eyebrow"] == "Truth ledger"
    assert page["values"]["heading"] == "Four values, one operational record"
    assert page["values"]["copy"] ==
             "Provider truth does not silently become Cadence execution truth."

    assert Enum.map(page["values"]["rows"], & &1["id"]) ==
             ~w(starts-at ends-at station resource status)

    assert page["changes"] == %{
             "id" => "contact-change-control",
             "eyebrow" => "Provider revision control",
             "heading" => "Changes and decisions",
             "timeline_id" => "contact-change-timeline",
             "empty" => %{
               "id" => "contact-change-timeline-empty",
               "copy" => "No provider revisions beyond the accepted baseline."
             }
           }

    assert page["audit"] == %{
             "eyebrow" => "Evidence timeline",
             "heading" => "Provider audit",
             "timeline_id" => "contact-audit-timeline",
             "empty" => %{
               "id" => "contact-audit-timeline-empty",
               "copy" => "No provider audit entries recorded yet."
             }
           }

    assert page["binding_chain"]["id"] == "contact-binding-chain"
    assert Enum.map(page["binding_chain"]["rows"], & &1["label"]) == [
             "Provider Account",
             "Mission grant",
             "Mission Provider",
             "Delivery policy",
             "Transport",
             "Service Profile",
             "Delivery Profile"
           ]

    assert Enum.map(page["lifecycle"]["rows"], & &1["label"]) == [
             "Provider Contact",
             "Provider pass",
             "Delivery",
             "Cadence schedule",
             "Actual contact",
             "Reservation"
           ]
  end

  defp expected_admin_diagnostics(setup) do
    reservation = setup.reservation

    %{
      "id" => "contact-admin-diagnostics",
      "label" => "Administrator diagnostics",
      "rows" => [
        %{"label" => "Protocol", "value" => "—"},
        %{"label" => "Endpoint", "value" => "—"},
        %{"label" => "Framing", "value" => "not observed"},
        %{"label" => "Credential ref", "value" => "legacy / unavailable"},
        %{"label" => "Provider contact", "value" => reservation.provider_contact_ref},
        %{"label" => "Provider opportunity", "value" => reservation.provider_opportunity_ref},
        %{"label" => "Client reference", "value" => reservation.idempotency_key}
      ],
      "link" => nil
    }
  end

  defp expected_change_row(change, role) do
    row = %{
      "__dom_id" => "provider-change-#{change.provider_reservation_change_id}",
      "provider_reservation_change_id" => change.provider_reservation_change_id,
      "from_provider_revision" => to_string(change.from_provider_revision),
      "provider_revision" => to_string(change.provider_revision),
      "lifecycle_state" => to_string(change.lifecycle_state),
      "classification" => classification_title(change.classification),
      "policy_version" => to_string(change.policy_version),
      "explanation" => change_explanation(change),
      "changed_fields" => change.changed_fields_document |> Map.keys() |> Enum.sort(),
      "deadline" => deadline_contract(change.deadline_at),
      "remediation" => remediation_contract(change)
    }

    case {role, change.lifecycle_state} do
      {:admin, :pending_approval} ->
        Map.put(row, "decision_forms", %{
          "approval" => expected_decision_form(change, :approval),
          "rejection" =>
            if(change.actionable, do: expected_decision_form(change, :rejection), else: nil),
          "acknowledgment" => nil
        })

      {:admin, :acknowledgment_required} ->
        Map.put(row, "decision_forms", %{
          "approval" => nil,
          "rejection" => nil,
          "acknowledgment" => expected_decision_form(change, :acknowledgment)
        })

      _other ->
        row
    end
  end

  defp expected_decision_form(change, kind) do
    form_name = Atom.to_string(kind)

    %{
      "id" => "provider-change-#{form_name}-form-#{change.provider_reservation_change_id}",
      "proposal_hash" => %{
        "id" => "#{form_name}_proposal_hash",
        "name" => "#{form_name}[proposal_hash]",
        "value" => change.proposal_hash
      },
      "reason" => %{
        "id" => "#{form_name}_reason",
        "name" => "#{form_name}[reason]",
        "label" => decision_reason_label(kind),
        "value" => "",
        "required" => true
      },
      "submit" => %{
        "id" => "#{decision_prefix(kind)}-provider-change-#{change.provider_reservation_change_id}",
        "label" => decision_submit_label(kind)
      }
    }
  end

  defp expected_audit_rows(org, mission, setup) do
    ProviderAudit.list_entries(org.organization_id,
      mission_id: mission.mission_id,
      provider_reservation_id: setup.reservation.provider_reservation_id,
      limit: 200
    )
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      %{
        "__dom_id" => "provider-audit-#{entry.provider_audit_entry_id}",
        "provider_audit_entry_id" => entry.provider_audit_entry_id,
        "recorded_at" => format_time(entry.recorded_at),
        "action" => to_string(entry.action),
        "outcome" => to_string(entry.outcome),
        "evidence_references" =>
          Enum.map(entry.evidence_references, fn reference ->
            %{
              "provider_evidence_id" => reference["provider_evidence_id"],
              "content_sha256" => short_hash(reference["content_sha256"])
            }
          end)
      }
    end)
  end

  defp classification_title(:observation), do: "Operational observation"
  defp classification_title(:policy_accept), do: "Accepted by mission policy"
  defp classification_title(:approval_required), do: "Operator approval required"
  defp classification_title(:acknowledgment_required), do: "Provider fact requires acknowledgment"
  defp classification_title(:configuration_failure), do: "Configuration conflict"

  defp change_explanation(change) do
    case change.decision_document["reasons"] do
      reasons when is_list(reasons) and reasons != [] -> Enum.join(reasons, " · ")
      _other -> "Provider revision classified without additional explanation."
    end
  end

  defp deadline_contract(nil), do: nil

  defp deadline_contract(value) do
    %{"label" => "Provider decision deadline", "value" => format_time(value)}
  end

  defp remediation_contract(%{lifecycle_state: :configuration_failure} = change) do
    %{
      "id" => "configuration-remediation-#{change.provider_reservation_change_id}",
      "heading" => "Never approvable from Contact data",
      "copy" =>
        "Reconcile the Mission Provider, Transport, credential, and delivery-profile configuration before retrying. Cadence has not rewritten execution."
    }
  end

  defp remediation_contract(_change), do: nil

  defp decision_reason_label(:approval), do: "Approval reason"
  defp decision_reason_label(:rejection), do: "Rejection reason"
  defp decision_reason_label(:acknowledgment), do: "Contingency note"
  defp decision_prefix(:approval), do: "approve"
  defp decision_prefix(:rejection), do: "reject"
  defp decision_prefix(:acknowledgment), do: "acknowledge"
  defp decision_submit_label(:approval), do: "Approve current revision"
  defp decision_submit_label(:rejection), do: "Reject provider proposal"
  defp decision_submit_label(:acknowledgment), do: "Acknowledge provider fact"

  defp format_time(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp short_hash(nil), do: "unavailable"
  defp short_hash(hash) when byte_size(hash) > 12, do: binary_part(hash, 0, 12) <> "…"
  defp short_hash(hash), do: hash

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: role)
    mission = TestFixtures.persist_mission!(org, display_name: "Contact Ops")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp persist_contact!(org, mission, scenario) do
    suffix = System.unique_integer([:positive])
    starts_at = ~U[2026-07-20 12:00:00.000000Z]
    ends_at = DateTime.add(starts_at, 600)

    provider =
      MissionProvider.new(%{
        provider_id: "detail-provider-#{suffix}",
        mission_id: mission.mission_id,
        display_name: "Detail simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-detail-#{suffix}",
        delivery_policy_document: %{}
      })

    assert {:ok, provider} = MissionProviders.persist_provider(org.organization_id, provider)

    transport =
      Transport.new(%{
        transport_id: "detail-transport-#{suffix}",
        mission_id: mission.mission_id,
        display_name: "Detail TCP transport",
        origin: :direct,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "127.0.0.1",
          "port" => 5_100,
          "framing_mode" => "fixed_size",
          "frame_size" => 1_115,
          "reconnect_policy" => "on_disconnect",
          "tls_enabled" => false,
          "ingress_protocol_family" => "tm"
        }
      })

    assert {:ok, transport} =
             TransportStore.persist_transport(org.organization_id, transport)

    requested = %{
      "provider_contact_ref" => nil,
      "provider_revision" => 1,
      "client_reference" => "detail-client-#{suffix}",
      "opportunity_ref" => "detail-opportunity-#{suffix}",
      "spacecraft_ref" => "SC-DETAIL-#{suffix}",
      "ground_station_ref" => "station-alpha",
      "antenna_or_service_pool_ref" => "pool-alpha",
      "service_profile_ref" => "service-downlink",
      "delivery_profile_ref" => "delivery-cadence",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at),
      "status" => "requesting",
      "pass_phase" => "scheduled",
      "delivery_state" => "pending",
      "delivery_descriptor" => %{},
      "status_reason" => nil,
      "extensions" => %{}
    }

    reservation =
      ProviderReservation.new(%{
        provider_reservation_id: "detail-reservation-#{suffix}",
        mission_id: mission.mission_id,
        provider_id: provider.provider_id,
        provider_version: provider.version,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        service_profile_ref: %{"id" => "service-downlink", "version" => 3},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7},
        provider_profile_id: "detail-profile-#{suffix}",
        provider_profile_version: 1,
        scheduled_contact_id: "detail-scheduled-contact-#{suffix}",
        provider_opportunity_ref: requested["opportunity_ref"],
        idempotency_key: requested["client_reference"],
        spacecraft_id: "detail-spacecraft-#{suffix}",
        provider_spacecraft_ref: requested["spacecraft_ref"],
        source_endpoint_refs: ["detail-source-#{suffix}"],
        path_template_ids: ["detail-path-#{suffix}"],
        starts_at: starts_at,
        ends_at: ends_at,
        requested_snapshot_document: requested,
        request_document: %{"provider_request" => requested}
      })

    assert {:ok, reservation} =
             ProviderReservations.create_attempt(org.organization_id, reservation)

    baseline =
      requested
      |> Map.delete("delivery_descriptor")
      |> Map.put("id", "provider-contact-#{suffix}")
      |> Map.put("provider_contact_ref", "provider-contact-#{suffix}")
      |> Map.put("status", "confirmed")

    assert {:ok, reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               baseline
             )

    scheduled_contact =
      ScheduledContact.new(%{
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: reservation.scheduled_contact_id,
        starts_at: starts_at,
        ends_at: ends_at,
        provider_contact_ref: reservation.provider_contact_ref,
        metadata: %{"provider_reservation_id" => reservation.provider_reservation_id}
      })

    assert {:ok, row} = scheduled_contact |> ScheduledContactRow.changeset() |> Repo.insert()

    assert {:ok, _revision} =
             ScheduledContactRevisions.ensure_initial(
               Repo,
               ScheduledContactRow.to_domain(row)
             )

    apply_scenario!(org, mission, reservation, baseline, scenario)

    assert {:ok, reservation} =
             ProviderReservations.fetch(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id
             )

    %{reservation: reservation, baseline: baseline}
  end

  defp apply_scenario!(_org, _mission, _reservation, _baseline, :baseline), do: :ok

  defp apply_scenario!(org, mission, reservation, baseline, :approval) do
    shifted =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("starts_at", shift(baseline["starts_at"], 60))
      |> Map.put("ends_at", shift(baseline["ends_at"], 60))

    assert {:ok, _reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               shifted
             )
  end

  defp apply_scenario!(org, mission, reservation, baseline, :acknowledgment) do
    effective =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("status", "canceled")
      |> Map.put("extensions", %{
        "provider_change" => %{"effective" => true, "rejectable" => false}
      })

    assert {:ok, _reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               effective
             )
  end

  defp apply_scenario!(org, mission, reservation, baseline, :configuration_failure) do
    mismatch =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("spacecraft_ref", "SC-UNAPPROVED")

    assert {:error, {:provider_configuration_mismatch, _reason}} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               mismatch
             )
  end

  defp shift(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp only_change(setup) do
    assert [change] =
             ProviderReservationChanges.list_for_reservation(
               setup.reservation.organization_id,
               setup.reservation.provider_reservation_id
             )

    change
  end

  defp detail_path(mission, setup),
    do:
      ~p"/missions/#{mission.mission_id}/ops/contacts/#{setup.reservation.provider_reservation_id}"
end
