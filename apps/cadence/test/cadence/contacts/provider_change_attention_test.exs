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
    assert Enum.any?(fields, &(&1.field == "starts_at" and is_binary(&1.after_json)))
    assert %{open: 1} = ProviderChangeAttention.counts(c.organization_id, c.mission_id)

    assert {:ok, %{items: items}} = Attention.load(c.admin_scope, c.mission_id)
    assert Enum.any?(items, &(&1.source == "provider_change"))

    assert {:ok, _approved} =
             Contacts.approve_provider_change(c.admin_scope, item.id, hash, "Inside the plan")

    assert [] = ProviderChangeAttention.items(c.organization_id, c.mission_id)
    since = DateTime.add(DateTime.utc_now(), -60)

    assert [%{id: id, action: "approved", resolved_by: %{"kind" => "user"}}] =
             ProviderChangeAttention.resolved_since(c.organization_id, c.mission_id, since)

    assert id == item.id
  end
end
