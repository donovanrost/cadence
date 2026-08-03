defmodule CadenceWeb.OpsDashboardShowLive.DashboardSectionEditing do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]

  alias Cadence.Dashboards.{Document, Section}
  alias Cadence.Ids

  def form_defaults do
    %{
      "section_id" => "",
      "title" => "",
      "description" => "",
      "collapsed_by_default" => "false"
    }
  end

  def open(socket) do
    socket
    |> assign(:panel, :dashboard_sections)
    |> assign(:section_error, nil)
    |> assign(:section_form, to_form(form_defaults(), as: :section))
  end

  def edit(socket, section_id) do
    case Enum.find(socket.assigns.dashboard_document.sections, &(&1.section_id == section_id)) do
      %Section{} = section ->
        params = %{
          "section_id" => section.section_id,
          "title" => section.title,
          "description" => section.description || "",
          "collapsed_by_default" => to_string(section.collapsed_by_default?)
        }

        socket
        |> assign(:section_error, nil)
        |> assign(:section_form, to_form(params, as: :section))

      nil ->
        socket
    end
  end

  def validate(socket, params) when is_map(params) do
    assign(socket, :section_form, to_form(params, as: :section))
  end

  def save(socket, params, opts) when is_map(params) do
    with {:ok, section} <- build_section(params),
         document <- Document.put_section(socket.assigns.dashboard_document, section),
         {:ok, socket} <- persist(opts, socket, document, "Updated dashboard sections") do
      socket
      |> assign(:section_error, nil)
      |> assign(:section_form, to_form(form_defaults(), as: :section))
    else
      {:error, message} when is_binary(message) -> assign(socket, :section_error, message)
      {:error, socket} -> socket
    end
  end

  def remove(socket, section_id, opts) do
    document = Document.remove_section(socket.assigns.dashboard_document, section_id)

    case persist(opts, socket, document, "Removed dashboard section") do
      {:ok, socket} -> socket
      {:error, socket} -> socket
    end
  end

  def move(socket, section_id, direction, opts) when direction in [:up, :down] do
    document = Document.move_section(socket.assigns.dashboard_document, section_id, direction)

    case persist(opts, socket, document, "Reordered dashboard sections") do
      {:ok, socket} -> socket
      {:error, socket} -> socket
    end
  end

  defp build_section(params) do
    title = params |> Map.get("title", "") |> String.trim()
    description = params |> Map.get("description", "") |> String.trim()

    cond do
      String.length(title) not in 1..80 ->
        {:error, "Section title must be 1 to 80 characters."}

      String.length(description) > 240 ->
        {:error, "Section description must be 240 characters or fewer."}

      true ->
        {:ok,
         %Section{
           section_id: present_id(params["section_id"]) || Ids.new("dash_section"),
           title: title,
           description: if(description == "", do: nil, else: description),
           collapsed_by_default?: truthy?(params["collapsed_by_default"])
         }}
    end
  end

  defp persist(opts, socket, document, change_summary) do
    opts
    |> Keyword.fetch!(:persist_document)
    |> then(& &1.(socket, document, change_summary: change_summary))
  end

  defp present_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      id -> id
    end
  end

  defp present_id(_value), do: nil

  defp truthy?(value), do: value in [true, "true", "1", "on"]
end
