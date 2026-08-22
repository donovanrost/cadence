defmodule CadenceWeb.ScheduledContactController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.ContactJSON, as: ContactJSON

  alias CadenceWeb.API.ContactParams, as: ContactParams

  alias Cadence.Contacts.ScheduledContact
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      scheduled_contacts =
        Cadence.Contacts.list_scheduled_contacts(organization_id, mission_id)
        |> Enum.map(&ContactJSON.scheduled_contact/1)

      json(conn, %{data: scheduled_contacts})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "scheduled_contact" => scheduled_contact_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ScheduledContact{} = scheduled_contact} <-
           ContactParams.scheduled_contact(
             organization_id,
             mission_id,
             scheduled_contact_params
           ),
         {:ok, %ScheduledContact{} = persisted_scheduled_contact} <-
           Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact) do
      conn
      |> put_status(:created)
      |> json(%{data: ContactJSON.scheduled_contact(persisted_scheduled_contact)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "scheduled_contact_id" => scheduled_contact_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ScheduledContact{} = scheduled_contact} <-
           Cadence.Contacts.fetch_scheduled_contact(
             organization_id,
             mission_id,
             scheduled_contact_id
           ) do
      json(conn, %{data: ContactJSON.scheduled_contact(scheduled_contact)})
    end
  end

  def realize(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "scheduled_contact_id" => scheduled_contact_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, realization_opts} <-
           ContactParams.realization(Map.get(params, "realization", %{})),
         {:ok, realized_contact} <-
           Cadence.Contacts.realize_scheduled_contact(
             organization_id,
             mission_id,
             scheduled_contact_id,
             realization_opts
           ) do
      json(conn, %{data: ContactJSON.realized_contact(realized_contact)})
    end
  end

  def cancel(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "scheduled_contact_id" => scheduled_contact_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, cancellation_opts} <-
           ContactParams.contact_action(Map.get(params, "cancellation", %{})),
         {:ok, scheduled_contact} <-
           Cadence.Contacts.cancel_scheduled_contact(
             organization_id,
             mission_id,
             scheduled_contact_id,
             cancellation_opts
           ) do
      json(conn, %{data: ContactJSON.scheduled_contact(scheduled_contact)})
    end
  end
end
