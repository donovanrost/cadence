defmodule CadenceWeb.ProviderProfileController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Contacts.ProviderProfile
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      provider_profiles =
        Cadence.list_provider_profiles(organization_id, mission_id)
        |> Enum.map(&ControlPlaneJSON.provider_profile/1)

      json(conn, %{data: provider_profiles})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "provider_profile" => provider_profile_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ProviderProfile{} = provider_profile} <-
           ControlPlaneParams.provider_profile(
             organization_id,
             mission_id,
             provider_profile_params
           ),
         {:ok, %ProviderProfile{} = persisted_provider_profile} <-
           Cadence.persist_provider_profile(organization_id, provider_profile) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.provider_profile(persisted_provider_profile)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "provider_profile_id" => provider_profile_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ProviderProfile{} = provider_profile} <-
           Cadence.fetch_provider_profile(organization_id, mission_id, provider_profile_id) do
      json(conn, %{data: ControlPlaneJSON.provider_profile(provider_profile)})
    end
  end

  def versions(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "provider_profile_id" => provider_profile_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      provider_profiles =
        Cadence.list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
        |> Enum.map(&ControlPlaneJSON.provider_profile/1)

      json(conn, %{data: provider_profiles})
    end
  end

  def show_version(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "provider_profile_id" => provider_profile_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, version} <- ControlPlaneParams.resource_version(params),
         {:ok, %ProviderProfile{} = provider_profile} <-
           Cadence.fetch_provider_profile_version(
             organization_id,
             mission_id,
             provider_profile_id,
             version
           ) do
      json(conn, %{data: ControlPlaneJSON.provider_profile(provider_profile)})
    end
  end

  def update(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "provider_profile_id" => provider_profile_id
        } = params
      ) do
    provider_profile_params = Map.get(params, "provider_profile", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.provider_profile_patch(provider_profile_params),
         {:ok, %ProviderProfile{} = provider_profile} <-
           Cadence.version_provider_profile(
             organization_id,
             mission_id,
             provider_profile_id,
             attrs
           ) do
      json(conn, %{data: ControlPlaneJSON.provider_profile(provider_profile)})
    end
  end

  def delete(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "provider_profile_id" => provider_profile_id
        } = params
      ) do
    provider_profile_params = Map.get(params, "provider_profile", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.provider_profile_patch(provider_profile_params),
         {:ok, %ProviderProfile{} = provider_profile} <-
           Cadence.delete_provider_profile(
             organization_id,
             mission_id,
             provider_profile_id,
             Map.get(attrs, :metadata, %{})
           ) do
      json(conn, %{data: ControlPlaneJSON.provider_profile(provider_profile)})
    end
  end
end
