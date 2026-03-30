defmodule CadenceWeb.RealizedContactController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Contacts.RealizedContact
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      realized_contacts =
        Cadence.list_realized_contacts(organization_id, mission_id)
        |> Enum.map(&ControlPlaneJSON.realized_contact/1)

      json(conn, %{data: realized_contacts})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "realized_contact_id" => realized_contact_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %RealizedContact{} = realized_contact} <-
           Cadence.fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
      json(conn, %{data: ControlPlaneJSON.realized_contact(realized_contact)})
    end
  end

  def runtime(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "realized_contact_id" => realized_contact_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, runtime_snapshot} <-
           Cadence.realized_contact_snapshot(
             organization_id,
             mission_id,
             realized_contact_id
           ) do
      json(conn, %{data: ControlPlaneJSON.realized_contact_runtime_snapshot(runtime_snapshot)})
    end
  end

  def path_runtime(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "realized_contact_id" => realized_contact_id,
        "path_id" => path_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, runtime_snapshot} <-
           Cadence.path_runtime_snapshot(
             organization_id,
             mission_id,
             realized_contact_id,
             path_id
           ) do
      json(conn, %{data: ControlPlaneJSON.path_runtime_snapshot(runtime_snapshot)})
    end
  end

  def end_early(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "realized_contact_id" => realized_contact_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, termination_opts} <-
           ControlPlaneParams.contact_action(Map.get(params, "termination", %{})),
         {:ok, realized_contact} <-
           Cadence.end_realized_contact_early(
             organization_id,
             mission_id,
             realized_contact_id,
             termination_opts
           ) do
      json(conn, %{data: ControlPlaneJSON.realized_contact(realized_contact)})
    end
  end
end
