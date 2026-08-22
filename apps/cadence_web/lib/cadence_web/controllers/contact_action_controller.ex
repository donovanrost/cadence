defmodule CadenceWeb.ContactActionController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.ContactJSON, as: ContactJSON

  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      contact_actions =
        Cadence.Contacts.list_contact_actions(
          organization_id,
          mission_id,
          scheduled_contact_id: string_param(params, "scheduled_contact_id"),
          realized_contact_id: string_param(params, "realized_contact_id")
        )
        |> Enum.map(&ContactJSON.contact_action/1)

      json(conn, %{data: contact_actions})
    end
  end

  defp string_param(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end
end
