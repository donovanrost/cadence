defmodule Cadence.Control.Contacts.ProviderGrants do
  @moduledoc """
  Control-plane handoff from provider grant changes to affected reservations.

  Provider configuration owns grant revocation. Contacts owns the durable
  reservation review state that must reflect that revocation.
  """

  alias Cadence.Contacts.ProviderReservations

  @spec mark_reservations_for_review(map(), DateTime.t()) :: {:ok, non_neg_integer()}
  def mark_reservations_for_review(grant, %DateTime{} = now) when is_map(grant) do
    ProviderReservations.mark_provider_grant_for_review(grant, now)
  end
end
