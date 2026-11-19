defmodule Cadence.Administration.OrganizationPeople do
  @moduledoc """
  The organization people directory and member invitations for organization
  admins (the console People screen).

  Capabilities are evaluated on the server (DECISIONS #2) in a small,
  stable vocabulary the UI gates on. Each is derived by calling the policy
  function that enforces it, for a scope built from that member
  (DECISIONS #38), never from a role table:

  - `org.manage_members`, `org.invite`: `Policy` `:manage_organization_members`.
  - Other contexts' capabilities (commanding's `command.request` /
    `command.approve` from its review policy) come in through the
    `:capabilities` option, since this identity module can't depend on them.
  """

  alias Cadence.{Accounts, Organizations}
  alias Cadence.Accounts.{InvitationDelivery, MembershipAdministration, OrganizationMembership}
  alias Cadence.Auth.{Policy, Scope}

  @roles %{"member" => :member, "organization_admin" => :organization_admin}

  @doc """
  The directory. `opts[:capabilities]` (`Scope.t() -> [binary()]`) adds
  capabilities evaluated by other contexts for each member's scope.
  """
  @spec load(Scope.t(), binary(), keyword()) ::
          {:ok, map()} | {:error, :forbidden | :organization_not_found}
  def load(%Scope{} = scope, organization_id, opts \\ []) do
    with :ok <- authorize(scope, :operate_organization, organization_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id) do
      extra = Keyword.get(opts, :capabilities, fn _scope -> [] end)
      scopes = member_scopes(organization)

      {:ok,
       %{
         members:
           Enum.map(Accounts.list_member_directory(organization_id), fn row ->
             member(row, Map.get(scopes, row.user_id), extra)
           end),
         invitations:
           organization_id
           |> Accounts.list_invitation_directory(include_recent: true)
           |> Enum.map(&invitation(&1, DateTime.utc_now())),
         permissions: permissions(scope, organization_id)
       }}
    end
  end

  @doc "Service identities for organization admins. `last_used_at` is not tracked yet."
  @spec service_identities(Scope.t(), binary()) :: {:ok, map()} | {:error, :forbidden}
  def service_identities(%Scope{} = scope, organization_id) do
    with :ok <- authorize(scope, :manage_service_identities, organization_id) do
      missions =
        organization_id
        |> Cadence.Missions.list_missions()
        |> Map.new(&{&1.mission_id, &1.display_name})

      {:ok,
       %{
         service_identities:
           organization_id
           |> Cadence.Auth.list_service_identity_directory()
           |> Enum.map(&service_identity(&1, missions)),
         rotation_policy_days: nil
       }}
    end
  end

  defp service_identity(row, missions) do
    %{
      id: row.id,
      name: row.name,
      scope_summary: scope_summary(row.capabilities, missions[row.mission_id]),
      capabilities: row.capabilities,
      mission: row.mission_id && %{id: row.mission_id, name: missions[row.mission_id]},
      last_used_at: nil,
      key_created_at: row.key_created_at
    }
  end

  defp scope_summary(capabilities, mission_name) do
    abilities =
      case capabilities do
        [] ->
          "No capabilities"

        list ->
          Enum.map_join(list, ", ", &(&1 |> String.replace("_", " ") |> String.capitalize()))
      end

    if mission_name, do: "#{abilities} · #{mission_name}", else: "#{abilities} · all missions"
  end

  @doc "The organization capabilities `scope` holds in `organization_id`, from enforcing policy."
  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, organization_id) do
    if authorize(scope, :manage_organization_members, organization_id) == :ok,
      do: ["org.invite", "org.manage_members"],
      else: []
  end

  # Each active member's scope in the organization, as the server builds it
  # for their requests (no admin mode: that's a per-session opt-in).
  defp member_scopes(organization) do
    organization.organization_id
    |> Accounts.list_organization_members()
    |> Map.new(fn %{user: user, membership: membership} ->
      {user.user_id,
       Scope.new(%{
         user: user,
         organization_id: organization.organization_id,
         organization: organization,
         organization_membership: membership
       })}
    end)
  end

  @doc "Invites `email` with `role`. Returns the invitation and whether mail was submitted."
  @spec invite(Scope.t(), binary(), map()) ::
          {:ok, map()}
          | {:error, :forbidden | :organization_not_found | :already_member | :already_invited}
          | {:error, {:invalid, map()}}
  def invite(%Scope{user: %{}} = scope, organization_id, params) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id),
         {:ok, email, role} <- validate(params),
         :ok <- not_already(organization_id, email) do
      issue(scope, organization, email, role)
    end
  end

  def invite(%Scope{}, _organization_id, _params), do: {:error, :forbidden}

  # Creates the invitation (revoking any pending one for the email) and delivers it.
  defp issue(%Scope{user: %{user_id: inviter_id}} = scope, organization, email, role) do
    with {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} <-
           Accounts.establish_organization_access(email, organization.organization_id,
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

  @doc """
  Changes a member's role (`member | organization_admin`). The last organization admin can't be
  demoted (`:last_admin`).
  """
  @spec change_role(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def change_role(%Scope{} = scope, organization_id, user_id, params) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id),
         {:ok, role} <- role_param(params) do
      MembershipAdministration.change_role(organization_id, user_id, role, actor_id(scope))
    end
  end

  @doc "Removes a member (revokes the membership). The last organization admin can't be removed."
  @spec remove_member(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def remove_member(%Scope{} = scope, organization_id, user_id) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id) do
      MembershipAdministration.remove_member(organization_id, user_id, actor_id(scope))
    end
  end

  @doc "Revokes a pending invitation; its link stops working."
  @spec revoke_invitation(Scope.t(), binary(), binary()) :: :ok | {:error, term()}
  def revoke_invitation(%Scope{} = scope, organization_id, invitation_id) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id) do
      MembershipAdministration.revoke_invitation(organization_id, invitation_id, actor_id(scope))
    end
  end

  @doc """
  Resends a pending invitation: a fresh link (the old one stops working) with the same email and
  role, delivered again. Returns the new invitation like `invite/3`.
  """
  @spec resend_invitation(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def resend_invitation(%Scope{user: %{}} = scope, organization_id, invitation_id) do
    with :ok <- authorize(scope, :manage_organization_members, organization_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id),
         {:ok, pending} <-
           MembershipAdministration.fetch_pending_invitation(organization_id, invitation_id) do
      issue(
        scope,
        organization,
        pending.email,
        OrganizationMembership.normalize_role(pending.membership_role)
      )
    end
  end

  def resend_invitation(%Scope{}, _organization_id, _invitation_id), do: {:error, :forbidden}

  defp actor_id(%Scope{user: %{user_id: id}}), do: id
  defp actor_id(_scope), do: nil

  defp role_param(params) do
    case Map.fetch(@roles, Map.get(params, "role")) do
      {:ok, role} -> {:ok, role}
      :error -> {:error, {:invalid, %{role: "Choose member or organization_admin."}}}
    end
  end

  defp member(row, member_scope, extra) do
    %{
      user_id: row.user_id,
      display_name: row.display_name,
      email: row.email,
      role: String.to_existing_atom(row.role),
      capabilities: member_capabilities(member_scope, extra),
      joined_at: row.joined_at
    }
  end

  defp member_capabilities(nil, _extra), do: []

  defp member_capabilities(member_scope, extra),
    do: extra.(member_scope) ++ permissions(member_scope, member_scope.organization_id)

  # Explicit map, never to_existing_atom (qa #53). A pending one past its expiry reads expired.
  @invitation_status %{
    "pending" => :pending,
    "accepted" => :accepted,
    "declined" => :declined,
    "revoked" => :revoked,
    "expired" => :expired
  }

  defp invitation(row, now) do
    status = Map.get(@invitation_status, row.status, :expired)

    status =
      if status == :pending and DateTime.compare(row.expires_at, now) != :gt,
        do: :expired,
        else: status

    %{
      id: row.id,
      email: row.email,
      role: row.role,
      invited_by: row.invited_by_name && %{name: row.invited_by_name},
      sent_at: row.sent_at,
      expires_at: row.expires_at,
      status: status,
      decided_at: if(status == :pending, do: nil, else: row.decided_at)
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
