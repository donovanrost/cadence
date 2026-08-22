defmodule CadenceWeb.UserNotifier do
  @moduledoc false

  import Swoosh.Email

  alias Cadence.Accounts.OrganizationInvitation
  alias Cadence.Organizations.Organization
  alias CadenceWeb.Mailer

  @from_address {"Cadence", "no-reply@cadence.local"}

  @spec deliver_organization_invitation(
          OrganizationInvitation.t(),
          Organization.t(),
          binary()
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_organization_invitation(
        %OrganizationInvitation{} = invitation,
        %Organization{} = organization,
        acceptance_url
      )
      when is_binary(acceptance_url) do
    email =
      new()
      |> to(invitation.email)
      |> from(@from_address)
      |> subject("Cadence invitation for #{organization.display_name}")
      |> text_body(invitation_body(invitation, organization, acceptance_url))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp invitation_body(
         %OrganizationInvitation{} = invitation,
         %Organization{} = organization,
         url
       ) do
    """

    ==============================

    You have been invited to Cadence.

    Organization: #{organization.display_name}
    Role: #{humanize_role(invitation.membership_role)}
    Platform Admin: #{if(invitation.grant_platform_admin, do: "Yes", else: "No")}

    Accept the invitation and create your account:

    #{url}

    This invitation expires at #{DateTime.to_iso8601(invitation.expires_at)}.

    If you were not expecting this invitation, you can ignore this email.

    ==============================
    """
  end

  defp humanize_role(:organization_admin), do: "Organization Admin"
  defp humanize_role(:member), do: "Member"
end
