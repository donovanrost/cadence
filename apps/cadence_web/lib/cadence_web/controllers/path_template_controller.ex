defmodule CadenceWeb.PathTemplateController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Contacts.PathTemplate
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      path_templates =
        Cadence.Contacts.list_path_templates(organization_id, mission_id)
        |> Enum.map(&ControlPlaneJSON.path_template/1)

      json(conn, %{data: path_templates})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "path_template" => path_template_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %PathTemplate{} = path_template} <-
           ControlPlaneParams.path_template(
             organization_id,
             mission_id,
             path_template_params
           ),
         {:ok, %PathTemplate{} = persisted_path_template} <-
           Cadence.Contacts.persist_path_template(organization_id, path_template) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.path_template(persisted_path_template)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "path_template_id" => path_template_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %PathTemplate{} = path_template} <-
           Cadence.Contacts.fetch_path_template(organization_id, mission_id, path_template_id) do
      json(conn, %{data: ControlPlaneJSON.path_template(path_template)})
    end
  end

  def versions(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "path_template_id" => path_template_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      path_templates =
        Cadence.Contacts.list_path_template_versions(
          organization_id,
          mission_id,
          path_template_id
        )
        |> Enum.map(&ControlPlaneJSON.path_template/1)

      json(conn, %{data: path_templates})
    end
  end

  def show_version(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "path_template_id" => path_template_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, version} <- ControlPlaneParams.resource_version(params),
         {:ok, %PathTemplate{} = path_template} <-
           Cadence.Contacts.fetch_path_template_version(
             organization_id,
             mission_id,
             path_template_id,
             version
           ) do
      json(conn, %{data: ControlPlaneJSON.path_template(path_template)})
    end
  end

  def update(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "path_template_id" => path_template_id
        } = params
      ) do
    path_template_params = Map.get(params, "path_template", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.path_template_patch(path_template_params),
         {:ok, %PathTemplate{} = path_template} <-
           Cadence.Contacts.version_path_template(
             organization_id,
             mission_id,
             path_template_id,
             attrs
           ) do
      json(conn, %{data: ControlPlaneJSON.path_template(path_template)})
    end
  end

  def delete(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "path_template_id" => path_template_id
        } = params
      ) do
    path_template_params = Map.get(params, "path_template", %{})

    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, attrs} <- ControlPlaneParams.path_template_patch(path_template_params),
         {:ok, %PathTemplate{} = path_template} <-
           Cadence.Contacts.delete_path_template(
             organization_id,
             mission_id,
             path_template_id,
             Map.get(attrs, :metadata, %{})
           ) do
      json(conn, %{data: ControlPlaneJSON.path_template(path_template)})
    end
  end
end
