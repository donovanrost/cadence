defmodule CadenceWeb.Console.SpacecraftUplinkAPITest do
  @moduledoc "Investigate's Uplink tab: GET …/spacecraft/:id/uplink."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{CommandAuthoringFixtures, CommandGroupFixtures, ExactCommandAuthoringFixtures}
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandReleaseAttempt, CommandReleaseAttemptRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Control.UplinkReadiness
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

    UplinkReadiness.create_table()

    %{
      org: org,
      admin: admin,
      mission: mission,
      ids: model.commands_by_name,
      craft: craft,
      endpoint: endpoint,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_data(c, path),
    do:
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> path)
      |> json_response(200)
      |> Map.fetch!("data")

  defp pass!(c, starts_in_s) do
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
        %{"command_id" => c.ids["SET_SIGNED"], "argument_values_json" => ~s({"counter":1})}
      ]
    }

    conn = TestFixtures.member_conn(c.admin)
    pre = conn |> post(c.base <> "/command-groups/preflight", body) |> json_response(200)

    c.admin
    |> TestFixtures.member_conn()
    |> post(c.base <> "/command-groups", Map.put(body, "preflight_digest", pre["data"]["digest"]))
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp live!(c, reservation, state) do
    key = {c.mission.mission_id, "realized-#{reservation.provider_reservation_id}", "path", "gw"}
    on_exit(fn -> :ets.delete(UplinkReadiness.table(), {:session, key}) end)

    UplinkReadiness.record(
      UplinkReadiness.table(),
      key,
      %{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        scheduled_contact_id: reservation.scheduled_contact_id,
        provider_reservation_id: reservation.provider_reservation_id,
        provider_contact_ref: nil,
        provider_id: reservation.provider_id,
        spacecraft_id: c.craft.spacecraft_id,
        ground_station_ref: nil,
        starts_at: reservation.starts_at,
        ends_at: reservation.ends_at
      },
      state,
      nil,
      DateTime.utc_now()
    )
  end

  test "an unknown spacecraft is not found; a spacecraft with nothing booked is empty", c do
    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             c.admin
             |> TestFixtures.member_conn()
             |> get(c.base <> "/spacecraft/nobody/uplink")
             |> json_response(404)

    assert %{
             "spacecraft" => %{"name" => "EARENDIL-001"},
             "now" => nil,
             "next_passes" => [],
             "queue" => [],
             "waits_for" => nil,
             "released" => []
           } = get_data(c, "/spacecraft/#{c.craft.spacecraft_id}/uplink")
  end

  test "before the pass: the next commandable pass, and the lane waiting for it", c do
    next = pass!(c, 3_600)
    group_id = queue_group!(c)

    data = get_data(c, "/spacecraft/#{c.craft.spacecraft_id}/uplink")

    assert %{"in_contact" => false, "pass" => %{"reservation_id" => next_id}, "readiness" => nil} =
             data["now"]

    assert next_id == next.provider_reservation_id

    assert [
             %{
               "position" => 1,
               "command_name" => "SET_SIGNED",
               "arguments_json" => args,
               "group" => %{"id" => ^group_id, "title" => "Mode change"}
             }
           ] = data["queue"]

    assert Jason.decode!(args) == %{"counter" => 1}
    assert %{"pass" => %{"reservation_id" => ^next_id}} = data["waits_for"]
  end

  test "in contact: readiness, and the following passes with their uplink evidence", c do
    live = pass!(c, -60)
    later = pass!(c, 5 * 3_600)
    live!(c, live, :ready)

    data = get_data(c, "/spacecraft/#{c.craft.spacecraft_id}/uplink")

    assert %{
             "in_contact" => true,
             "readiness" => %{"state" => "ready", "command_groups_queued" => nil}
           } = data["now"]

    assert [
             %{
               "reservation_id" => later_id,
               "uplink_evidence" => "booked",
               "uplink_confirmed" => true,
               "attested_by" => nil
             }
           ] = data["next_passes"]

    assert later_id == later.provider_reservation_id
  end

  test "a release in the last 24 h is listed with its status", c do
    pass!(c, 3_600)
    group_id = queue_group!(c)
    [member] = GroupStore.members(c.org.organization_id, c.mission.mission_id, group_id)

    %CommandQueueEntryRow{command_queue_entry_id: entry_id} =
      Repo.get_by!(CommandQueueEntryRow, command_request_id: member.command_request_id)

    CommandReleaseAttempt.new(%{
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      command_queue_entry_id: entry_id,
      command_request_id: member.command_request_id,
      source_endpoint_ref: member.source_endpoint_ref,
      realized_contact_id: "contact-1",
      mission_model_revision_id: member.mission_model_revision_id,
      command_id: member.command_id,
      command_name: member.command_name,
      lifecycle_state: :released,
      released_by: %{},
      attempted_at: DateTime.utc_now(),
      released_at: DateTime.utc_now()
    })
    |> CommandReleaseAttemptRow.changeset()
    |> Repo.insert!()

    assert [
             %{
               "request_id" => id,
               "group" => %{"id" => ^group_id},
               "status" => status,
               "verification_state" => stage
             }
           ] =
             get_data(c, "/spacecraft/#{c.craft.spacecraft_id}/uplink")["released"]

    assert id == member.command_request_id
    assert is_binary(status)

    assert stage in ~w(radiating executed verified no_verifier verify_failed release_failed indeterminate)
  end
end
