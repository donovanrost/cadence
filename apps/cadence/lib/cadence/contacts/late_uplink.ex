defmodule Cadence.Contacts.LateUplink do
  @moduledoc """
  An operator attested a booking (DECISIONS #53), so its contact was scheduled downlink-only
  ("uplink unconfirmed"). When the provider later confirms the booking **including** its uplink
  leg, the contact gains the uplink path and `:command_window` as a new revision (#55), but only
  before AOS. After AOS the confirmation is recorded and the contact is left as it flew.

  This is D1's evidence (#46) arriving late for the same booking, not a policy change.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.ContactStore.ScheduledContactRow

  alias Cadence.Contacts.{
    ProviderReservation,
    ScheduledContact,
    ScheduledContactRevision,
    ScheduledContactRevisions,
    UplinkLegs
  }

  alias Cadence.Control.Contacts.Store.ScheduledContactRevisionRow
  alias Cadence.Repo

  @doc """
  `{:ok, :revised | :after_aos | :not_applicable}`. `:not_applicable` when the confirmation
  doesn't include uplink service, or the contact already has its command window or isn't
  scheduled. Option `:now`.
  """
  @spec revise(ProviderReservation.t(), keyword()) ::
          {:ok, :revised | :after_aos | :not_applicable} | {:error, term()}
  def revise(%ProviderReservation{} = reservation, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {ids, refs, intents, metadata} <- UplinkLegs.scheduled_fields(reservation),
         true <- :command_window in intents,
         {:ok, %ScheduledContact{lifecycle_state: :scheduled} = contact} <-
           Contacts.fetch_scheduled_contact(
             reservation.organization_id,
             reservation.mission_id,
             reservation.scheduled_contact_id
           ),
         false <- :command_window in contact.contact_intents do
      if DateTime.compare(now, contact.starts_at) == :lt,
        do: apply_revision(contact, reservation, {ids, refs, metadata}, now),
        else: {:ok, :after_aos}
    else
      {:error, reason} -> {:error, reason}
      _not_applicable -> {:ok, :not_applicable}
    end
  end

  defp apply_revision(contact, reservation, {ids, refs, metadata}, now) do
    Repo.transaction(fn ->
      row =
        Repo.get_by!(ScheduledContactRow,
          scheduled_contact_id: contact.scheduled_contact_id,
          mission_id: contact.mission_id
        )

      current = ScheduledContactRow.to_domain(row)

      revised =
        struct!(current,
          contact_intents: Enum.uniq(current.contact_intents ++ [:command_window]),
          path_template_ids: Enum.uniq(current.path_template_ids ++ ids),
          path_template_refs: Enum.uniq(current.path_template_refs ++ refs),
          metadata: Map.merge(current.metadata, metadata),
          current_revision: current.current_revision + 1
        )

      with {:ok, row} <-
             row |> ScheduledContactRow.uplink_revision_changeset(revised) |> Repo.update(),
           {:ok, _revision} <-
             append_revision(ScheduledContactRow.to_domain(row), reservation, now) do
        :revised
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp append_revision(contact, reservation, now) do
    %{
      organization_id: contact.organization_id,
      mission_id: contact.mission_id,
      scheduled_contact_id: contact.scheduled_contact_id,
      revision: contact.current_revision,
      snapshot_document: ScheduledContactRevisions.snapshot(contact),
      reason_document: %{
        "kind" => "uplink_confirmed",
        "provider_reservation_id" => reservation.provider_reservation_id,
        "provider_revision" => reservation.provider_revision
      },
      created_by: "provider:#{reservation.provider_id}",
      created_at: now
    }
    |> ScheduledContactRevision.new()
    |> ScheduledContactRevisionRow.changeset()
    |> Repo.insert()
  end
end
