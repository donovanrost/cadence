defmodule Cadence.Accounts.InvitationDelivery do
  @moduledoc "Delivery port for organization invitations; the adapter supplies public URLs and mail transport."
  @callback deliver(struct(), struct(), binary()) :: {:ok, term()} | {:error, term()}

  def deliver(invitation, organization, token) do
    case Application.get_env(:cadence, :organization_invitation_delivery) do
      adapter when is_atom(adapter) and not is_nil(adapter) ->
        adapter.deliver(invitation, organization, token)

      _ ->
        {:error, :invitation_delivery_unavailable}
    end
  end
end
