defmodule Cadence.Administration.OrganizationPeople do
  @moduledoc """
  The organization people directory and member invitations for organization
  admins (the console People screen).

  Capabilities are evaluated on the server (DECISIONS #2) in a small,
  stable vocabulary the UI gates on, mapped to today's policy until Cedar:

  | capability | today |
  | --- | --- |
  | `command.request` | any active member (`operate_mission`) |
  | `command.approve` | any active human member (a second operator; never the requester) |
  | `org.manage_members` | `organization_admin` |
  | `org.invite` | `organization_admin` |
  """

  alias Cadence.{Accounts, Organizations}
  alias Cadence.Accounts.InvitationDelivery
  alias Cadence.Auth.{Policy, Scope}

  @roles %{"member" => :member, "organization_admin" => :organization_admin}

  @spec load(Scope.t(), binary()) :: {:ok, map()} | {:error, :forbidden | :organization_not_found}
  def load(%Scope{} = scope, organization_id) do
    with :ok <- authorize(scope, :operate_organization, organization_id),
         {:ok, _org} <- Organizations.fetch_organization(organization_id) do
      {:ok,
       %{
         members: Enum.map(Accounts.list_member_directory(organization_id), &member/1),
         invitations:
           Enum.map(Accounts.list_invitation_directory(organization_id), &invitation/1),
         permissions: permissions(scope, organization_id)
       }}
    end
  end

  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, organization_id) do
    if authorize(scope, :manage_organization_members, organization_id) == :ok,
      do: ["org.invite", "org.manage_members"],
      else: []
  end

  @doc "Invites `email` with `role`. Returns the invitation and whether mail was submitted."
  @spec invite(Scope.t(), binary(), map()) ::
          {:ok, map()}
          | {:error, :forbidden | :organization_not_found | :already_member | :already_invited}
          | {:error, {:invalid, map()}}
  def invite(%Scope{user: %{user_id: inviter_id}} = scope, organization_id, params) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id),
         {:ok, email, role} <- validate(params),
         :ok <- not_already(organization_id, email),
         {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} <-
           Accounts.establish_organization_access(email, organization_id,
             membership_role: role,
             invited_by_user_id: inviter_id,
             force_invitation: true
           ) do
      {:ok,
       %{
         id: invitation.organization_invitation_id,
         email: invitation.email,
         role: invitation.membership_role,
         invited_by: %{name: scope.user.display_name},
         sent_at: DateTime.utc_now(),
         expires_at: invitation.expires_at,
         status: :pending,
         delivery: deliver(invitation, organization, token)
       }}
    end
  end

  def invite(%Scope{}, _organization_id, _params), do: {:error, :forbidden}

  defp member(row) do
    role = String.to_existing_atom(row.role)

    %{
      user_id: row.user_id,
      display_name: row.display_name,
      email: row.email,
      role: role,
      capabilities: member_capabilities(role),
      joined_at: row.joined_at
    }
  end

  defp member_capabilities(:organization_admin),
    do: ["command.request", "command.approve", "org.manage_members", "org.invite"]

  defp member_capabilities(_member), do: ["command.request", "command.approve"]

  defp invitation(row) do
    %{
      id: row.id,
      email: row.email,
      role: row.role,
      invited_by: row.invited_by_name && %{name: row.invited_by_name},
      sent_at: row.sent_at,
      expires_at: row.expires_at,
      status: :pending
    }
  end

  defp validate(params) do
    email = params |> Map.get("email", "") |> to_string() |> String.trim() |> String.downcase()
    role = Map.get(@roles, Map.get(params, "role", "member"))

    cond do
      not (byte_size(email) in 3..254 and String.match?(email, ~r/^[^\s@]+@[^\s@]+$/u)) ->
        {:error, {:invalid, %{email: "Enter a valid email address."}}}

      is_nil(role) ->
        {:error, {:invalid, %{role: "Choose member or organization_admin."}}}

      true ->
        {:ok, email, role}
    end
  end

  defp not_already(organization_id, email) do
    cond do
      Enum.any?(
        Accounts.list_member_directory(organization_id),
        &(String.downcase(&1.email) == email)
      ) ->
        {:error, :already_member}

      Enum.any?(Accounts.list_invitation_directory(organization_id), &(&1.email == email)) ->
        {:error, :already_invited}

      true ->
        :ok
    end
  end

  defp authorize(scope, action, organization_id),
    do: Policy.authorize(scope, action, %{organization_id: organization_id})

  defp deliver(invitation, organization, token) do
    case InvitationDelivery.deliver(invitation, organization, token) do
      {:ok, _} -> :submitted
      _other -> :unavailable
    end
  rescue
    _error -> :unavailable
  catch
    :exit, _reason -> :unavailable
  end
end
