defmodule Cadence.Auth do
  @moduledoc """
  Browser and service authentication for Cadence actors.
  """

  import Ecto.Query

  alias Cadence.Accounts
  alias Cadence.Accounts.OrganizationMembership
  alias Cadence.Auth.{Scope, ServiceIdentity, ServiceIdentityRow}
  alias Cadence.Missions
  alias Cadence.Organizations
  alias Cadence.Repo
  alias Ecto.Changeset

  @type issued_service_identity :: %{
          service_identity: ServiceIdentity.t(),
          api_token: binary()
        }

  @spec issue_service_identity(ServiceIdentity.t()) ::
          {:ok, issued_service_identity()} | {:error, term()}
  def issue_service_identity(%ServiceIdentity{} = service_identity) do
    api_token = generate_api_token()

    with :ok <- validate_service_identity_scope(service_identity) do
      persist_service_identity(service_identity, api_token)
    end
  end

  @spec authenticate_api_token(binary()) :: {:ok, Scope.t()} | {:error, term()}
  def authenticate_api_token(api_token) when is_binary(api_token) do
    token_digest = digest_api_token(api_token)

    service_identity_row =
      ServiceIdentityRow
      |> where(
        [service_identity_row],
        service_identity_row.token_digest == ^token_digest and
          service_identity_row.lifecycle_state == "active"
      )
      |> Repo.one()

    case service_identity_row do
      %ServiceIdentityRow{} = row ->
        with {:ok, organization} <- Organizations.fetch_organization(row.organization_id),
             {:ok, mission} <- fetch_scope_mission(row),
             service_identity <- ServiceIdentityRow.to_domain(row) do
          {:ok,
           Scope.new(%{
             organization_id: organization.organization_id,
             organization: organization,
             mission: mission,
             service_identity: service_identity
           })}
        else
          {:error, reason} -> {:error, reason}
        end

      nil ->
        {:error, :unauthenticated}
    end
  end

  @spec authenticate_browser_session(binary(), keyword()) ::
          {:ok, Scope.t()} | {:error, term()}
  def authenticate_browser_session(session_token, opts \\ [])
      when is_binary(session_token) and is_list(opts) do
    with {:ok, %{user: user, session_context: :browser}} <-
           Accounts.authenticate_user_session(session_token),
         admin_mode? <- Keyword.get(opts, :admin_mode?, false),
         {:ok, organization_membership, organization} <-
           browser_organization_context(
             user,
             Keyword.get(opts, :current_organization_id),
             admin_mode?
           ) do
      {:ok,
       Scope.new(%{
         user: user,
         organization_id: organization && organization.organization_id,
         organization: organization,
         organization_membership: organization_membership,
         admin_mode?: admin_mode?
       })}
    end
  end

  @spec sign_in(binary(), binary()) :: {:ok, Accounts.issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    Accounts.sign_in(email, password)
  end

  @spec login_environment_admin(binary(), binary()) ::
          {:ok, Accounts.issued_user_session()} | {:error, term()}
  def login_environment_admin(email, password)
      when is_binary(email) and is_binary(password) do
    Accounts.login_environment_admin(email, password)
  end

  @spec login_user(binary(), binary()) :: {:ok, Accounts.issued_user_session()} | {:error, term()}
  def login_user(email, password) when is_binary(email) and is_binary(password) do
    Accounts.login_user(email, password)
  end

  @spec verify_user_password(Cadence.Accounts.User.t(), binary()) ::
          :ok | {:error, :invalid_credentials}
  def verify_user_password(%Cadence.Accounts.User{} = user, password)
      when is_binary(password) do
    Accounts.verify_user_password(user, password)
  end

  @spec reconcile_environment_admin() ::
          {:ok, Cadence.Accounts.User.t() | nil} | {:error, term()}
  def reconcile_environment_admin do
    Accounts.reconcile_environment_admin()
  end

  @spec revoke_user_session(binary()) :: :ok
  def revoke_user_session(session_token) when is_binary(session_token) do
    Accounts.revoke_user_session(session_token)
  end

  @spec fetch_organization_invitation(binary()) ::
          {:ok, Cadence.Accounts.OrganizationInvitation.t()} | {:error, term()}
  def fetch_organization_invitation(invitation_token) when is_binary(invitation_token) do
    Accounts.fetch_organization_invitation(invitation_token)
  end

  @spec accept_organization_invitation(binary(), map()) :: {:ok, map()} | {:error, term()}
  def accept_organization_invitation(invitation_token, attrs)
      when is_binary(invitation_token) and is_map(attrs) do
    Accounts.accept_organization_invitation(invitation_token, attrs)
  end

  defp browser_organization_context(user, organization_id, true)
       when is_binary(organization_id) do
    case Organizations.fetch_organization(organization_id) do
      {:ok, organization} ->
        organization_membership =
          case Accounts.fetch_user_membership(user.user_id, organization_id) do
            {:ok, %OrganizationMembership{} = membership} -> membership
            {:error, :not_found} -> nil
          end

        {:ok, organization_membership, organization}

      {:error, :organization_not_found} ->
        default_browser_organization_context(user)
    end
  end

  defp browser_organization_context(user, organization_id, _admin_mode?) do
    with {:ok, organization_membership} <-
           Accounts.preferred_organization_membership(user.user_id, organization_id),
         {:ok, organization} <- fetch_scope_organization(organization_membership) do
      {:ok, organization_membership, organization}
    end
  end

  defp default_browser_organization_context(user) do
    browser_organization_context(user, nil, false)
  end

  defp fetch_scope_organization(nil), do: {:ok, nil}

  defp fetch_scope_organization(%OrganizationMembership{} = organization_membership) do
    Organizations.fetch_organization(organization_membership.organization_id)
  end

  defp persist_service_identity(%ServiceIdentity{} = service_identity, api_token) do
    case Repo.transaction(fn ->
           insert_service_identity_or_rollback(service_identity, api_token)
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_service_identity_or_rollback(%ServiceIdentity{} = service_identity, api_token) do
    case insert_service_identity(Repo, service_identity, api_token) do
      {:ok, persisted_service_identity} ->
        %{service_identity: persisted_service_identity, api_token: api_token}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  @spec fetch_service_identity(binary(), binary()) ::
          {:ok, ServiceIdentity.t()} | {:error, term()}
  def fetch_service_identity(organization_id, service_identity_id)
      when is_binary(organization_id) and is_binary(service_identity_id) do
    service_identity_row =
      ServiceIdentityRow
      |> where(
        [service_identity_row],
        service_identity_row.organization_id == ^organization_id and
          service_identity_row.service_identity_id == ^service_identity_id
      )
      |> Repo.one()

    case service_identity_row do
      %ServiceIdentityRow{} = row -> {:ok, ServiceIdentityRow.to_domain(row)}
      nil -> {:error, :service_identity_not_found}
    end
  end

  @spec list_service_identities(binary(), keyword()) :: [ServiceIdentity.t()]
  def list_service_identities(organization_id, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    mission_id = Keyword.get(opts, :mission_id)

    ServiceIdentityRow
    |> where([service_identity_row], service_identity_row.organization_id == ^organization_id)
    |> maybe_where_mission_id(mission_id)
    |> order_by([service_identity_row], asc: service_identity_row.display_name)
    |> Repo.all()
    |> Enum.map(&ServiceIdentityRow.to_domain/1)
  end

  defp validate_service_identity_scope(%ServiceIdentity{} = service_identity) do
    with {:ok, _organization} <-
           Organizations.fetch_organization(service_identity.organization_id),
         {:ok, _mission_or_nil} <- validate_service_identity_mission(service_identity) do
      :ok
    end
  end

  defp validate_service_identity_mission(%ServiceIdentity{mission_id: nil}), do: {:ok, nil}

  defp validate_service_identity_mission(%ServiceIdentity{} = service_identity) do
    Missions.fetch_mission(service_identity.organization_id, service_identity.mission_id)
  end

  defp insert_service_identity(repo, %ServiceIdentity{} = service_identity, api_token) do
    with :ok <- validate_service_identity_scope(service_identity) do
      case repo.insert(ServiceIdentityRow.changeset(service_identity, api_token),
             on_conflict: :nothing,
             conflict_target: [:service_identity_id]
           ) do
        {:ok, %ServiceIdentityRow{} = row} ->
          {:ok, ServiceIdentityRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  defp fetch_scope_mission(%ServiceIdentityRow{mission_id: nil}), do: {:ok, nil}

  defp fetch_scope_mission(%ServiceIdentityRow{} = row) do
    Missions.fetch_mission(row.organization_id, row.mission_id)
  end

  defp maybe_where_mission_id(query, nil), do: query

  defp maybe_where_mission_id(query, mission_id) when is_binary(mission_id) do
    where(query, [service_identity_row], service_identity_row.mission_id == ^mission_id)
  end

  defp generate_api_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp digest_api_token(api_token) when is_binary(api_token) do
    :sha256
    |> :crypto.hash(api_token)
    |> Base.encode16(case: :lower)
  end
end
