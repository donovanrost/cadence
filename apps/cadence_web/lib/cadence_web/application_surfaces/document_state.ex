defmodule CadenceWeb.ApplicationSurfaces.DocumentState do
  @moduledoc "Loads a declarative surface document into bounded LiveView state."

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4]

  alias Cadence.Reads.ApplicationSurfaces

  @spec load(Phoenix.LiveView.Socket.t(), map() | nil) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, term()}
  def load(socket, params \\ nil) do
    params = params || socket.assigns.application_surface_query_params

    with {:ok, document} <-
           ApplicationSurfaces.load(
             socket.assigns.current_scope,
             socket.assigns.application_host_context,
             socket.assigns.application_definition.application_key,
             socket.assigns.application_definition.version,
             socket.assigns.application_surface_definition,
             params
           ) do
      rows = (document.table && document.table.page.items) || []
      activity_items = (document.activity && document.activity.items) || []

      {:ok,
       socket
       |> assign(:application_surface_document, document)
       |> assign(:application_surface_form, surface_form(document.form))
       |> assign(:application_surface_query_params, params)
       |> stream(:application_surface_rows, rows, reset: true)
       |> stream(:application_surface_activity, activity_items, reset: true)}
    end
  end

  defp surface_form(nil), do: nil

  defp surface_form(form_definition) do
    params =
      Map.new(form_definition.fields, fn field ->
        {Atom.to_string(field.field), field.default}
      end)

    to_form(params, as: :application_action)
  end
end
