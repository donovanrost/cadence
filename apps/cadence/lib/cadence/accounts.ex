defmodule Cadence.Accounts do
  @moduledoc """
  Platform users, local credentials, memberships, invitations, and browser sessions.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Accounts.{OrganizationInvitation, OrganizationMembership, Password, User}
  alias Cadence.Ids

  alias Cadence.Persistence.Schemas.{
    OrganizationInvitationRow,
    OrganizationMembershipRow,
    SetupWorkflowRow,
    UserLocalCredentialRow,
    UserRow,
    UserSessionTokenRow
  }

  alias Cadence.Repo
  alias Cadence.Setup.Workflow

  @bootstrap_provider_key "bootstrap_env"
  @password_provider_key "password"
  @bootstrap_session_context "bootstrap_admin"
  @browser_session_context "browser"
  @default_bootstrap_admin_display_name "Bootstrap Admin"
  @default_bootstrap_admin_session_ttl_seconds 86_400
  @default_browser_session_ttl_seconds 2_592_000
  @default_invitation_ttl_seconds 604_800

  @type user_session_context :: :bootstrap_admin | :browser

  @type issued_user_session :: %{
          user: User.t(),
          session_token: binary(),
          expires_at: DateTime.t(),
          current_organization_id: binary() | nil,
          temporary_setup_access?: boolean()
        }

  @type issued_bootstrap_admin_session :: issued_user_session()

  @type organization_access_result ::
          %{
            mode: :granted,
            user: User.t(),
            membership: OrganizationMembership.t()
          }
          | %{
              mode: :invited,
              invitation: OrganizationInvitation.t(),
              invitation_token: binary()
            }

  @spec bootstrap_admin_enabled?() :: boolean()
  def bootstrap_admin_enabled? do
    bootstrap_admin_config()
    |> Keyword.get(:enabled, false)
  end

  @spec ensure_bootstrap_admin() :: {:ok, User.t()} | {:error, term()}
  def ensure_bootstrap_admin do
    if bootstrap_admin_enabled?() do
      config = bootstrap_admin_config()
      email = Keyword.fetch!(config, :email)
      display_name = Keyword.get(config, :display_name, @default_bootstrap_admin_display_name)
      password = Keyword.fetch!(config, :password)

      Repo.transaction(fn ->
        with {:ok, persisted_user} <- upsert_bootstrap_admin_user(email, display_name),
             :ok <-
               upsert_local_credential(
                 Repo,
                 persisted_user.user_id,
                 @bootstrap_provider_key,
                 password,
                 setup_access_metadata()
               ) do
          persisted_user
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, %User{} = persisted_user} -> {:ok, persisted_user}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :bootstrap_admin_disabled}
    end
  end

  @spec sign_in(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    with {:ok, user} <- fetch_active_user_by_email(email),
         {:ok, credential_kind} <- resolve_credential_kind(user) do
      case credential_kind do
        :durable -> login_user(email, password)
        :bootstrap_admin -> login_bootstrap_admin(email, password)
      end
    end
  end

  @spec login_bootstrap_admin(binary(), binary()) ::
          {:ok, issued_user_session()} | {:error, term()}
  def login_bootstrap_admin(email, password)
      when is_binary(email) and is_binary(password) do
    with :ok <- ensure_bootstrap_admin_enabled(),
         normalized_email <- User.normalize_email(email),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             email: normalized_email,
             lifecycle_state: Atom.to_string(:active)
           ),
         {:ok, %User{} = user} <- ensure_platform_admin(UserRow.to_domain(user_row)),
         %UserLocalCredentialRow{} = credential_row <-
           Repo.get_by(UserLocalCredentialRow,
             user_id: user.user_id,
             provider_key: @bootstrap_provider_key,
             lifecycle_state: Atom.to_string(:active)
           ),
         true <-
           Password.verify_password(
             password,
             credential_row.password_hash,
             credential_row.password_salt,
             credential_row.password_iterations
           ) do
      issue_user_session(user, @bootstrap_session_context, nil)
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec login_user(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def login_user(email, password) when is_binary(email) and is_binary(password) do
    with normalized_email <- User.normalize_email(email),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             email: normalized_email,
             lifecycle_state: Atom.to_string(:active)
           ),
         %User{} = user <- UserRow.to_domain(user_row),
         :ok <- ensure_durable_login_user(user),
         %UserLocalCredentialRow{} = credential_row <-
           Repo.get_by(UserLocalCredentialRow,
             user_id: user.user_id,
             provider_key: @password_provider_key,
             lifecycle_state: Atom.to_string(:active)
           ),
         true <-
           Password.verify_password(
             password,
             credential_row.password_hash,
             credential_row.password_salt,
             credential_row.password_iterations
           ) do
      issue_user_session(
        user,
        @browser_session_context,
        default_user_organization_id(user.user_id)
      )
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec authenticate_user_session(binary()) ::
          {:ok, %{user: User.t(), session_context: user_session_context()}} | {:error, term()}
  def authenticate_user_session(session_token) when is_binary(session_token) do
    with %UserSessionTokenRow{} = token_row <- active_session_token_row(session_token),
         {:ok, session_context} <- normalize_session_context(token_row.context),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             user_id: token_row.user_id,
             lifecycle_state: Atom.to_string(:active)
           ) do
      {:ok, %{user: UserRow.to_domain(user_row), session_context: session_context}}
    else
      nil -> {:error, :unauthenticated}
      {:error, _reason} = error -> error
    end
  end

  @spec revoke_user_session(binary()) :: :ok
  def revoke_user_session(session_token) when is_binary(session_token) do
    token_digest = digest_token(session_token)

    UserSessionTokenRow
    |> where([row], row.token_digest == ^token_digest)
    |> Repo.delete_all()

    :ok
  end

  @spec revoke_bootstrap_admin_session(binary()) :: :ok
  def revoke_bootstrap_admin_session(session_token) when is_binary(session_token) do
    revoke_user_session(session_token)
  end

  @spec fetch_user(binary()) :: {:ok, User.t()} | {:error, term()}
  def fetch_user(user_id) when is_binary(user_id) do
    case Repo.get(UserRow, user_id) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :user_not_found}
    end
  end

  @spec fetch_user_by_email(binary()) :: {:ok, User.t()} | {:error, term()}
  def fetch_user_by_email(email) when is_binary(email) do
    case Repo.get_by(UserRow, email: User.normalize_email(email)) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :user_not_found}
    end
  end

  @spec preferred_organization_membership(binary(), binary() | nil) ::
          {:ok, OrganizationMembership.t() | nil}
  def preferred_organization_membership(user_id, current_organization_id \\ nil)
      when is_binary(user_id) do
    membership =
      case current_organization_id do
        organization_id when is_binary(organization_id) ->
          active_membership_query(user_id)
          |> where([row], row.organization_id == ^organization_id)
          |> Repo.one()

        _other ->
          nil
      end

    case membership do
      %OrganizationMembershipRow{} = row ->
        {:ok, OrganizationMembershipRow.to_domain(row)}

      nil ->
        case active_membership_query(user_id) |> Repo.one() do
          %OrganizationMembershipRow{} = row -> {:ok, OrganizationMembershipRow.to_domain(row)}
          nil -> {:ok, nil}
        end
    end
  end

  @spec list_organization_members(binary()) :: [
          %{membership: OrganizationMembership.t(), user: User.t()}
        ]
  def list_organization_members(organization_id) when is_binary(organization_id) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: m.user_id == u.user_id)
    |> where([m, _u], m.organization_id == ^organization_id and m.lifecycle_state == "active")
    |> order_by([m, _u], asc: m.inserted_at)
    |> select([m, u], {m, u})
    |> Repo.all()
    |> Enum.map(fn {membership_row, user_row} ->
      %{
        membership: OrganizationMembershipRow.to_domain(membership_row),
        user: UserRow.to_domain(user_row)
      }
    end)
  end

  @spec list_pending_invitations(binary()) :: [OrganizationInvitation.t()]
  def list_pending_invitations(organization_id) when is_binary(organization_id) do
    now = DateTime.utc_now()

    OrganizationInvitationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.status == "pending" and
        row.expires_at > ^now
    )
    |> order_by([row], asc: row.inserted_at)
    |> Repo.all()
    |> Enum.map(&OrganizationInvitationRow.to_domain/1)
  end

  @spec count_users() :: non_neg_integer()
  def count_users do
    UserRow
    |> where([row], row.lifecycle_state == "active")
    |> Repo.aggregate(:count, :user_id)
  end

  @spec establish_organization_access(binary(), binary(), keyword()) ::
          {:ok, organization_access_result()} | {:error, term()}
  def establish_organization_access(email, organization_id, opts \\ [])
      when is_binary(email) and is_binary(organization_id) and is_list(opts) do
    membership_role = Keyword.get(opts, :membership_role, :member)
    grant_platform_admin = Keyword.get(opts, :grant_platform_admin, false)
    invited_by_user_id = Keyword.fetch!(opts, :invited_by_user_id)
    display_name = Keyword.get(opts, :display_name)
    membership_metadata = Keyword.get(opts, :membership_metadata, %{})
    invitation_metadata = Keyword.get(opts, :invitation_metadata, %{})

    with {:ok, normalized_email} <- normalize_required_email(email),
         :ok <- validate_membership_role(membership_role) do
      case durable_user_by_email(normalized_email) do
        {:ok, %User{} = user} ->
          Repo.transaction(fn ->
            with {:ok, granted_user} <-
                   grant_platform_admin_if_requested(Repo, user, grant_platform_admin),
                 {:ok, membership} <-
                   upsert_membership(
                     Repo,
                     granted_user.user_id,
                     organization_id,
                     membership_role,
                     membership_metadata
                   ) do
              %{mode: :granted, user: granted_user, membership: membership}
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
          |> unwrap_transaction_result()

        :not_found ->
          Repo.transaction(fn ->
            with :ok <- revoke_pending_invitations(Repo, normalized_email, organization_id),
                 {:ok, %{invitation: invitation, invitation_token: invitation_token}} <-
                   insert_invitation(
                     Repo,
                     normalized_email,
                     organization_id,
                     membership_role,
                     grant_platform_admin,
                     invited_by_user_id,
                     display_name,
                     invitation_metadata
                   ) do
              %{mode: :invited, invitation: invitation, invitation_token: invitation_token}
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
          |> unwrap_transaction_result()
      end
    end
  end

  @spec fetch_organization_invitation(binary()) ::
          {:ok, OrganizationInvitation.t()} | {:error, term()}
  def fetch_organization_invitation(invitation_token) when is_binary(invitation_token) do
    token_digest = digest_token(invitation_token)

    case Repo.get_by(OrganizationInvitationRow, token_digest: token_digest) do
      nil ->
        {:error, :organization_invitation_not_found}

      %OrganizationInvitationRow{} = row ->
        invitation = OrganizationInvitationRow.to_domain(row)

        cond do
          invitation.status != :pending ->
            {:error, :organization_invitation_unavailable}

          OrganizationInvitation.expired?(invitation) ->
            expire_invitation(row)
            {:error, :organization_invitation_expired}

          true ->
            {:ok, invitation}
        end
    end
  end

  @spec accept_organization_invitation(binary(), map()) ::
          {:ok,
           %{
             user: User.t(),
             membership: OrganizationMembership.t(),
             invitation: OrganizationInvitation.t(),
             session_token: binary(),
             expires_at: DateTime.t(),
             current_organization_id: binary(),
             temporary_setup_access?: false
           }}
          | {:error, term()}
  def accept_organization_invitation(invitation_token, attrs)
      when is_binary(invitation_token) and is_map(attrs) do
    with {:ok, acceptance_attrs} <- validate_invitation_acceptance_attrs(attrs) do
      token_digest = digest_token(invitation_token)

      Repo.transaction(fn ->
        with {:ok, invitation_row, invitation} <- lock_usable_invitation(Repo, token_digest),
             {:ok, user} <- upsert_invited_user(Repo, invitation, acceptance_attrs),
             {:ok, user} <-
               grant_platform_admin_if_requested(Repo, user, invitation.grant_platform_admin),
             :ok <-
               upsert_local_credential(
                 Repo,
                 user.user_id,
                 @password_provider_key,
                 acceptance_attrs.password,
                 %{}
               ),
             {:ok, membership} <-
               upsert_membership(
                 Repo,
                 user.user_id,
                 invitation.organization_id,
                 invitation.membership_role,
                 %{
                   "accepted_via" => "organization_invitation",
                   "organization_invitation_id" => invitation.organization_invitation_id
                 }
               ),
             {:ok, accepted_invitation} <-
               mark_invitation_accepted(Repo, invitation_row, user.user_id),
             :ok <-
               maybe_record_setup_handoff_acceptance(Repo, accepted_invitation, user, membership),
             :ok <- revoke_all_user_sessions(Repo, user.user_id),
             {:ok, issued_session} <-
               issue_user_session(user, @browser_session_context, membership.organization_id) do
          %{
            user: user,
            membership: membership,
            invitation: accepted_invitation,
            session_token: issued_session.session_token,
            expires_at: issued_session.expires_at,
            current_organization_id: membership.organization_id,
            temporary_setup_access?: false
          }
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> unwrap_transaction_result()
    end
  end

  defp ensure_bootstrap_admin_enabled do
    if bootstrap_admin_enabled?(), do: :ok, else: {:error, :bootstrap_admin_disabled}
  end

  defp ensure_platform_admin(%User{} = user) do
    if :platform_admin in user.capabilities do
      {:ok, user}
    else
      {:error, :forbidden}
    end
  end

  defp ensure_durable_login_user(%User{} = user) do
    cond do
      user.lifecycle_state != :active ->
        {:error, :invalid_credentials}

      not User.confirmed?(user) ->
        {:error, :invalid_credentials}

      true ->
        :ok
    end
  end

  defp upsert_bootstrap_admin_user(email, display_name) do
    normalized_email = User.normalize_email(email)

    case Repo.get_by(UserRow, email: normalized_email) do
      nil ->
        user =
          User.new(%{
            user_id: bootstrap_admin_config() |> Keyword.get(:user_id, "user_bootstrap_admin"),
            email: normalized_email,
            display_name: display_name,
            capabilities: [:platform_admin],
            lifecycle_state: :active,
            metadata: setup_access_metadata()
          })

        upsert_user(Repo, user)

      %UserRow{} = row ->
        existing_user = UserRow.to_domain(row)

        user =
          User.new(%{
            user_id: existing_user.user_id,
            email: existing_user.email,
            display_name:
              if(User.confirmed?(existing_user),
                do: existing_user.display_name,
                else: display_name
              ),
            capabilities: add_platform_admin_capability(existing_user.capabilities),
            confirmed_at: existing_user.confirmed_at,
            lifecycle_state: :active,
            metadata:
              if(User.confirmed?(existing_user),
                do: existing_user.metadata,
                else: Map.merge(existing_user.metadata, setup_access_metadata())
              )
          })

        upsert_user(Repo, user)
    end
  end

  defp durable_user_by_email(email) when is_binary(email) do
    case Repo.get_by(UserRow, email: email) do
      %UserRow{} = row ->
        user = UserRow.to_domain(row)

        if durable_user?(user) do
          {:ok, user}
        else
          :not_found
        end

      nil ->
        :not_found
    end
  end

  defp durable_user?(%User{} = user) do
    user.lifecycle_state == :active and User.confirmed?(user) and
      active_password_credential?(user.user_id)
  end

  defp active_password_credential?(user_id) when is_binary(user_id) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: @password_provider_key,
      lifecycle_state: Atom.to_string(:active)
    ) != nil
  end

  defp fetch_active_user_by_email(email) when is_binary(email) do
    normalized_email = User.normalize_email(email)

    case Repo.get_by(UserRow,
           email: normalized_email,
           lifecycle_state: Atom.to_string(:active)
         ) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :invalid_credentials}
    end
  end

  defp resolve_credential_kind(%User{user_id: user_id}) do
    has_password = active_credential?(user_id, @password_provider_key)
    has_bootstrap = active_credential?(user_id, @bootstrap_provider_key)

    cond do
      has_password ->
        {:ok, :durable}

      has_bootstrap and bootstrap_admin_enabled?() and setup_pending?() ->
        {:ok, :bootstrap_admin}

      true ->
        {:error, :invalid_credentials}
    end
  end

  defp active_credential?(user_id, provider_key)
       when is_binary(user_id) and is_binary(provider_key) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: provider_key,
      lifecycle_state: Atom.to_string(:active)
    ) != nil
  end

  defp setup_pending? do
    case Cadence.Setup.fetch_initial_workflow() do
      {:ok, workflow} -> Cadence.Setup.active?(workflow)
      {:error, _reason} -> true
    end
  end

  defp upsert_user(repo, %User{} = user) do
    case repo.get_by(UserRow, email: user.email) do
      nil ->
        case repo.insert(UserRow.changeset(user)) do
          {:ok, %UserRow{} = row} -> {:ok, UserRow.to_domain(row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end

      %UserRow{} = row ->
        attrs = %{
          email: user.email,
          display_name: user.display_name,
          capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
          confirmed_at: user.confirmed_at,
          lifecycle_state: Atom.to_string(user.lifecycle_state),
          metadata: user.metadata
        }

        case repo.update(UserRow.update_changeset(row, attrs)) do
          {:ok, %UserRow{} = updated_row} -> {:ok, UserRow.to_domain(updated_row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  defp grant_platform_admin_if_requested(repo, %User{} = user, true) do
    updated_user = %User{user | capabilities: add_platform_admin_capability(user.capabilities)}
    upsert_user(repo, updated_user)
  end

  defp grant_platform_admin_if_requested(_repo, %User{} = user, false), do: {:ok, user}

  defp add_platform_admin_capability(capabilities) when is_list(capabilities) do
    capabilities
    |> List.wrap()
    |> Kernel.++([:platform_admin])
    |> Enum.uniq()
  end

  defp upsert_membership(repo, user_id, organization_id, role, metadata)
       when is_binary(user_id) and is_binary(organization_id) and is_map(metadata) do
    membership =
      OrganizationMembership.new(%{
        user_id: user_id,
        organization_id: organization_id,
        role: role,
        lifecycle_state: :active,
        metadata: metadata
      })

    case repo.get_by(OrganizationMembershipRow,
           user_id: user_id,
           organization_id: organization_id
         ) do
      nil ->
        case repo.insert(OrganizationMembershipRow.changeset(membership)) do
          {:ok, %OrganizationMembershipRow{} = row} ->
            {:ok, OrganizationMembershipRow.to_domain(row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}
        end

      %OrganizationMembershipRow{} = row ->
        case repo.update(
               OrganizationMembershipRow.update_changeset(row, %{
                 role: Atom.to_string(membership.role),
                 lifecycle_state: Atom.to_string(membership.lifecycle_state),
                 metadata: membership.metadata
               })
             ) do
          {:ok, %OrganizationMembershipRow{} = updated_row} ->
            {:ok, OrganizationMembershipRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  defp active_membership_query(user_id) when is_binary(user_id) do
    OrganizationMembershipRow
    |> where(
      [row],
      row.user_id == ^user_id and row.lifecycle_state == ^Atom.to_string(:active)
    )
    |> order_by([row], asc: row.inserted_at, asc: row.organization_id)
  end

  defp default_user_organization_id(user_id) when is_binary(user_id) do
    case preferred_organization_membership(user_id) do
      {:ok, %OrganizationMembership{} = membership} -> membership.organization_id
      {:ok, nil} -> nil
    end
  end

  defp insert_invitation(
         repo,
         email,
         organization_id,
         membership_role,
         grant_platform_admin,
         invited_by_user_id,
         display_name,
         metadata
       ) do
    invitation_token = generate_token()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(invitation_ttl_seconds(), :second)

    invitation =
      OrganizationInvitation.new(%{
        organization_id: organization_id,
        email: email,
        display_name: display_name,
        membership_role: membership_role,
        grant_platform_admin: grant_platform_admin,
        status: :pending,
        token_digest: digest_token(invitation_token),
        token_hint: token_hint(invitation_token),
        expires_at: expires_at,
        invited_by_user_id: invited_by_user_id,
        metadata: metadata
      })

    case repo.insert(OrganizationInvitationRow.changeset(invitation)) do
      {:ok, %OrganizationInvitationRow{} = row} ->
        {:ok,
         %{
           invitation: OrganizationInvitationRow.to_domain(row),
           invitation_token: invitation_token
         }}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp revoke_pending_invitations(repo, email, organization_id)
       when is_binary(email) and is_binary(organization_id) do
    OrganizationInvitationRow
    |> where(
      [row],
      row.email == ^email and row.organization_id == ^organization_id and row.status == "pending"
    )
    |> repo.update_all(set: [status: "revoked"])

    :ok
  end

  defp validate_membership_role(role) do
    if role in OrganizationMembership.roles() do
      :ok
    else
      {:error, :invalid_organization_role}
    end
  end

  defp normalize_required_email(email) when is_binary(email) do
    case User.normalize_email(email) do
      nil -> {:error, {:invalid_param, "email", :required}}
      "" -> {:error, {:invalid_param, "email", :required}}
      normalized_email -> {:ok, normalized_email}
    end
  end

  defp validate_invitation_acceptance_attrs(attrs) when is_map(attrs) do
    display_name =
      attrs
      |> Map.get(:display_name, Map.get(attrs, "display_name"))
      |> present_string()

    password =
      attrs
      |> Map.get(:password, Map.get(attrs, "password"))
      |> present_string()

    cond do
      is_nil(display_name) ->
        {:error, {:invalid_param, "display_name", :required}}

      is_nil(password) ->
        {:error, {:invalid_param, "password", :required}}

      String.length(password) < 12 ->
        {:error, {:invalid_param, "password", :too_short}}

      true ->
        {:ok, %{display_name: display_name, password: password}}
    end
  end

  defp lock_usable_invitation(repo, token_digest) when is_binary(token_digest) do
    row =
      OrganizationInvitationRow
      |> where([row], row.token_digest == ^token_digest)
      |> lock("FOR UPDATE")
      |> repo.one()

    case row do
      nil ->
        {:error, :organization_invitation_not_found}

      %OrganizationInvitationRow{} = invitation_row ->
        invitation = OrganizationInvitationRow.to_domain(invitation_row)

        cond do
          invitation.status != :pending ->
            {:error, :organization_invitation_unavailable}

          OrganizationInvitation.expired?(invitation) ->
            expire_locked_invitation(repo, invitation_row, invitation)

          true ->
            {:ok, invitation_row, invitation}
        end
    end
  end

  defp upsert_invited_user(repo, %OrganizationInvitation{} = invitation, acceptance_attrs)
       when is_map(acceptance_attrs) do
    email = invitation.email
    display_name = Map.fetch!(acceptance_attrs, :display_name)

    case repo.get_by(UserRow, email: email) do
      nil ->
        user =
          User.new(%{
            email: email,
            display_name: display_name,
            capabilities: [],
            confirmed_at: DateTime.utc_now(),
            lifecycle_state: :active,
            metadata: %{}
          })

        upsert_user(repo, user)

      %UserRow{} = row ->
        existing_user = UserRow.to_domain(row)

        updated_user =
          User.new(%{
            user_id: existing_user.user_id,
            email: existing_user.email,
            display_name: display_name,
            capabilities: existing_user.capabilities,
            confirmed_at: existing_user.confirmed_at || DateTime.utc_now(),
            lifecycle_state: :active,
            metadata: existing_user.metadata
          })

        upsert_user(repo, updated_user)
    end
  end

  defp mark_invitation_accepted(repo, %OrganizationInvitationRow{} = row, accepted_by_user_id)
       when is_binary(accepted_by_user_id) do
    accepted_at = DateTime.utc_now()

    case repo.update(
           OrganizationInvitationRow.update_changeset(row, %{
             status: Atom.to_string(:accepted),
             membership_role: row.membership_role,
             grant_platform_admin: row.grant_platform_admin,
             expires_at: row.expires_at,
             accepted_by_user_id: accepted_by_user_id,
             accepted_at: accepted_at,
             metadata: row.metadata
           })
         ) do
      {:ok, %OrganizationInvitationRow{} = updated_row} ->
        {:ok, OrganizationInvitationRow.to_domain(updated_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_record_setup_handoff_acceptance(
         repo,
         %OrganizationInvitation{} = invitation,
         %User{} = user,
         %OrganizationMembership{} = membership
       ) do
    case invitation.metadata["setup_workflow_id"] do
      workflow_id when is_binary(workflow_id) ->
        update_setup_handoff_workflow(repo, workflow_id, invitation, user, membership)

      _other ->
        :ok
    end
  end

  defp expire_invitation(%OrganizationInvitationRow{} = row) do
    Repo.update(
      OrganizationInvitationRow.update_changeset(row, %{
        status: Atom.to_string(:expired),
        expires_at: row.expires_at,
        membership_role: row.membership_role,
        grant_platform_admin: row.grant_platform_admin,
        metadata: row.metadata
      })
    )

    :ok
  end

  defp expire_locked_invitation(repo, %OrganizationInvitationRow{} = invitation_row, invitation) do
    case repo.update(
           OrganizationInvitationRow.update_changeset(invitation_row, %{
             membership_role: invitation_row.membership_role,
             grant_platform_admin: invitation_row.grant_platform_admin,
             status: Atom.to_string(:expired),
             expires_at: invitation.expires_at,
             metadata: invitation.metadata
           })
         ) do
      {:ok, _row} -> {:error, :organization_invitation_expired}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp update_setup_handoff_workflow(
         repo,
         workflow_id,
         %OrganizationInvitation{} = invitation,
         %User{} = user,
         %OrganizationMembership{} = membership
       ) do
    case repo.get(SetupWorkflowRow, workflow_id) do
      %SetupWorkflowRow{} = workflow_row ->
        workflow_row
        |> accepted_setup_workflow(invitation, user, membership)
        |> persist_setup_workflow_update(repo, workflow_row)

      nil ->
        :ok
    end
  end

  defp accepted_setup_workflow(
         %SetupWorkflowRow{} = workflow_row,
         %OrganizationInvitation{} = invitation,
         %User{} = user,
         %OrganizationMembership{} = membership
       ) do
    workflow = SetupWorkflowRow.to_domain(workflow_row)

    Workflow.new(%{
      setup_workflow_id: workflow.setup_workflow_id,
      current_step:
        if(workflow.current_step == :pending_durable_admin_handoff,
          do: :pending_completion,
          else: workflow.current_step
        ),
      active_organization_id: workflow.active_organization_id,
      created_by_user_id: workflow.created_by_user_id,
      completed_at: workflow.completed_at,
      metadata:
        Map.merge(workflow.metadata, %{
          "durable_admin_handoff" => %{
            "status" => "accepted",
            "mode" => "invitation",
            "email" => invitation.email,
            "user_id" => user.user_id,
            "organization_membership_id" => membership.organization_membership_id,
            "organization_role" => Atom.to_string(membership.role),
            "platform_admin" => invitation.grant_platform_admin,
            "invitation_id" => invitation.organization_invitation_id,
            "accepted_at" => iso8601(invitation.accepted_at)
          }
        })
    })
  end

  defp persist_setup_workflow_update(
         %Workflow{} = workflow,
         repo,
         %SetupWorkflowRow{} = workflow_row
       ) do
    case repo.update(SetupWorkflowRow.update_changeset(workflow_row, workflow)) do
      {:ok, _updated_row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_all_user_sessions(repo, user_id) when is_binary(user_id) do
    UserSessionTokenRow
    |> where([row], row.user_id == ^user_id)
    |> repo.delete_all()

    :ok
  end

  defp upsert_local_credential(repo, user_id, provider_key, password, metadata)
       when is_binary(user_id) and is_binary(provider_key) and is_binary(password) and
              is_map(metadata) do
    attrs = local_credential_attrs(user_id, provider_key, password, metadata)

    case repo.get_by(UserLocalCredentialRow, user_id: user_id, provider_key: provider_key) do
      nil -> insert_local_credential(repo, attrs)
      %UserLocalCredentialRow{} = row -> update_local_credential(repo, row, attrs)
    end
  end

  defp active_session_token_row(session_token) do
    token_digest = digest_token(session_token)

    UserSessionTokenRow
    |> where([row], row.token_digest == ^token_digest and row.expires_at > ^DateTime.utc_now())
    |> Repo.one()
  end

  defp issue_user_session(%User{} = user, session_context, current_organization_id) do
    session_token = generate_token()
    expires_at = DateTime.utc_now() |> DateTime.add(session_ttl_seconds(session_context), :second)

    attrs = %{
      session_token_id: Ids.new("sess"),
      user_id: user.user_id,
      context: session_context,
      token_digest: digest_token(session_token),
      token_hint: token_hint(session_token),
      expires_at: expires_at,
      metadata:
        if(session_context == @bootstrap_session_context, do: setup_access_metadata(), else: %{})
    }

    case Repo.insert(UserSessionTokenRow.changeset(attrs)) do
      {:ok, %UserSessionTokenRow{}} ->
        {:ok,
         %{
           user: user,
           session_token: session_token,
           expires_at: expires_at,
           current_organization_id: current_organization_id,
           temporary_setup_access?: session_context == @bootstrap_session_context
         }}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp normalize_session_context(@bootstrap_session_context), do: {:ok, :bootstrap_admin}
  defp normalize_session_context(@browser_session_context), do: {:ok, :browser}
  defp normalize_session_context(_other), do: {:error, :unauthenticated}

  defp bootstrap_admin_config do
    Application.get_env(:cadence, :bootstrap_admin, [])
  end

  defp setup_access_metadata do
    %{"bootstrap_admin" => true, "setup_access" => true}
  end

  defp session_ttl_seconds(@bootstrap_session_context) do
    bootstrap_admin_config()
    |> Keyword.get(:session_ttl_seconds, @default_bootstrap_admin_session_ttl_seconds)
  end

  defp session_ttl_seconds(@browser_session_context), do: @default_browser_session_ttl_seconds

  defp invitation_ttl_seconds do
    Application.get_env(
      :cadence,
      :organization_invitation_ttl_seconds,
      @default_invitation_ttl_seconds
    )
  end

  defp unwrap_transaction_result({:ok, result}), do: {:ok, result}
  defp unwrap_transaction_result({:error, reason}), do: {:error, reason}

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    trimmed_value = String.trim(value)
    if trimmed_value == "", do: nil, else: trimmed_value
  end

  defp present_string(_other), do: nil

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp generate_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp digest_token(session_token) when is_binary(session_token) do
    :sha256
    |> :crypto.hash(session_token)
    |> Base.encode16(case: :lower)
  end

  defp token_hint(session_token) do
    session_token
    |> String.slice(-6, 6)
  end

  defp local_credential_attrs(user_id, provider_key, password, metadata) do
    password_document = Password.hash_password(password)

    %{
      local_credential_id: Ids.new("cred"),
      user_id: user_id,
      provider_key: provider_key,
      password_hash: password_document.password_hash,
      password_salt: password_document.password_salt,
      password_iterations: password_document.password_iterations,
      lifecycle_state: Atom.to_string(:active),
      metadata: metadata
    }
  end

  defp insert_local_credential(repo, attrs) when is_map(attrs) do
    case repo.insert(UserLocalCredentialRow.changeset(attrs)) do
      {:ok, %UserLocalCredentialRow{}} -> :ok
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp update_local_credential(repo, %UserLocalCredentialRow{} = row, attrs) when is_map(attrs) do
    case repo.update(
           UserLocalCredentialRow.update_changeset(
             row,
             Map.drop(attrs, [:local_credential_id, :user_id, :provider_key])
           )
         ) do
      {:ok, %UserLocalCredentialRow{}} -> :ok
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end
end
