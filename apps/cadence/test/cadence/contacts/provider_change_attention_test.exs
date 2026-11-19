defmodule Cadence.Contacts.ProviderChangeAttentionTest do
  @moduledoc "§11 L14: provider changes waiting for a decision, as attention items."
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.ProviderChangeAttention
  alias Cadence.Control.Contacts
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.Attention

  test "a change awaiting approval is an item with what changed; deciding it resolves it" do
    c = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(c, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(c.baseline["ends_at"], 60)
             })

    assert [item] = ProviderChangeAttention.items(c.organization_id, c.mission_id)

    assert %{
             source: "provider_change",
             conflict: "approval_required",
             state: "open",
             provider_reservation_id: reservation_id,
             provider_change: %{proposal_hash: hash, provider_revision: 2, fields: fields}
           } = item

    assert reservation_id == c.reservation.provider_reservation_id

    assert Enum.any?(
             fields,
             &(&1.field == "starts_at" and &1.label == "AOS" and is_binary(&1.after_json))
           )

    assert %{open: 1} = ProviderChangeAttention.counts(c.organization_id, c.mission_id)

    assert {:ok, %{items: items}} = Attention.load(c.admin_scope, c.mission_id)
    assert Enum.any?(items, &(&1.source == "provider_change"))

    assert {:ok, _approved} =
             Contacts.approve_provider_change(c.admin_scope, item.id, hash, "Inside the plan")

    assert [] = ProviderChangeAttention.items(c.organization_id, c.mission_id)
    since = DateTime.add(DateTime.utc_now(), -60)

    assert [
             %{
               id: id,
               action: "approved",
               resolved_by: %{"kind" => "user"},
               note: "Inside the plan"
             }
           ] =
             ProviderChangeAttention.resolved_since(c.organization_id, c.mission_id, since)

    assert id == item.id
  end

  describe "a pass that has ended (L14 expiry)" do
    test "a pending change leaves Now, shows expired on the pass and can't be decided" do
      c = ended_pass()

      assert {:ok, _reservation} =
               ProviderChangeFixtures.advance(c, 2, %{
                 "starts_at" => ProviderChangeFixtures.shift(c.baseline["starts_at"], 60),
                 "ends_at" => ProviderChangeFixtures.shift(c.baseline["ends_at"], 60)
               })

      assert [] = ProviderChangeAttention.items(c.organization_id, c.mission_id)
      assert %{open: 0} = ProviderChangeAttention.counts(c.organization_id, c.mission_id)

      assert [%{provider_change: %{state: "pending_approval", expired: true} = change}] =
               ProviderChangeAttention.pass_items(c.organization_id, c.mission_id)

      assert {:error, :provider_change_expired} =
               Contacts.approve_provider_change(
                 c.admin_scope,
                 change.id,
                 change.proposal_hash,
                 "Late"
               )

      assert {:error, :provider_change_expired} =
               Contacts.reject_provider_change(
                 c.admin_scope,
                 change.id,
                 change.proposal_hash,
                 "Late"
               )

      assert [%{id: id, expired: true, resolution: nil}] =
               ProviderChangeAttention.pass_history(
                 c.organization_id,
                 c.mission_id,
                 c.reservation.provider_reservation_id
               )

      assert id == change.id
    end

    test "an acknowledgement leaves Now but can still be made from the pass, then is history" do
      c = ended_pass()

      assert {:ok, _reservation} =
               ProviderChangeFixtures.advance(c, 2, %{
                 "status" => "canceled",
                 "extensions" => %{"provider_change" => %{"effective" => true}}
               })

      assert [] = ProviderChangeAttention.items(c.organization_id, c.mission_id)

      assert [%{id: id, provider_change: %{expired: false, proposal_hash: hash}}] =
               ProviderChangeAttention.pass_items(c.organization_id, c.mission_id)

      assert %{id: ^id} = ProviderChangeAttention.item(c.organization_id, c.mission_id, id)

      assert {:ok, _acknowledged} =
               Contacts.acknowledge_provider_change(
                 c.admin_scope,
                 id,
                 hash,
                 "Seen after the pass"
               )

      assert [
               %{
                 id: ^id,
                 state: "acknowledged",
                 expired: false,
                 resolution: %{
                   action: "acknowledged",
                   by: %{"kind" => "user"},
                   reason: "Seen after the pass"
                 }
               }
             ] =
               ProviderChangeAttention.pass_history(
                 c.organization_id,
                 c.mission_id,
                 c.reservation.provider_reservation_id
               )
    end
  end

  # A pass that ended an hour ago (ten minutes long).
  defp ended_pass do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(-70, :minute)
      |> DateTime.truncate(:second)
      |> Map.put(:microsecond, {0, 6})

    ProviderChangeFixtures.setup_contact(%{}, starts_at: starts_at)
  end
end
