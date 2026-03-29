defmodule Cadence.Auth do
  @moduledoc """
  Service-identity authentication and bootstrap helpers for the control-plane
  API.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Cadence.Accounts
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Missions
  alias Cadence.Missions.Mission
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.ServiceIdentityRow
  alias Cadence.Repo

  @type issued_service_identity :: %{
          service_identity: ServiceIdentity.t(),
          api_token: binary()
        }

  @spec bootstrap(Organization.t(), ServiceIdentity.t(), Mission.t() | nil) ::
          {:ok,
           %{
             organization: Organization.t(),
             mission: Mission.t() | nil,
             service_identity: ServiceIdentity.t(),
             api_token: binary()
           }}
          | {:error, term()}
  def bootstrap(
        %Organization{} = organization,
        %ServiceIdentity{} = service_identity,
        mission \\ nil
      ) do
    if Organizations.count_organizations() > 0 do
      {:error, :bootstrap_already_completed}
    else
      api_token = generate_api_token()

      Multi.new()
      |> Multi.run(:organization, fn _repo, _changes ->
        Organizations.persist_organization(organization)
      end)
      |> maybe_insert_bootstrap_mission(mission)
      |> Multi.run(:service_identity, fn repo, _changes ->
        insert_service_identity(repo, service_identity, api_token)
      end)
      |> Repo.transaction()
      |> case do
        {:ok,
         %{organization: persisted_organization, service_identity: persisted_service_identity} =
             changes} ->
          {:ok,
           %{
             organization: persisted_organization,
             mission: Map.get(changes, :mission),
             service_identity: persisted_service_identity,
             api_token: api_token
           }}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec issue_service_identity(ServiceIdentity.t()) ::
          {:ok, issued_service_identity()} | {:error, term()}
  def issue_service_identity(%ServiceIdentity{} = service_identity) do
    api_token = generate_api_token()

    with :ok <- validate_service_identity_scope(service_identity) do
      case Repo.transaction(fn ->
             with {:ok, persisted_service_identity} <-
                    insert_service_identity(Repo, service_identity, api_token) do
               %{service_identity: persisted_service_identity, api_token: api_token}
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
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
        authenticate_bootstrap_admin_session_token(api_token)
    end
  end

  @spec login_bootstrap_admin(binary(), binary()) ::
          {:ok, Accounts.issued_bootstrap_admin_session()} | {:error, term()}
  def login_bootstrap_admin(email, password)
      when is_binary(email) and is_binary(password) do
    Accounts.login_bootstrap_admin(email, password)
  end

  @spec ensure_bootstrap_admin() :: {:ok, Cadence.Accounts.User.t()} | {:error, term()}
  def ensure_bootstrap_admin do
    Accounts.ensure_bootstrap_admin()
  end

  @spec bootstrap_admin_enabled?() :: boolean()
  def bootstrap_admin_enabled? do
    Accounts.bootstrap_admin_enabled?()
  end

  defp authenticate_bootstrap_admin_session_token(api_token) do
    with {:ok, user} <- Accounts.authenticate_bootstrap_admin_session(api_token) do
      {:ok,
       Scope.new(%{
         user: user,
         role: :platform_admin
       })}
    else
      {:error, reason} -> {:error, reason}
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

  defp maybe_insert_bootstrap_mission(multi, nil), do: multi

  defp maybe_insert_bootstrap_mission(multi, %Mission{} = mission) do
    Multi.run(multi, :mission, fn _repo, _changes ->
      Missions.persist_mission(mission)
    end)
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
