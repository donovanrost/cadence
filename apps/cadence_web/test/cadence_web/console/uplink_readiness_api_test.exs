defmodule CadenceWeb.Console.UplinkReadinessAPITest do
  @moduledoc "U33 / DECISIONS #58: pass readiness, group uplink, uplink_blocked attention, Recover."
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.{CommandAuthoringFixtures, CommandGroupFixtures, ExactCommandAuthoringFixtures}
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Control.{UplinkQualification, UplinkReadiness}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = ExactCommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    endpoint =
      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id
      })

    reservation =
      CommandGroupFixtures.commandable_pass!(
        org.organization_id,
        mission.mission_id,
        craft.spacecraft_id,
        DateTime.add(DateTime.utc_now(), -60)
      )

    UplinkReadiness.create_table()
    key = {mission.mission_id, "realized-#{reservation.provider_reservation_id}", "path", "gw"}
    on_exit(fn -> :ets.delete(UplinkReadiness.table(), {:session, key}) end)
    pause_qualifier()

    %{
      org: org,
      admin: admin,
      mission: mission,
      ids: model.commands_by_name,
      craft: craft,
      endpoint: endpoint,
      reservation: reservation,
      key: key,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  # #421: the node-wide UplinkQualification forgets, every 15 s, each readiness entry without a live
  # UplinkSessions session (UplinkQualification.run/1, its keys-minus-live sweep; intended: the
  # readiness view holds a pass only while its session runs). These tests write entries by hand,
  # with no session, so a tick between two reads deleted one (:182's pass read read nil). The
  # qualifier is paused for each test and resumed on exit, which ExUnit runs even when the test
  # fails. Nothing here waits on a tick. Recover's requalify would call the paused qualifier, but
  # every Recover case here stops before it (unrecoverable, not blocked, actor, unknown pass).
  defp pause_qualifier do
    case Process.whereis(UplinkQualification) do
      nil ->
        :ok

      qualifier ->
        :sys.suspend(qualifier)
        on_exit(fn -> resume(qualifier) end)
    end
  end

  defp resume(qualifier) do
    :sys.resume(qualifier)
  catch
    # Already resumed, or gone (the supervisor restarted it, so it isn't suspended).
    :exit, _reason -> :ok
  end

  defp live!(c, state, reason) do
    r = c.reservation

    UplinkReadiness.record(
      UplinkReadiness.table(),
      c.key,
      %{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        scheduled_contact_id: r.scheduled_contact_id,
        provider_reservation_id: r.provider_reservation_id,
        provider_contact_ref: nil,
        provider_id: r.provider_id,
        spacecraft_id: c.craft.spacecraft_id,
        ground_station_ref: "SVB-1",
        starts_at: r.starts_at,
        ends_at: r.ends_at
      },
      state,
      reason,
      DateTime.utc_now()
    )
  end

  defp conn(c), do: TestFixtures.member_conn(c.admin)

  defp get_data(c, path),
    do: c |> conn() |> get(c.base <> path) |> json_response(200) |> Map.fetch!("data")

  defp queue_group!(c) do
    body = %{
      "title" => "Mode change",
      "targets" => [
        %{
          "spacecraft_id" => c.craft.spacecraft_id,
          "source_endpoint_id" => c.endpoint.source_endpoint_id
        }
      ],
      "commands" => [
        %{
          "command_id" => c.ids["SET_SIGNED"],
          "argument_values_json" => Jason.encode!(%{"counter" => 1})
        }
      ]
    }

    pre = c |> conn() |> post(c.base <> "/command-groups/preflight", body) |> json_response(200)

    c
    |> conn()
    |> post(c.base <> "/command-groups", Map.put(body, "preflight_digest", pre["data"]["digest"]))
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  test "before its pass, a queued group's uplink names the next commandable pass (U33)", c do
    upcoming =
      CommandGroupFixtures.commandable_pass!(
        c.org.organization_id,
        c.mission.mission_id,
        c.craft.spacecraft_id,
        DateTime.add(DateTime.utc_now(), 3_600)
      )

    # The scheduled contact the booking materialized (only its facts matter to the read).
    %{
      scheduled_contact_id: upcoming.scheduled_contact_id,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      source_endpoint_refs: [c.endpoint.source_endpoint_id],
      contact_intents: [:telemetry_downlink, :command_window],
      starts_at: upcoming.starts_at,
      ends_at: upcoming.ends_at
    }
    |> ScheduledContact.new()
    |> ScheduledContactRow.changeset()
    |> Ecto.Changeset.apply_changes()
    |> Repo.insert!()

    group_id = queue_group!(c)

    assert %{"uplink" => %{"pass" => pass, "readiness" => nil}} =
             get_data(c, "/command-groups/#{group_id}")

    assert pass["contact_id"] == upcoming.scheduled_contact_id
    assert pass["reservation_id"] == upcoming.provider_reservation_id
  end

  defp upcoming_pass!(c, starts_in_s) do
    reservation =
      CommandGroupFixtures.commandable_pass!(
        c.org.organization_id,
        c.mission.mission_id,
        c.craft.spacecraft_id,
        DateTime.add(DateTime.utc_now(), starts_in_s)
      )

    %{
      scheduled_contact_id: reservation.scheduled_contact_id,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      source_endpoint_refs: [c.endpoint.source_endpoint_id],
      contact_intents: [:telemetry_downlink, :command_window],
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at
    }
    |> ScheduledContact.new()
    |> ScheduledContactRow.changeset()
    |> Ecto.Changeset.apply_changes()
    |> Repo.insert!()

    reservation
  end

  test "the single-pass read counts the groups queued for it and names the next pass (ux)", c do
    first = upcoming_pass!(c, 3_600)
    second = upcoming_pass!(c, 3 * 3_600)
    queue_group!(c)

    assert %{"queued_command_groups" => %{"count" => 1, "next_pass" => next}} =
             get_data(c, "/passes/#{first.provider_reservation_id}")

    assert next["reservation_id"] == second.provider_reservation_id

    assert %{"queued_command_groups" => %{"count" => 0}} =
             get_data(c, "/passes/#{second.provider_reservation_id}")
  end

  test "a provider-error readiness reason reads as a key, not a crash (qa #41)", c do
    live!(c, :ready, nil)
    group_id = queue_group!(c)

    error = %Cadence.GroundNetworks.ProviderError{
      category: :conflict,
      detail: "contact has no active included uplink leg"
    }

    live!(c, :blocked, error)

    assert %{
             "uplink" => %{
               "readiness" => %{"state" => "blocked", "reason" => "provider_conflict"}
             }
           } =
             get_data(c, "/command-groups/#{group_id}")

    # #421: a qualifier tick here deleted the hand-written entry before the pass read; paused, the
    # tick waits until the test ends.
    if qualifier = Process.whereis(UplinkQualification), do: send(qualifier, :tick)

    assert %{"uplink_readiness" => %{"reason" => "provider_conflict"}} =
             get_data(c, "/passes/#{c.reservation.provider_reservation_id}")

    queue = get_data(c, "/action-queue")

    assert %{"attention" => %{"uplink" => %{"reason" => "provider_conflict"}}} =
             Enum.find(queue["items"], &(&1["source"] == "uplink_blocked"))
  end

  test "after LOS a stale readiness entry gives no uplink section, not an error (qa #41)", c do
    live!(c, :ready, nil)
    group_id = queue_group!(c)

    # The driver hasn't forgotten the session yet, but its pass ended a minute ago.
    r = c.reservation

    UplinkReadiness.record(
      UplinkReadiness.table(),
      c.key,
      %{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        scheduled_contact_id: r.scheduled_contact_id,
        provider_reservation_id: r.provider_reservation_id,
        provider_contact_ref: nil,
        provider_id: r.provider_id,
        spacecraft_id: c.craft.spacecraft_id,
        ground_station_ref: "SVB1",
        starts_at: DateTime.add(DateTime.utc_now(), -900),
        ends_at: DateTime.add(DateTime.utc_now(), -60)
      },
      :blocked,
      %Cadence.GroundNetworks.ProviderError{category: :conflict, detail: "no active uplink leg"},
      DateTime.utc_now()
    )

    assert %{"uplink" => nil} = get_data(c, "/command-groups/#{group_id}")
    assert %{"uplink_readiness" => nil} = get_data(c, "/passes/#{r.provider_reservation_id}")
  end

  test "a pass with no live uplink session has no readiness", c do
    assert %{"uplink_readiness" => nil} =
             get_data(c, "/passes/#{c.reservation.provider_reservation_id}")
  end

  test "a blocked pass with a queued group: readiness, the group's uplink and a queue row", c do
    live!(c, :ready, nil)
    group_id = queue_group!(c)
    live!(c, :blocked, :attestation_signature_invalid)

    pass = get_data(c, "/passes/#{c.reservation.provider_reservation_id}")

    assert %{
             "state" => "blocked",
             "reason" => "attestation_signature_invalid",
             "since" => since,
             "command_groups_queued" => 1
           } = pass["uplink_readiness"]

    assert is_binary(since)

    assert %{
             "uplink" => %{
               "pass" => %{"reservation_id" => reservation_id, "contact_id" => contact_id},
               "readiness" => %{"state" => "blocked", "reason" => "attestation_signature_invalid"},
               "next_pass" => nil
             }
           } = get_data(c, "/command-groups/#{group_id}")

    assert reservation_id == c.reservation.provider_reservation_id
    assert contact_id == c.reservation.scheduled_contact_id

    queue = get_data(c, "/action-queue")

    assert %{
             "kind" => "attention",
             "source" => "uplink_blocked",
             "priority" => 1,
             "spacecraft" => [%{"name" => "EARENDIL-001"}],
             "attention" => %{
               "conflict" => nil,
               "state" => "open",
               "reservation_id" => ^reservation_id,
               "uplink" => %{
                 "state" => "blocked",
                 "reason" => "attestation_signature_invalid",
                 "command_group_ids" => [^group_id]
               }
             }
           } = Enum.find(queue["items"], &(&1["source"] == "uplink_blocked"))

    assert %{"open" => 1} = get_data(c, "/counts")["attention"]

    # The pass row's attention block stays for pass resolutions; readiness carries the block.
    assert pass["attention"] == nil
  end

  # U46 / DECISIONS #84: Cadence accepted terms without the uplink leg the booking asked for.
  test "a pass whose uplink leg was dropped reads blocked, uplink_leg_dropped (U46)", c do
    live!(c, :ready, nil)
    group_id = queue_group!(c)
    drop_uplink!(c)

    pass = get_data(c, "/passes/#{c.reservation.provider_reservation_id}")

    assert %{
             "state" => "blocked",
             "reason" => "uplink_leg_dropped",
             "since" => _since,
             "command_groups_queued" => queued
           } = pass["uplink_readiness"]

    assert is_integer(queued)
    assert pass["uplink_confirmed"] == false

    # The group was live on it, so its uplink shows the drop (fe-ops).
    assert %{
             "uplink" => %{
               "pass" => %{"reservation_id" => reservation_id},
               "readiness" => %{"state" => "blocked", "reason" => "uplink_leg_dropped"}
             }
           } = get_data(c, "/command-groups/#{group_id}")

    assert reservation_id == c.reservation.provider_reservation_id
  end

  defp drop_uplink!(c) do
    id = c.reservation.provider_reservation_id

    row =
      Repo.one!(from(row in ProviderReservationRow, where: row.provider_reservation_id == ^id))

    update = fn doc, uplink ->
      (JsonDocument.unwrap_value(doc) || %{}) |> Map.put("uplink", uplink)
    end

    row
    |> Ecto.Changeset.change(
      request_document:
        JsonDocument.wrap_value(update.(row.request_document, %{"routing_rule_id" => "r"})),
      cadence_accepted_snapshot_document:
        JsonDocument.wrap_value(
          update.(row.cadence_accepted_snapshot_document, %{"status" => "rejected"})
        )
    )
    |> Repo.update!()
  end

  test "Recover: refused when unrecoverable, not_blocked when ready, unknown pass", c do
    path = "/passes/#{c.reservation.provider_reservation_id}/recover-uplink"

    live!(c, :blocked, :protocol_state_restore_required)

    assert %{
             "error" => %{
               "code" => "uplink_recovery_refused",
               "details" => %{"reason" => "protocol_state_restore_required"}
             }
           } = c |> conn() |> post(c.base <> path) |> json_response(409)

    live!(c, :ready, nil)

    assert %{"error" => %{"code" => "uplink_not_blocked"}} =
             c |> conn() |> post(c.base <> path) |> json_response(409)

    assert %{"error" => %{"code" => "actor_not_assignable"}} =
             c |> conn() |> post(c.base <> path, %{"user_id" => "someone"}) |> json_response(422)

    assert %{"error" => %{"code" => "pass_not_found"}} =
             c |> conn() |> post(c.base <> "/passes/nope/recover-uplink") |> json_response(404)
  end
end
