defmodule CadenceWeb.MissionAuth do
  @moduledoc false

  import Phoenix.Component

  def on_mount(:load_mission, %{"mission_id" => mission_id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.fetch_mission(organization_id, mission_id) do
      {:ok, mission} ->
        {:cont,
         socket
         |> assign(:current_mission, mission)
         |> assign(:nav_context, :mission)}

      {:error, _reason} ->
        raise Phoenix.Router.NoRouteError,
          conn: %Plug.Conn{},
          router: CadenceWeb.Router
    end
  end
end
