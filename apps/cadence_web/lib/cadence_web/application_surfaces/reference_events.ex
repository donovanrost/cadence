defmodule CadenceWeb.ApplicationSurfaces.ReferenceEvents do
  @moduledoc "LiveView event adapter for host-rendered searchable references."

  import Phoenix.Component, only: [assign: 3, to_form: 2]

  alias Cadence.Reads.ApplicationReferences
  alias CadenceWeb.ApplicationSurfaces.ReferenceForm

  @spec change(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def change(params, socket) when is_map(params) do
    action_params =
      case Map.get(params, "application_action", %{}) do
        action_params when is_map(action_params) -> action_params
        _invalid -> %{}
      end

    socket =
      socket
      |> assign(:application_surface_form, to_form(action_params, as: :application_action))
      |> assign(:application_action_feedback, nil)

    case ReferenceForm.search_field_name(
           socket.assigns.application_surface_document,
           Map.get(params, "_target")
         ) do
      {:ok, field_name} ->
        query =
          case Map.get(action_params, field_name, "") do
            query when is_binary(query) -> query
            _invalid -> ""
          end

        search(socket, field_name, query)

      :none ->
        {:noreply, socket}
    end
  end

  defp search(socket, field_name, query) do
    case ApplicationReferences.search(
           socket.assigns.current_scope,
           socket.assigns.application_host_context,
           socket.assigns.application_definition.application_key,
           socket.assigns.application_definition.version,
           socket.assigns.application_surface_definition,
           field_name,
           query
         ) do
      {:ok, page} ->
        document =
          ReferenceForm.put_page(
            socket.assigns.application_surface_document,
            field_name,
            page
          )

        {:noreply, assign(socket, :application_surface_document, document)}

      {:error, _reason} ->
        {:noreply,
         assign(socket, :application_action_feedback, %{
           kind: :error,
           code: "reference_lookup_failed",
           message: "Mission references could not be refreshed. Try again."
         })}
    end
  end
end
