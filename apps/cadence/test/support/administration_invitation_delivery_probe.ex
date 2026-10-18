defmodule Cadence.Test.AdministrationInvitationDeliveryProbe do
  @moduledoc false
  @behaviour Cadence.Accounts.InvitationDelivery
  def deliver(invitation, organization, token) do
    send(
      self(),
      {:invitation_mail_attempt, invitation.organization_invitation_id,
       organization.organization_id, is_binary(token) and byte_size(token) > 0}
    )

    case Process.get(:administration_invitation_delivery_result, :submitted) do
      :submitted -> {:ok, :queued}
      :failed -> {:error, :mail_unavailable}
      :raised -> raise "Test mail transport unavailable"
    end
  end
end
