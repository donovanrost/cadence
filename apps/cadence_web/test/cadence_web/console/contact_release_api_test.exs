defmodule CadenceWeb.Console.ContactReleaseAPITest do
  @moduledoc """
  U46 named release over HTTP (docs/apogee/api/commanding.md §Named release): one result per group
  in the order sent, the whole-request refusals, and the group read's contact half (`uplink.contact`,
  `spacecraft`, `armed_group_ids`, members' `release_refusal`).
  """
  use CadenceWeb.ConnCase, async: false

  import Cadence.GroupReleaseFixtures
  import Ecto.Query

  alias Cadence.Commanding.CommandQueueEntryRow
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @org "org-group-release"
  @mission "mission-group-release"

  setup do
    Cadence.DataCase.persist_mission_scope(@org, @mission)
    alpha = persist_target!("alpha", 0)
    bravo = persist_target!("bravo", 1)
    model = import_noop_model!()
    {:ok, org} = Cadence.Organizations.fetch_organization(@org)
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)

    %{alpha: alpha, bravo: bravo, model: model, conn: TestFixtures.member_conn(user)}
  end

  defp base, do: "/api/console/v1/missions/#{@mission}"

  defp release(c, contact, body),
    do: post(c.conn, base() <> "/contacts/#{contact.realized_contact_id}/release", body)

  defp group(c, id),
    do:
      c.conn |> get(base() <> "/command-groups/#{id}") |> json_response(200) |> Map.fetch!("data")

  test "a hand-started contact: confirm first, then each group in order, with a stop", c do
    first = c |> armed_group!([c.alpha, c.alpha, c.alpha, c.bravo]) |> with_targets!()
    second = c |> armed_group!([c.alpha]) |> with_targets!()
    [one, two, three, _bravo] = first.entries
    contact = uplink_contact!(c.alpha)

    # The group read names the live hand start and what's armed for it.
    assert %{
             "spacecraft" => %{"id" => "spacecraft-alpha", "name" => "alpha"},
             "pass" => nil,
             "readiness" => nil,
             "next_pass" => nil,
             "contact" => %{
               "realized_contact_id" => contact_id,
               "booked" => false,
               "reservation_id" => nil,
               "contact_id" => nil,
               "ends_at" => nil,
               "armed_group_ids" => armed
             }
           } = group(c, first.id)["uplink"]

    assert contact_id == contact.realized_contact_id
    assert Enum.sort(armed) == Enum.sort([first.id, second.id])

    # Not a booked pass: the danger sheet's confirm is required, and nothing went out.
    assert %{"error" => %{"code" => "unbooked_contact_unconfirmed", "details" => details}} =
             c |> release(contact, %{"command_group_ids" => [first.id]}) |> json_response(409)

    assert details == %{"realized_contact_id" => contact.realized_contact_id}

    not_yet!(two)

    body = %{"command_group_ids" => [first.id, second.id], "confirm_unbooked" => true}
    data = c |> release(contact, body) |> json_response(200) |> Map.fetch!("data")

    assert %{"realized_contact_id" => ^contact_id, "booked" => false, "results" => [a, b]} = data

    assert %{
             "command_group_id" => first_id,
             "outcome" => "stopped",
             "released_entry_ids" => [^one],
             "not_attempted_entry_ids" => [^three],
             "stopped" => %{
               "command_queue_entry_id" => ^two,
               "command_request_id" => stopped_request,
               "code" => code,
               "details" => %{}
             },
             "refused" => nil
           } = a

    assert first_id == first.id
    assert is_binary(code) and code != "unknown"

    # The second group's member is behind the stopped one in the same lane.
    assert %{
             "command_group_id" => second_id,
             "outcome" => "stopped",
             "released_entry_ids" => [],
             "stopped" => %{"code" => "command_queue_entry_not_next_for_release"},
             "refused" => nil
           } = b

    assert second_id == second.id

    # The stopped member says why on the group read; the others don't.
    members = for target <- group(c, first.id)["targets"], member <- target["members"], do: member

    assert [refused] = Enum.filter(members, & &1["release_refusal"])
    assert refused["request_id"] == stopped_request

    assert %{
             "code" => ^code,
             "realized_contact_id" => ^contact_id,
             "booked" => false,
             "at" => _at
           } = refused["release_refusal"]

    assert [%{"kind" => "released_on_contact"} | _] =
             Enum.filter(group(c, first.id)["events"], &(&1["kind"] == "released_on_contact"))
  end

  test "a booked pass that has ended refuses the whole request with its window", c do
    group = armed_group!(c, [c.alpha])
    now = DateTime.utc_now()
    starts_at = DateTime.add(now, -1_200, :second)
    ends_at = DateTime.add(now, -600, :second)
    ended = uplink_contact!(c.alpha, {starts_at, ends_at})

    assert %{"error" => %{"code" => "command_window_closed", "details" => details}} =
             c |> release(ended, %{"command_group_ids" => [group.id]}) |> json_response(409)

    assert %{
             "realized_contact_id" => id,
             "why" => "outside_pass",
             "starts_at" => starts,
             "ends_at" => ends
           } = details

    assert id == ended.realized_contact_id
    assert iso(starts) == DateTime.truncate(starts_at, :second)
    assert iso(ends) == DateTime.truncate(ends_at, :second)
  end

  test "group-level refusals come back per group; later groups are still tried", c do
    lone = armed_group!(c, [c.bravo])
    ok = armed_group!(c, [c.alpha])
    contact = uplink_contact!(c.alpha)

    body = %{"command_group_ids" => [lone.id, ok.id], "confirm_unbooked" => true}
    data = c |> release(contact, body) |> json_response(200) |> Map.fetch!("data")

    assert [
             %{
               "outcome" => "refused",
               "refused" => %{
                 "code" => "release_contact_not_target_spacecraft",
                 "details" => %{"realized_contact_id" => _}
               }
             },
             %{"outcome" => "released", "released_entry_ids" => [_entry], "stopped" => nil}
           ] = data["results"]
  end

  test "the group ids must be 1 to 50 distinct ids", c do
    contact = uplink_contact!(c.alpha)

    for ids <- [[], ["g", "g"], [""], "g", nil] do
      assert %{"error" => %{"code" => "invalid_params", "details" => %{"command_group_ids" => _}}} =
               c |> release(contact, %{"command_group_ids" => ids}) |> json_response(422)
    end

    assert %{"error" => %{"details" => %{"confirm_unbooked" => _}}} =
             c
             |> release(contact, %{"command_group_ids" => ["g"], "confirm_unbooked" => "yes"})
             |> json_response(422)
  end

  # domain's fixture groups carry no `targets`; the group read needs them (one per target index).
  defp with_targets!(%{id: id} = group) do
    {:ok, %CommandGroup{} = stored} = GroupStore.fetch(@org, @mission, id)

    targets =
      @org
      |> GroupStore.members(@mission, id)
      |> Enum.uniq_by(& &1.metadata["group"]["target_index"])
      |> Enum.map(fn member ->
        name = String.replace_prefix(member.source_endpoint_ref, "source-endpoint-", "")

        %{
          "index" => member.metadata["group"]["target_index"],
          "spacecraft_id" => "spacecraft-" <> name,
          "source_endpoint_id" => member.source_endpoint_ref,
          "name" => name
        }
      end)

    {:ok, _} = GroupStore.update_group(%CommandGroup{stored | targets: targets})
    group
  end

  defp iso(value) do
    {:ok, at, 0} = DateTime.from_iso8601(value)
    DateTime.truncate(at, :second)
  end

  # The entry isn't due yet, so its release is refused (as domain's GroupReleaseTest does).
  defp not_yet!(entry_id) do
    {1, _} =
      from(q in CommandQueueEntryRow, where: q.command_queue_entry_id == ^entry_id)
      |> Repo.update_all(set: [not_before: DateTime.add(DateTime.utc_now(), 3_600, :second)])
  end
end
