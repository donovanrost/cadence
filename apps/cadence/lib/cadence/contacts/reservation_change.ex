defmodule Cadence.Contacts.ReservationChange do
  @moduledoc """
  Whether a provider poll changed what readers see of a reservation (qa 11-14: the reconciler
  published `:contacts_changed` for every poll and every failed poll, ~38/s on dev, and every open
  contacts or plan screen refetched about once a second).

  A poll always bumps `attempt_count` and `last_reconciled_at`, and a failed one re-stamps its
  error's `recorded_at`, so the row always differs. Readers see only the fields below (domain's
  rule, 11-14), so `publish_if_changed/4` announces only when one of them differs.
  """

  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Platform.ScopedReadUpdates

  @visible [
    :lifecycle_state,
    :provider_status,
    :provider_revision,
    :pass_phase,
    :delivery_state,
    :provider_contact_ref,
    :response_document,
    :provider_confirmed_snapshot_document,
    :cadence_accepted_snapshot_document,
    :delivery_descriptor_document,
    :last_error_document
  ]

  @doc "What readers see of a fetched reservation (`{:ok, reservation}`), or nil."
  @spec visible(term()) :: map() | nil
  def visible({:ok, %ProviderReservation{} = reservation}) do
    reservation
    |> Map.take(@visible)
    |> Map.update(:last_error_document, %{}, &without_stamp/1)
    # The pass's scheduled contact appearing (the first materialization) is a change too.
    |> Map.put(:scheduled_contact_id, (reservation.metadata || %{})["scheduled_contact_id"])
  end

  def visible(_missing), do: nil

  @doc """
  Publishes `:contacts_changed` after a successful write whose visible reservation differs from
  `before` (`visible/1` of it before the write). Returns `result` either way.
  """
  @spec publish_if_changed(term(), binary(), binary(), map() | nil) :: term()
  def publish_if_changed({:ok, _reservation} = result, organization_id, mission_id, before) do
    if visible(result) != before,
      do: ScopedReadUpdates.publish(:contacts_changed, organization_id, mission_id)

    result
  end

  def publish_if_changed(result, _organization_id, _mission_id, _before), do: result

  defp without_stamp(%{} = error), do: Map.delete(error, "recorded_at")
  defp without_stamp(other), do: other
end
