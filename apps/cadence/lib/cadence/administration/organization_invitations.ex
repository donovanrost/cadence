defmodule Cadence.Administration.OrganizationInvitations do
  @moduledoc "Authorized organization invitations with separate persistence and mail submission outcomes."
  alias Cadence.{Accounts, Ids, Organizations}
  alias Cadence.Accounts.InvitationDelivery
  alias Cadence.Administration.Access

  def load(scope, organization_id) do
    with {:ok, user} <- Access.authorize(scope),
         true <- Ids.valid_identifier?(organization_id),
         {:ok, org} <- Organizations.fetch_organization(organization_id) do
      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "organization" => %{
           "id" => org.organization_id,
           "name" => org.display_name,
           "slug" => org.slug
         },
         "submitted" => nil
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def create(scope, organization_id, input) do
    with {:ok, user} <- Access.authorize(scope),
         true <- Ids.valid_identifier?(organization_id),
         {:ok, org} <- Organizations.fetch_organization(organization_id),
         {:ok, values} <- validate(input),
         {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} <-
           Accounts.establish_organization_access(values.email, organization_id,
             membership_role: values.role,
             grant_platform_admin: values.grant_platform_admin,
             invited_by_user_id: user.user_id,
             display_name: values.name,
             force_invitation: true
           ) do
      {:ok,
       %{
         "id" => invitation.organization_invitation_id,
         "email" => invitation.email,
         "role" => Atom.to_string(invitation.membership_role),
         "grant_platform_admin" => invitation.grant_platform_admin,
         "expires_at" => DateTime.to_iso8601(invitation.expires_at),
         "delivery" => deliver(invitation, org, token)
       }}
    else
      {:invalid, _} = invalid -> invalid
      _ -> {:error, :unavailable}
    end
  end

  defp validate(
         %{
           "email" => email,
           "display_name" => name,
           "membership_role" => role,
           "grant_platform_admin" => grant
         } = values
       )
       when map_size(values) == 4 and is_binary(email) and is_binary(name) and is_boolean(grant) do
    email = email |> String.trim() |> String.downcase()
    name = String.trim(name)

    cond do
      not valid_email?(email) ->
        {:invalid, %{"email" => "Enter a valid email address."}}

      not valid_name?(name) ->
        {:invalid, %{"display_name" => "Use a display name of up to 200 bytes."}}

      role not in ["member", "organization_admin"] ->
        {:invalid, %{"membership_role" => "Choose a membership role."}}

      true ->
        {:ok,
         %{
           email: email,
           name: if(name == "", do: nil, else: name),
           role:
             Map.fetch!(%{"member" => :member, "organization_admin" => :organization_admin}, role),
           grant_platform_admin: grant
         }}
    end
  end

  defp validate(_), do: {:invalid, %{"form" => "Complete the invitation fields."}}

  defp valid_email?(email) do
    byte_size(email) in 3..254 and String.match?(email, ~r/^[^\s@]+@[^\s@]+$/u) and
      not String.match?(email, ~r/[\x00-\x1f\x7f]/u)
  end

  defp valid_name?(name),
    do: byte_size(name) <= 200 and not String.match?(name, ~r/[\x00-\x1f\x7f]/u)

  defp deliver(invitation, organization, token) do
    case InvitationDelivery.deliver(invitation, organization, token) do
      {:ok, _} -> "submitted"
      _ -> "unavailable"
    end
  rescue
    _ -> "unavailable"
  catch
    :exit, _ -> "unavailable"
  end
end
