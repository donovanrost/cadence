defmodule CadenceWeb.SpacecraftAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(
        :load_spacecraft,
        %{"mission_id" => mission_id, "spacecraft_id" => spacecraft_id},
        _session,
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      {:ok, spacecraft} ->
        {:cont, assign(socket, :current_spacecraft, spacecraft)}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "Spacecraft not found.")
         |> redirect(to: "/missions/#{mission_id}/spacecraft")}
    end
  end
end
