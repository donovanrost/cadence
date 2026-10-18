defmodule CadenceWeb.ApplicationSurfaces.DocumentState do
  @moduledoc "Loads a declarative surface document into bounded LiveView state."

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [stream: 4]

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Reads.ApplicationSurfaces
  alias CadenceWeb.ApplicationSurfaces.Declarative

  @doc "Builds the canonical web form used by both LiveView and the JSON bridge."
  @spec form(map()) :: Phoenix.HTML.Form.t() | nil
  def form(document), do: surface_form(document)

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
      rows = Declarative.table_row_dtos(document)
      activity_items = Declarative.activity_item_dtos(document)
      packet_groups = Declarative.packet_group_dtos(document)

      {:ok,
       socket
       |> assign(:application_surface_document, document)
       |> assign(:application_surface_form, surface_form(document))
       |> assign(:application_surface_query_params, params)
       |> stream(:application_surface_rows, bounded_collection(rows), reset: true)
       |> stream(:application_surface_activity, bounded_collection(activity_items), reset: true)
       |> stream(
         :application_surface_packet_groups,
         bounded_collection(packet_groups),
         reset: true
       )}
    end
  end

  defp bounded_collection(value) when is_list(value) do
    case JSONBoundary.validate(value) do
      :ok -> value
      {:error, _reason} -> []
    end
  end

  defp bounded_collection(_value), do: []

  defp surface_form(%{form: form}) when not is_nil(form), do: generated_form(form)

  defp surface_form(%{packet_bindings: nil}), do: nil

  defp surface_form(%{packet_bindings: packet_bindings}) do
    selected_packet_ids =
      packet_bindings.packet_groups
      |> Enum.filter(& &1.selected)
      |> Enum.map(& &1.packet_id)

    to_form(
      %{
        "input_id" => packet_bindings.input_definition.input_id,
        "input_version" => Integer.to_string(packet_bindings.input_definition.version),
        "catalog_revision_id" => packet_bindings.catalog_revision_id || "",
        "source_endpoint_ref" => packet_bindings.source_endpoint_ref || "",
        "expected_configuration_version" => version_value(packet_bindings.configured_version),
        "selected_packet_ids" => selected_packet_ids
      },
      as: :application_action
    )
  end

  defp generated_form(form_definition) do
    params =
      Map.new(form_definition.fields, fn field ->
        {Atom.to_string(field.field), field.default}
      end)

    to_form(params, as: :application_action)
  end

  defp version_value(nil), do: ""
  defp version_value(version), do: Integer.to_string(version)
end
