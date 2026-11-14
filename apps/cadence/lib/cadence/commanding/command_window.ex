defmodule Cadence.Commanding.CommandWindow do
  @moduledoc """
  Whether a realized contact may carry a command release now (director, P9CS night 11-14).

  Two ways a pass's command window is closed even though its contact is still `defined` or
  `active`:

  - **Outside the pass.** A command releases only between the scheduled contact's start and
    end. Until 11-14 a contact left `defined` after its pass (its runtime never started) was still
    a release target, so a queued command could have gone to a pass that had ended.
  - **The uplink leg was dropped.** A scheduled contact keeps the uplink path it was booked with
    (DECISIONS #46: contacts keep their snapshot). If an accepted provider change takes the
    booking's uplink leg out of `"included"`, the provider won't carry the uplink, so no command
    releases on that pass.

  A realized contact with no scheduled contact (started by hand) has no booked window. The lane
  dispatch never picks one (director, 11-14: an armed group releases by itself only into a
  scheduled pass); it takes a command only when an operator names it, and this check lets that
  through.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.{ProviderReservation, RealizedContact}
  alias Cadence.Control.Contacts, as: ControlContacts

  @type reason :: {:command_window_closed, binary(), :outside_pass | :uplink_leg_dropped}

  @spec check(binary(), binary(), RealizedContact.t(), DateTime.t()) :: :ok | {:error, reason()}
  def check(org, mission, %RealizedContact{} = contact, %DateTime{} = at) do
    with :ok <- within_pass(org, mission, contact, at) do
      uplink_leg(org, mission, contact)
    end
  end

  defp within_pass(_org, _mission, %RealizedContact{scheduled_contact_id: nil}, _at), do: :ok

  defp within_pass(org, mission, %RealizedContact{} = contact, at) do
    case Contacts.fetch_scheduled_contact(org, mission, contact.scheduled_contact_id) do
      {:ok, scheduled} ->
        if started?(scheduled.starts_at, at) and not ended?(scheduled.ends_at, at),
          do: :ok,
          else: closed(contact, :outside_pass)

      {:error, _not_found} ->
        :ok
    end
  end

  defp started?(nil, _at), do: true
  defp started?(%DateTime{} = starts_at, at), do: DateTime.compare(starts_at, at) != :gt

  defp ended?(nil, _at), do: false
  defp ended?(%DateTime{} = ends_at, at), do: DateTime.compare(ends_at, at) != :gt

  # The booking's current, accepted terms decide (Contacts.UplinkLegs.dropped?/1).
  defp uplink_leg(
         org,
         mission,
         %RealizedContact{metadata: %{"provider_reservation_id" => id}} = c
       )
       when is_binary(id) do
    case ControlContacts.fetch_provider_reservation(org, mission, id) do
      {:ok, %ProviderReservation{} = reservation} ->
        if ControlContacts.uplink_leg_dropped?(reservation),
          do: closed(c, :uplink_leg_dropped),
          else: :ok

      {:error, _not_found} ->
        :ok
    end
  end

  defp uplink_leg(_org, _mission, %RealizedContact{}), do: :ok

  defp closed(%RealizedContact{realized_contact_id: id}, why),
    do: {:error, {:command_window_closed, id, why}}
end
