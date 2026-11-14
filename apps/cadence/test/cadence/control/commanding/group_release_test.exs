defmodule Cadence.Control.Commanding.GroupReleaseTest do
  @moduledoc """
  U46: an operator releases an armed group onto a contact they name. Members of that contact's
  spacecraft go in stack order and the call stops at the first one that doesn't release.
  """
  use Cadence.ConfigCase, async: false

  import Cadence.GroupReleaseFixtures

  alias Cadence.CommandGroupFixtures
  alias Cadence.Commanding.CommandQueueEntryRow
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.Control.Commanding
  alias Cadence.Control.Commanding.GroupRelease

  @org "org-group-release"
  @mission "mission-group-release"
  @at ~U[2026-11-14 07:20:00Z]

  setup do
    persist_mission_scope(@org, @mission)
    alpha = persist_target!("alpha", 0)
    bravo = persist_target!("bravo", 1)
    model = import_noop_model!()
    scope = CommandGroupFixtures.operator!(%{org: @org}, "Release Operator")

    %{alpha: alpha, bravo: bravo, model: model, scope: scope}
  end

  describe "a group released onto a named contact" do
    test "releases its target's members in stack order, and the timeline says so", c do
      group = armed_group!(c, [c.alpha, c.alpha, c.alpha, c.bravo])
      contact = uplink_contact!(c.alpha)

      assert {:error, {:unbooked_contact_unconfirmed, id}} = release(c, group, contact)
      assert id == contact.realized_contact_id
      assert events(group) == []

      assert {:ok, result} = release(c, group, contact, confirm_unbooked: true)
      alpha_entries = Enum.take(group.entries, 3)

      assert %{released_entry_ids: ^alpha_entries, stopped: nil, not_attempted_entry_ids: []} =
               result

      assert entry_state(Enum.at(group.entries, 3)) == "pending"

      user_id = c.scope.user.user_id

      assert [
               %{
                 kind: :released_on_contact,
                 payload: %{
                   "booked" => false,
                   "released_by" => %{"actor_kind" => "user", "user_id" => ^user_id},
                   "released_entry_ids" => ^alpha_entries,
                   "not_attempted_entry_ids" => [],
                   "stopped" => nil
                 }
               }
             ] = events(group)

      assert {:error, {:command_group_nothing_to_release, _id}} =
               release(c, group, contact, confirm_unbooked: true)
    end

    test "stops at the first member that doesn't release; the rest stay queued", c do
      group = armed_group!(c, [c.alpha, c.alpha, c.alpha])
      [first, second, third] = group.entries
      not_yet!(second)
      contact = uplink_contact!(c.alpha)

      assert {:ok,
              %{
                released_entry_ids: [^first],
                stopped: %{command_queue_entry_id: ^second, reason: reason},
                not_attempted_entry_ids: [^third]
              }} = release(c, group, contact, confirm_unbooked: true)

      assert entry_state(second) == "pending"
      assert entry_state(third) == "pending"

      code = GroupRelease.encode_reason(reason)["code"]

      assert [
               %{
                 payload: %{
                   "stopped" => %{"command_queue_entry_id" => ^second, "reason" => stored}
                 }
               }
             ] =
               events(group)

      assert %{"code" => ^code, "details" => %{}} = stored
      assert code != "unknown"
      assert Jason.encode!(stored)
    end

    test "refuses as a group before anything is released", c do
      group = armed_group!(c, [c.alpha])
      contact = uplink_contact!(c.alpha)

      # Not armed.
      {:ok, %CommandGroup{} = pending} = GroupStore.fetch(@org, @mission, group.id)
      {:ok, _} = GroupStore.update_group(%CommandGroup{pending | state: :approval_pending})

      assert {:error, {:command_group_not_armed, :approval_pending}} =
               release(c, group, contact, confirm_unbooked: true)

      {:ok, _} = GroupStore.update_group(%CommandGroup{pending | state: :queued})

      # A contact that serves another spacecraft.
      other = uplink_contact!(c.bravo)

      assert {:error, {:release_contact_not_target_spacecraft, _}} =
               release(c, group, other, confirm_unbooked: true)

      # A booked pass whose window has closed.
      ended = uplink_contact!(c.alpha, {DateTime.add(@at, -1_200), DateTime.add(@at, -600)})

      assert {:error, {:command_window_closed, _, :outside_pass} = closed} =
               release(c, group, ended)

      %{"details" => %{"starts_at" => starts_at, "ends_at" => ends_at}} =
        GroupRelease.encode_reason(closed, @org, @mission)

      assert at(starts_at) == DateTime.add(@at, -1_200)
      assert at(ends_at) == DateTime.add(@at, -600)

      # No one who can't operate the mission.
      assert {:error, :unavailable} =
               Commanding.release_group_to_contact(
                 %Cadence.Auth.Scope{},
                 @mission,
                 group.id,
                 contact.realized_contact_id,
                 confirm_unbooked: true
               )

      assert entry_state(hd(group.entries)) == "pending"
      assert events(group) == []
    end
  end

  test "a refusal reads as a code and named details" do
    assert GroupRelease.encode_reason(
             {:command_window_closed, "rc", :uplink_leg_dropped},
             @org,
             @mission
           ) ==
             %{
               "code" => "command_window_closed",
               "details" => %{
                 "realized_contact_id" => "rc",
                 "why" => "uplink_leg_dropped",
                 "starts_at" => nil,
                 "ends_at" => nil
               }
             }

    assert %{"code" => "command_queue_entry_not_next_for_release", "details" => details} =
             GroupRelease.encode_reason({:command_queue_entry_not_next_for_release, "e1", "e0"})

    assert details == %{"next_command_queue_entry_id" => "e0"}

    assert %{"code" => "earlier_command_failed", "details" => %{}} =
             GroupRelease.encode_reason(:earlier_command_failed)

    assert %{"code" => "command_release_refused", "details" => %{"refusal" => %{"code" => code}}} =
             GroupRelease.encode_reason(
               {:command_release_refused, "a1", {:uplink_gateway_scid_unknown, "gw"}},
               @org,
               @mission
             )

    assert code == "uplink_gateway_scid_unknown"
    assert %{"code" => "unknown"} = GroupRelease.encode_reason("weird")
  end

  defp release(c, group, contact, opts \\ []),
    do:
      Commanding.release_group_to_contact(
        c.scope,
        @mission,
        group.id,
        contact.realized_contact_id,
        Keyword.put(opts, :attempted_at, @at)
      )

  defp at(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.truncate(at, :second)
  end

  defp events(group) do
    @mission
    |> GroupStore.events(group.id)
    |> Enum.filter(&(&1.kind == :released_on_contact))
  end

  defp entry_state(entry_id),
    do: Repo.get_by!(CommandQueueEntryRow, command_queue_entry_id: entry_id).lifecycle_state

  # The entry isn't due yet, so its release is refused (LifecyclePolicy).
  defp not_yet!(entry_id) do
    {1, _} =
      from(q in CommandQueueEntryRow, where: q.command_queue_entry_id == ^entry_id)
      |> Repo.update_all(set: [not_before: DateTime.add(@at, 3_600)])
  end
end
