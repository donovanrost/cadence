defmodule Cadence.Contacts.RealizationFailureTest do
  # U45 (lead 11-17, option A): a pass that couldn't be realized is kept on its scheduled contact
  # and shown on contact_start, anchored on the booking, until it's realized or marked as seen.
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Applications.TelemetryDecomFixtures

  alias Cadence.Contacts.{
    ContactStartAttention,
    ContactStore,
    RealizationFailure,
    ScheduledContact
  }

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    org = "org-rf-" <> id
    mission = "mission-rf-" <> id
    persist_mission_scope(org, mission)
    %{org: org, mission: mission, scope: TelemetryDecomFixtures.user_scope(org, "op")}
  end

  defp scheduled!(ctx, ends_in_s) do
    now = DateTime.utc_now()

    {:ok, contact} =
      ContactStore.persist_scheduled(
        ScheduledContact.new(%{
          scheduled_contact_id: "sched-" <> Integer.to_string(System.unique_integer([:positive])),
          organization_id: ctx.org,
          mission_id: ctx.mission,
          starts_at: DateTime.add(now, -600, :second),
          ends_at: DateTime.add(now, ends_in_s, :second),
          source_endpoint_refs: []
        })
      )

    contact
  end

  defp refused, do: {:error, :contact_transport_profile_not_found}

  defp items(ctx), do: ContactStartAttention.items(ctx.org, ctx.mission)

  test "an unknown refusal is recorded and shown as 'unknown', logged on the first try only",
       ctx do
    contact = scheduled!(ctx, 600)

    log =
      capture_log(fn ->
        RealizationFailure.after_error(contact, refused(), DateTime.utc_now())
      end)

    assert log =~ "couldn't be set up"

    refute capture_log(fn ->
             RealizationFailure.after_error(contact, refused(), DateTime.utc_now())
           end) =~ "couldn't be set up"

    assert [
             %{
               id: id,
               reason: "unknown",
               attempts: 2,
               realized_contact_id: nil,
               conflict: "not_started"
             }
           ] = items(ctx)

    assert id == contact.scheduled_contact_id
    assert ContactStartAttention.counts(ctx.org, ctx.mission).open == 1
  end

  test "realization resolves it as started, with realized_contact_id null on the resolved entry",
       ctx do
    since = DateTime.utc_now()
    contact = scheduled!(ctx, 600)
    capture_log(fn -> RealizationFailure.after_error(contact, refused(), DateTime.utc_now()) end)
    {:ok, current} = ContactStore.fetch_scheduled(ctx.mission, contact.scheduled_contact_id)

    assert :ok = RealizationFailure.realized(current, DateTime.utc_now())
    assert items(ctx) == []
    id = contact.scheduled_contact_id

    assert [
             %{
               id: ^id,
               action: "started",
               realized_contact_id: nil,
               resolved_by: %{"kind" => "system"}
             }
           ] =
             ContactStartAttention.resolved_since(ctx.org, ctx.mission, since)
  end

  test "a missed unrealized pass is marked as seen by its scheduled id; not while still on",
       ctx do
    on = scheduled!(ctx, 600)
    missed = scheduled!(ctx, -60)

    for c <- [on, missed],
        do:
          capture_log(fn -> RealizationFailure.after_error(c, refused(), DateTime.utc_now()) end)

    assert {:error, :contact_start_not_missed} =
             ContactStartAttention.acknowledge(ctx.scope, ctx.mission, on.scheduled_contact_id)

    assert {:ok, %{state: "resolved", resolution: %{action: "acknowledged"}}} =
             ContactStartAttention.acknowledge(
               ctx.scope,
               ctx.mission,
               missed.scheduled_contact_id
             )

    assert [%{id: id}] = items(ctx)
    assert id == on.scheduled_contact_id

    assert {:error, :attention_item_not_found} =
             ContactStartAttention.acknowledge(ctx.scope, ctx.mission, "no-such-pass")
  end

  test "an error after the run was persisted resolves the realization failure instead", ctx do
    contact = scheduled!(ctx, 600)
    capture_log(fn -> RealizationFailure.after_error(contact, refused(), DateTime.utc_now()) end)
    {:ok, current} = ContactStore.fetch_scheduled(ctx.mission, contact.scheduled_contact_id)

    # The run exists (its start failed, which the realized contact records): not a second item.
    {:ok, realized} =
      ContactStore.update_scheduled_lifecycle(current, current.lifecycle_state, %{})

    realized = %{realized | realized_contact_id: contact.scheduled_contact_id <> "_run"}
    persist_realized_id!(realized)

    assert :ok = RealizationFailure.after_error(realized, :start_failed, DateTime.utc_now())
    assert items(ctx) == []
  end

  defp persist_realized_id!(%ScheduledContact{} = contact) do
    import Ecto.Query

    {1, _} =
      Cadence.Contacts.ContactStore.ScheduledContactRow
      |> where([row], row.scheduled_contact_id == ^contact.scheduled_contact_id)
      |> Cadence.Repo.update_all(set: [realized_contact_id: contact.realized_contact_id])
  end
end
