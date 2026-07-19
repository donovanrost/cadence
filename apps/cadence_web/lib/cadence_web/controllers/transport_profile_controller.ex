defmodule CadenceWeb.TransportProfileController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Contacts.TransportProfile
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      transport_profiles =
        Cadence.Contacts.list_transport_profiles(organization_id, mission_id)
        |> Enum.map(&ControlPlaneJSON.transport_profile/1)

      json(conn, %{data: transport_profiles})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "transport_profile" => transport_profile_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %TransportProfile{} = transport_profile} <-
           ControlPlaneParams.transport_profile(
             organization_id,
             mission_id,
             transport_profile_params
           ),
         {:ok, %TransportProfile{} = persisted_transport_profile} <-
           Cadence.Contacts.persist_transport_profile(organization_id, transport_profile) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.transport_profile(persisted_transport_profile)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "transport_profile_id" => transport_profile_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %TransportProfile{} = transport_profile} <-
           Cadence.Contacts.fetch_transport_profile(
             organization_id,
             mission_id,
             transport_profile_id
           ) do
      json(conn, %{data: ControlPlaneJSON.transport_profile(transport_profile)})
    end
  end

  def versions(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "transport_profile_id" => transport_profile_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      transport_profiles =
        Cadence.Contacts.list_transport_profile_versions(
          organization_id,
          mission_id,
          transport_profile_id
        )
        |> Enum.map(&ControlPlaneJSON.transport_profile/1)

      json(conn, %{data: transport_profiles})
    end
  end

  def show_version(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "transport_profile_id" => transport_profile_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, version} <- ControlPlaneParams.resource_version(params),
         {:ok, %TransportProfile{} = transport_profile} <-
           Cadence.Contacts.fetch_transport_profile_version(
             organization_id,
             mission_id,
             transport_profile_id,
             version
           ) do
      json(conn, %{data: ControlPlaneJSON.transport_profile(transport_profile)})
    end
  end

  def update(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "transport_profile_id" => transport_profile_id
        } = params
      ) do
    transport_profile_params = Map.get(params, "transport_profile", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.transport_profile_patch(transport_profile_params),
         {:ok, %TransportProfile{} = transport_profile} <-
           Cadence.Contacts.version_transport_profile(
             organization_id,
             mission_id,
             transport_profile_id,
             attrs
           ) do
      json(conn, %{data: ControlPlaneJSON.transport_profile(transport_profile)})
    end
  end

  def delete(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "transport_profile_id" => transport_profile_id
        } = params
      ) do
    transport_profile_params = Map.get(params, "transport_profile", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.transport_profile_patch(transport_profile_params),
         {:ok, %TransportProfile{} = transport_profile} <-
           Cadence.Contacts.delete_transport_profile(
             organization_id,
             mission_id,
             transport_profile_id,
             Map.get(attrs, :metadata, %{})
           ) do
      json(conn, %{data: ControlPlaneJSON.transport_profile(transport_profile)})
    end
  end
end
