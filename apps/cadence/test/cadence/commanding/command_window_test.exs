defmodule Cadence.Commanding.CommandWindowTest do
  @moduledoc """
  A command releases only inside its pass, and only while the booking still carries its uplink
  leg (director, P9CS night 11-14).
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Commanding.CommandWindow
  alias Cadence.Contacts.ProviderChangeAttention
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.Contacts
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo

  describe "the pass's window" do
    test "a contact releases between its pass's start and end, not before or after" do
      c = ProviderChangeFixtures.setup_contact()
      contact = realized(c)
      %{starts_at: starts_at, ends_at: ends_at} = c.reservation

      assert :ok = check(c, contact, starts_at)
      assert :ok = check(c, contact, DateTime.add(ends_at, -1))
      assert {:error, {:command_window_closed, id, :outside_pass}} = check(c, contact, ends_at)
      assert id == contact.realized_contact_id

      assert {:error, {:command_window_closed, _id, :outside_pass}} =
               check(c, contact, DateTime.add(starts_at, -1))
    end

    test "a contact with no scheduled contact (started by hand) has no booked window" do
      c = ProviderChangeFixtures.setup_contact()

      contact = %{realized(c) | scheduled_contact_id: nil, metadata: %{}}
      assert :ok = check(c, contact, ~U[2000-01-01 00:00:00Z])
    end
  end

  describe "the uplink leg" do
    test "an accepted change that takes the uplink leg out of 'included' closes the window" do
      c = ProviderChangeFixtures.setup_contact()
      request_uplink!(c)
      contact = realized(c)
      at = DateTime.add(c.reservation.starts_at, 10)

      assert {:ok, _} = ProviderChangeFixtures.advance(c, 2, %{"uplink" => included()})
      assert :ok = check(c, contact, at)
      id = c.reservation.provider_reservation_id
      assert %{} == Contacts.uplink_drops(c.organization_id, c.mission_id, [id])

      # The provider drops the leg: once Cadence has accepted it, no command releases.
      assert {:ok, _} =
               ProviderChangeFixtures.advance(c, 3, %{
                 "uplink" => %{"status" => "rejected", "status_reason" => "antenna lost"}
               })

      accept_pending!(c)

      assert {:error, {:command_window_closed, _id, :uplink_leg_dropped}} =
               check(c, contact, at)

      # For reads (api U46): when Cadence accepted the drop, which change, and why.
      provider_id = c.reservation.provider_id

      assert %{
               ^id => %{
                 at: %DateTime{},
                 change_id: change_id,
                 provider_id: ^provider_id,
                 reason: "antenna lost"
               }
             } =
               Contacts.uplink_drops(c.organization_id, c.mission_id, [id, "another-reservation"])

      assert is_binary(change_id)
    end

    test "a booking that never asked for an uplink leg is not closed by its absence" do
      c = ProviderChangeFixtures.setup_contact()
      contact = realized(c)

      assert :ok = check(c, contact, DateTime.add(c.reservation.starts_at, 10))
    end
  end

  defp check(c, contact, at),
    do: CommandWindow.check(c.organization_id, c.mission_id, contact, at)

  # The run the scheduler realizes from the booking's scheduled contact.
  defp realized(c) do
    reservation = c.reservation

    RealizedContact.new(%{
      realized_contact_id: reservation.scheduled_contact_id <> "_run",
      organization_id: c.organization_id,
      mission_id: c.mission_id,
      scheduled_contact_id: reservation.scheduled_contact_id,
      source_endpoint_refs: reservation.source_endpoint_refs,
      paths: [],
      metadata: %{"provider_reservation_id" => reservation.provider_reservation_id}
    })
  end

  defp included, do: %{"status" => "included"}

  # As UplinkLegs.for_booking asks for one when the route lands at the pass's station.
  defp request_uplink!(c) do
    id = c.reservation.provider_reservation_id

    row =
      Repo.one!(from(row in ProviderReservationRow, where: row.provider_reservation_id == ^id))

    request =
      row.request_document
      |> JsonDocument.unwrap_value()
      |> Map.put("uplink", %{"routing_rule_id" => "route-uplink"})

    row
    |> Ecto.Changeset.change(request_document: JsonDocument.wrap_value(request))
    |> Repo.update!()
  end

  # Approve whatever is waiting for a decision (a policy may also have accepted it already).
  defp accept_pending!(c) do
    for item <- ProviderChangeAttention.items(c.organization_id, c.mission_id) do
      %{proposal_hash: hash} = item.provider_change

      {:ok, _approved} =
        Contacts.approve_provider_change(c.admin_scope, item.id, hash, "Accept the change")
    end

    :ok
  end
end
