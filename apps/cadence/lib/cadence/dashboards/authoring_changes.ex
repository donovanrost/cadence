defmodule Cadence.Dashboards.AuthoringChanges do
  @moduledoc "Pure document transformations for already admitted authoring commands; no persistence."
  alias Cadence.Dashboards.{AuthoringDefaults, AuthoringWidget, Document, Section}

  def apply(document, "rename", fields),
    do:
      {:ok,
       %{
         document
         | name: String.trim(fields["name"]),
           description: String.trim(fields["description"])
       }, %{}}

  def apply(document, "add_section", fields) do
    if length(document.sections) < 64 do
      section = section(Cadence.Ids.new("dash_section"), fields)
      {:ok, Document.put_section(document, section), %{section_id: section.section_id}}
    else
      {:error, :capacity}
    end
  end

  def apply(document, "update_section", fields) do
    with :ok <- section_exists(document, fields["section_id"]) do
      {:ok, Document.put_section(document, section(fields["section_id"], fields)),
       %{section_id: fields["section_id"]}}
    end
  end

  def apply(document, "remove_section", fields) do
    with :ok <- section_exists(document, fields["section_id"]) do
      {:ok, Document.remove_section(document, fields["section_id"]),
       %{section_id: fields["section_id"]}}
    end
  end

  def apply(document, "move_section", fields) do
    with :ok <- section_exists(document, fields["section_id"]) do
      direction = if fields["direction"] == "up", do: :up, else: :down

      {:ok, Document.move_section(document, fields["section_id"], direction),
       %{section_id: fields["section_id"]}}
    end
  end

  def apply(document, "add_widget", fields) do
    if length(document.placements) < 1024 do
      put_widget(document, fields, nil)
    else
      {:error, :capacity}
    end
  end

  def apply(document, "update_widget", fields) do
    with {:ok, existing} <- placement(document, fields["placement_id"]) do
      put_widget(document, fields, existing)
    end
  end

  def apply(document, "remove_widget", fields) do
    with {:ok, _} <- placement(document, fields["placement_id"]) do
      {:ok, Document.remove_placement(document, fields["placement_id"]),
       %{placement_id: fields["placement_id"]}}
    end
  end

  def apply(document, "layout", %{"layouts" => layouts}) do
    ids = Enum.map(document.placements, & &1.placement_id) |> MapSet.new()

    if Enum.all?(layouts, &MapSet.member?(ids, &1["placement_id"])) do
      {:ok, Document.apply_layouts(document, layouts), %{}}
    else
      {:error, :missing_placement}
    end
  end

  def apply(document, "runtime_defaults", %{"defaults_json" => json}) do
    with {:ok, defaults} <- AuthoringDefaults.decode(json),
         :ok <- AuthoringDefaults.validate(defaults) do
      {:ok, %{document | defaults: defaults}, %{}}
    end
  end

  defp put_widget(document, input, existing) do
    with :ok <- optional_section(document, input["fields"]["section_id"]),
         {:ok, widget} <-
           AuthoringWidget.build(document, input["fields"], input["observables"], existing) do
      {:ok, Document.put_placement(document, widget), %{placement_id: widget.placement_id}}
    end
  end

  defp section(id, fields),
    do: %Section{
      section_id: id,
      title: String.trim(fields["title"]),
      description: String.trim(fields["description"]),
      collapsed_by_default?: fields["collapsed_by_default"]
    }

  defp optional_section(_document, ""), do: :ok
  defp optional_section(document, id), do: section_exists(document, id)

  defp section_exists(document, id) do
    if Enum.any?(document.sections, &(&1.section_id == id)),
      do: :ok,
      else: {:error, :missing_section}
  end

  defp placement(document, id) do
    case Enum.find(document.placements, &(&1.placement_id == id)) do
      nil -> {:error, :missing_placement}
      placement -> {:ok, placement}
    end
  end
end
