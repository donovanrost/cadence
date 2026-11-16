defmodule Cadence.Contacts.PassContactsWindowMovesTest do
  @moduledoc """
  `window_moves` lists only moves, each with both windows: a provider-change revision that didn't
  record its window (an approved change) takes it from the snapshots, and one that didn't move the
  window is left out (fe-ops' decode find, 11-16: approval_required with before/after null).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{PassContacts, ScheduledContactRevision, ScheduledContactRevisions}
  alias Cadence.Control.Contacts.Store.ScheduledContactRevisionRow
  alias Cadence.ProviderChangeFixtures

  setup do
    context = ProviderChangeFixtures.setup_contact()
    %{context: context, starts_at: context.baseline["starts_at"]}
  end

  defp revision!(context, number, snapshot_window, reason) do
    {starts_at, ends_at} = snapshot_window

    ScheduledContactRevision.new(%{
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      scheduled_contact_id: context.reservation.scheduled_contact_id,
      revision: number,
      provider_reservation_change_id: nil,
      snapshot_document: %{"starts_at" => starts_at, "ends_at" => ends_at},
      reason_document: Map.put(reason, "kind", "provider_change"),
      created_by: "cadence",
      created_at: DateTime.add(DateTime.utc_now(), number, :second)
    })
    |> ScheduledContactRevisionRow.changeset()
    |> Repo.insert!()
  end

  defp shifted(at, seconds), do: ProviderChangeFixtures.shift(at, seconds)

  test "an approved change that moved the window gets both windows; one that didn't is no move",
       %{context: context, starts_at: starts_at} do
    [initial] =
      ScheduledContactRevisions.list(
        context.organization_id,
        context.reservation.scheduled_contact_id
      )

    original = {initial.snapshot_document["starts_at"], initial.snapshot_document["ends_at"]}
    moved = {shifted(starts_at, 60), shifted(elem(original, 1), 60)}
    observed = {shifted(starts_at, 90), shifted(elem(original, 1), 90)}

    revision!(context, 2, moved, %{"classification" => "approval_required"})
    revision!(context, 3, moved, %{"classification" => "approval_required"})

    revision!(context, 4, observed, %{
      "classification" => "observed",
      "before" => %{"starts_at" => elem(moved, 0), "ends_at" => elem(moved, 1)},
      "after" => %{"starts_at" => elem(observed, 0), "ends_at" => elem(observed, 1)}
    })

    assert [
             %{classification: "observed", before: second_before, after: second_after},
             %{classification: "approval_required", before: first_before, after: first_after}
           ] =
             PassContacts.window_moves(
               context.organization_id,
               context.reservation.scheduled_contact_id
             )

    assert first_before == %{"starts_at" => elem(original, 0), "ends_at" => elem(original, 1)}
    assert first_after == %{"starts_at" => elem(moved, 0), "ends_at" => elem(moved, 1)}
    assert second_before == first_after
    assert second_after == %{"starts_at" => elem(observed, 0), "ends_at" => elem(observed, 1)}
  end
end
