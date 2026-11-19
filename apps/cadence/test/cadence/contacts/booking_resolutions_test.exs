defmodule Cadence.Contacts.BookingResolutionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanExecutionFixtures, as: Plan
  alias Cadence.ContactPlanning.{ContactPlanExecutions, ContactPlans}

  alias Cadence.Contacts.{
    BookingResolutions,
    LateUplink,
    ProviderReservations,
    ScheduledContactRevisions
  }

  alias Cadence.Contacts.BookingResolutions.Attention
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.Attention, as: AttentionRead

  setup do
    c = Plan.setup_plan()

    assert {:ok, %{items: [first, second]}} =
             ContactPlanExecutions.execute(
               c.member_scope,
               c.mission_id,
               c.plan.contact_plan_id,
               now: DateTime.add(Plan.now(), 2, :second),
               resolve_route: c.resolve_route,
               reserve: Plan.reserver("pending")
             )

    assert first.lifecycle_state == :uncertain and second.lifecycle_state == :uncertain
    Map.merge(c, %{first: first, second: second})
  end

  # Past the confirmation window, and the provider still silent on the re-read.
  defp silent(extra \\ []) do
    [now: DateTime.add(Plan.now(), 1, :hour), reconcile: &{:ok, &1}] ++ extra
  end

  defp resolve(c, item, action, attrs, opts \\ silent()),
    do:
      BookingResolutions.resolve(
        c.admin_scope,
        c.mission_id,
        item.contact_plan_execution_item_id,
        action,
        attrs,
        opts
      )

  defp provider_says(c, reservation_id, status, extra \\ %{}) do
    {:ok, reservation} =
      ProviderReservations.fetch(c.organization_id, c.mission_id, reservation_id)

    response =
      Map.merge(reservation.provider_confirmed_snapshot_document, %{
        "id" => reservation.provider_contact_ref,
        "provider_revision" => reservation.provider_revision + 1,
        "status" => status,
        "provider_status" => status
      })
      |> Map.merge(extra)

    ProviderReservations.apply_provider_status(
      c.organization_id,
      c.mission_id,
      reservation_id,
      response
    )
  end

  defp item(c, item),
    do:
      ContactPlanExecutions.fetch_item(
        c.organization_id,
        c.mission_id,
        item.contact_plan_execution_item_id
      )

  test "Mark booked attests the pass: reserved item, operator_attested contact without a command window; a contradicting provider answer is a conflict",
       c do
    attrs = %{"note" => "Confirmed by phone", "provider_reference" => "NL-4471"}

    assert {:ok, %{outcome: :attested, item: %{lifecycle_state: :reserved}}} =
             resolve(c, c.first, :booked, attrs)

    {:ok, reservation} =
      ProviderReservations.fetch(c.organization_id, c.mission_id, c.first.provider_reservation_id)

    # The lifecycle stays the provider's; the attestation is evidence beside it.
    assert reservation.lifecycle_state == :pending
    assert reservation.metadata["operator_resolution"]["provider_reference"] == "NL-4471"

    {:ok, contact} =
      Cadence.Contacts.fetch_scheduled_contact(
        c.organization_id,
        c.mission_id,
        reservation.scheduled_contact_id
      )

    assert contact.metadata["booking_evidence"] == "operator_attested"
    refute :command_window in contact.contact_intents

    # Resolved already: the error names who did it.
    assert {:error, {:booking_already_resolved, %{"kind" => "user"}}} =
             resolve(c, c.first, :booked, attrs)

    assert {:ok, _} = provider_says(c, c.first.provider_reservation_id, "canceled")
    assert {:ok, %{lifecycle_state: :failed}} = item(c, c.first)

    assert [%{conflict: "contradicts_attestation", state: "open", resolution: resolution}] =
             Attention.items(c.organization_id, c.mission_id)

    assert %{action: "booked", note: "Confirmed by phone", provider_reference: "NL-4471"} =
             resolution

    assert resolution.actor["kind"] == "user"
  end

  test "Mark not booked cancels first and fails the item; a failed cancel and a late confirmation are conflicts, never a silent re-book",
       c do
    assert {:ok, %{outcome: :not_booked, item: failed, resolution: row}} =
             resolve(
               c,
               c.second,
               :not_booked,
               %{"note" => "Provider has no record"},
               silent(cancel: fn _org, _mission, _id -> {:error, :provider_unreachable} end)
             )

    assert failed.lifecycle_state == :failed
    assert failed.last_error_document["code"] == "operator_not_booked"
    assert row.conflict == "cancel_failed" and row.conflict_state == "open"

    # Repair treats it like booking_lost: the plan is no longer fully booked.
    {:ok, plan, _version} =
      ContactPlans.fetch(c.organization_id, c.mission_id, c.plan.contact_plan_id)

    refute plan.lifecycle_state == :reserved

    # The provider confirms after all: the pass is not scheduled, the conflict says why.
    assert {:ok, %{lifecycle_state: :confirmed} = reservation} =
             provider_says(c, c.second.provider_reservation_id, "confirmed")

    assert {:error, :scheduled_contact_not_found} =
             Cadence.Contacts.fetch_scheduled_contact(
               c.organization_id,
               c.mission_id,
               reservation.scheduled_contact_id
             )

    assert [%{conflict: "late_confirmation", state: "open", provider_reservation_id: res_id}] =
             Attention.items(c.organization_id, c.mission_id)

    assert res_id == c.second.provider_reservation_id

    # A user can close it; the item comes back resolved.
    [%{id: id}] = Attention.items(c.organization_id, c.mission_id)

    assert {:ok, %{state: "resolved", id: ^id}} =
             Attention.resolve(c.member_scope, c.mission_id, id, "re-planned")
  end

  test "the fresh provider read wins: an answer settles the item and nothing is attested", c do
    reconcile = fn reservation ->
      provider_says(c, reservation.provider_reservation_id, "confirmed")
    end

    assert {:ok,
            %{outcome: :provider_answered, item: %{lifecycle_state: :reserved}, resolution: row}} =
             resolve(c, c.first, :booked, %{"note" => "n", "provider_reference" => "r"},
               now: DateTime.add(Plan.now(), 1, :hour),
               reconcile: reconcile
             )

    assert row.provider_answer_document["status"] == "confirmed"

    {:ok, reservation} =
      ProviderReservations.fetch(c.organization_id, c.mission_id, c.first.provider_reservation_id)

    refute Map.has_key?(reservation.metadata, "operator_resolution")
  end

  test "only admins resolve, only unconfirmed bookings, and Mark booked needs the provider reference",
       c do
    attrs = %{"note" => "n", "provider_reference" => "r"}

    assert {:error, _forbidden} =
             BookingResolutions.resolve(
               c.member_scope,
               c.mission_id,
               c.first.contact_plan_execution_item_id,
               :booked,
               attrs,
               silent()
             )

    assert {:error, :booking_not_unconfirmed} =
             resolve(c, c.first, :booked, attrs,
               now: DateTime.add(Plan.now(), 3, :second),
               reconcile: &{:ok, &1}
             )

    assert {:error, {:invalid, %{provider_reference: _}}} =
             resolve(c, c.first, :booked, %{"note" => "n"})

    assert {:error, {:invalid, %{note: _}}} = resolve(c, c.first, :not_booked, %{"note" => "  "})
  end

  test "attention: acknowledge keeps an item listed, a provider answer resolves it, counts and the fade-out follow",
       c do
    {:ok, %{resolution: row}} =
      resolve(
        c,
        c.second,
        :not_booked,
        %{"note" => "n"},
        silent(cancel: fn _org, _mission, _id -> {:error, :timeout} end)
      )

    assert %{open: 1, acknowledged: 0} = AttentionRead.counts(c.organization_id, c.mission_id)

    assert {:ok, %{state: "acknowledged", acknowledged_by: %{"kind" => "user"}}} =
             Attention.acknowledge(c.member_scope, c.mission_id, row.booking_resolution_id)

    assert %{open: 0, acknowledged: 1} = AttentionRead.counts(c.organization_id, c.mission_id)

    # The provider confirms the cancel after all: that resolves the cancel_failed conflict.
    assert {:ok, _} = provider_says(c, c.second.provider_reservation_id, "canceled")

    assert {:ok, %{items: [], resolved: [resolved], counts: %{open: 0, acknowledged: 0}}} =
             AttentionRead.load(c.member_scope, c.mission_id)

    assert %{source: "pass_resolution", action: "canceled", resolved_by: %{"kind" => "provider"}} =
             resolved

    assert {:error, :attention_item_not_open} =
             Attention.resolve(c.member_scope, c.mission_id, row.booking_resolution_id, "handled")
  end

  # The booking asked for an uplink leg (the fixture's route has none).
  defp request_uplink(c, reservation_id) do
    row = Repo.get_by!(ProviderReservationRow, provider_reservation_id: reservation_id)
    request = JsonDocument.unwrap_value(row.request_document) || %{}

    leg = %{
      "routing_rule_id" => "route-uplink-#{c.mission_id}",
      "path_template_id" => "template-uplink-#{c.mission_id}",
      "path_template_version" => 1
    }

    row
    |> Ecto.Changeset.change(
      request_document: JsonDocument.wrap_value(Map.put(request, "uplink", leg))
    )
    |> Repo.update!()
  end

  defp contact(c, reservation) do
    {:ok, contact} =
      Cadence.Contacts.fetch_scheduled_contact(
        c.organization_id,
        c.mission_id,
        reservation.scheduled_contact_id
      )

    contact
  end

  test "#55: the provider confirming an attested booking with uplink revises its contact before AOS, only records it after",
       c do
    request_uplink(c, c.first.provider_reservation_id)

    assert {:ok, %{outcome: :attested}} =
             resolve(c, c.first, :booked, %{"note" => "n", "provider_reference" => "NL-1"})

    {:ok, reservation} =
      ProviderReservations.fetch(c.organization_id, c.mission_id, c.first.provider_reservation_id)

    assert contact(c, reservation).metadata["uplink"]["reason"] == "uplink unconfirmed"

    # The confirmation arrives (through the hook, at real time: after this fixture's AOS).
    assert {:ok, confirmed} =
             provider_says(c, reservation.provider_reservation_id, "confirmed", %{
               "uplink" => %{"status" => "included"}
             })

    [row] = Repo.all(BookingResolutions.Row)
    assert row.provider_answer_document["uplink"] == "after_aos"
    refute :command_window in contact(c, confirmed).contact_intents

    # Before AOS the same confirmation adds the uplink path and command window as a revision.
    assert {:ok, :revised} = LateUplink.revise(confirmed, now: Plan.now())
    revised = contact(c, confirmed)
    assert :command_window in revised.contact_intents
    assert "template-uplink-#{c.mission_id}" in revised.path_template_ids
    assert revised.metadata["uplink"]["booked"] == true

    assert %{reason_document: %{"kind" => "uplink_confirmed"}} =
             c.organization_id
             |> ScheduledContactRevisions.list(revised.scheduled_contact_id)
             |> Enum.find(&(&1.revision == revised.current_revision))

    # Already revised: nothing more to do.
    assert {:ok, :not_applicable} = LateUplink.revise(confirmed, now: Plan.now())
  end

  test "#55: a confirmation without uplink service leaves the attested contact downlink-only",
       c do
    assert {:ok, %{outcome: :attested}} =
             resolve(c, c.first, :booked, %{"note" => "n", "provider_reference" => "NL-2"})

    assert {:ok, confirmed} = provider_says(c, c.first.provider_reservation_id, "confirmed")
    assert {:ok, :not_applicable} = LateUplink.revise(confirmed, now: Plan.now())
    refute :command_window in contact(c, confirmed).contact_intents
  end
end
