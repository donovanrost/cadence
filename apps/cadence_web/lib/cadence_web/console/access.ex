defmodule CadenceWeb.Console.Access do
  @moduledoc """
  Authentication and mission authorization for the Apogee console SPA.

  The console is URL-addressed by mission, so a request's organization is
  derived from the mission rather than from the session's current
  organization. That keeps two tabs on missions in different organizations
  working without one silently switching the other. Every mission read still
  goes through `Cadence.Auth.Policy` (`:operate_mission`), and a mission the
  actor cannot operate is reported as not found so its existence is not leaked.
  """

  alias Cadence.Auth.Policy
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission

  @typedoc """
  A person's browser session (cookie plus CSRF), or a service identity's bearer token (#753). A
  person never authenticates with a bearer token: every four-eyes decision is a person's.
  """
  @type credentials ::
          %{
            required(:session_token) => binary(),
            required(:admin_mode?) => boolean(),
            optional(:current_organization_id) => binary() | nil
          }
          | %{
              required(:service_scope) => Scope.t(),
              required(:current_organization_id) => binary() | nil
            }

  @doc "Reads console credentials from a browser session map (string or atom keys)."
  @spec credentials_from_session(map() | nil) :: {:ok, credentials()} | {:error, :unauthenticated}
  def credentials_from_session(session) when is_map(session) do
    case session_value(session, :user_session_token) do
      token when is_binary(token) and token != "" ->
        {:ok,
         %{
           session_token: token,
           current_organization_id: session_value(session, :current_organization_id),
           admin_mode?:
             CadenceWeb.AdminMode.active?(session_value(session, :admin_mode_expires_at))
         }}

      _other ->
        {:error, :unauthenticated}
    end
  end

  def credentials_from_session(_session), do: {:error, :unauthenticated}

  @doc """
  Reads console credentials from a bearer token. The token must belong to an active service
  identity; anything else is `:unauthenticated`.
  """
  @spec credentials_from_bearer(binary()) :: {:ok, credentials()} | {:error, :unauthenticated}
  def credentials_from_bearer(token) when is_binary(token) and token != "" do
    case Cadence.Auth.authenticate_api_token(token) do
      {:ok, %Scope{actor_kind: :service} = scope} ->
        {:ok, %{service_scope: scope, current_organization_id: scope.organization_id}}

      _other ->
        {:error, :unauthenticated}
    end
  end

  def credentials_from_bearer(_token), do: {:error, :unauthenticated}

  @doc "Authenticates credentials into the session's default scope."
  @spec authenticate(credentials()) :: {:ok, Scope.t()} | {:error, :unauthenticated}
  # A service identity's scope is fixed by its token: its own organization (and mission). Asking for
  # another organization doesn't re-scope it; the caller's Policy check refuses that organization.
  def authenticate(%{service_scope: %Scope{} = scope}), do: {:ok, scope}

  def authenticate(%{session_token: token, admin_mode?: admin_mode?} = credentials) do
    case Cadence.Auth.authenticate_browser_session(token,
           current_organization_id: Map.get(credentials, :current_organization_id),
           admin_mode?: admin_mode?
         ) do
      {:ok, %Scope{} = scope} -> {:ok, scope}
      {:error, _reason} -> {:error, :unauthenticated}
    end
  end

  @doc """
  Resolves a scope bound to the mission's organization and authorizes the actor
  to operate the mission.
  """
  @spec authorize_mission(credentials(), binary()) ::
          {:ok, Scope.t(), Mission.t()} | {:error, :unauthenticated | :mission_not_found}
  def authorize_mission(%{session_token: token, admin_mode?: admin_mode?}, mission_id)
      when is_binary(mission_id) do
    with organization_id when is_binary(organization_id) <-
           Cadence.Missions.organization_id_for_mission(mission_id),
         {:ok, scope} <-
           authenticate(%{
             session_token: token,
             admin_mode?: admin_mode?,
             current_organization_id: organization_id
           }),
         :ok <- authorize_operate(scope, organization_id, mission_id),
         {:ok, %Mission{} = mission} <-
           Cadence.Missions.fetch_mission(organization_id, mission_id) do
      {:ok, scope, mission}
    else
      {:error, :unauthenticated} -> {:error, :unauthenticated}
      _other -> {:error, :mission_not_found}
    end
  end

  # A service identity: the mission must be in its organization, and Policy's :operate_mission
  # pins a mission-scoped service to its own mission.
  def authorize_mission(%{service_scope: %Scope{} = scope}, mission_id)
      when is_binary(mission_id) do
    with organization_id when is_binary(organization_id) <-
           Cadence.Missions.organization_id_for_mission(mission_id),
         true <- organization_id == scope.organization_id,
         :ok <- authorize_operate(scope, organization_id, mission_id),
         {:ok, %Mission{} = mission} <-
           Cadence.Missions.fetch_mission(organization_id, mission_id) do
      {:ok, scope, mission}
    else
      _other -> {:error, :mission_not_found}
    end
  end

  def authorize_mission(_credentials, _mission_id), do: {:error, :mission_not_found}

  # todo(authz): a platform admin in admin mode operates ANY mission by id here without being a
  # member (Policy :operate_mission lets admin mode through; #90's platform binding sheet relies on
  # it, lead 11-14). Cedar should decide which mission routes admin mode may reach.
  defp authorize_operate(scope, organization_id, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  defp session_value(session, key) do
    Map.get(session, Atom.to_string(key)) || Map.get(session, key)
  end
end
