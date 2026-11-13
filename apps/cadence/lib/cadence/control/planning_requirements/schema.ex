defmodule Cadence.Control.PlanningRequirements.Schema do
  @moduledoc """
  The one-off contact requirement form (console, BACKLOG §8 8g), in the template schema's field
  shape (`path, label, type, unit, enum, range, default, required, help, visible_when, group,
  advanced`). It reuses `TemplateSchema`'s `requirement.*` fields without the prefix, and adds
  what a template's schedule supplies per occurrence: the spacecraft and the window. Plus
  `max_gap_seconds` (DECISIONS #74) until the template schema carries it.
  """

  alias Cadence.ContactPlanning.TemplateSchema

  @prefix "requirement."
  @day 86_400
  # ContactRequirementVersion's accepted range (DECISIONS #74); the domain validates on save.
  @max_gap_range %{min: 600, max: 7 * @day}

  @doc "Every field the wire `content` accepts, in form order."
  @spec fields() :: [map()]
  def fields do
    requirement = requirement_fields()

    window() ++
      requirement ++
      if(Enum.any?(requirement, &(&1.path == "max_gap_seconds")), do: [], else: [max_gap()])
  end

  @doc "The content the server fills in for omitted fields on create."
  @spec defaults() :: map()
  def defaults do
    Enum.reduce(fields(), %{}, fn field, acc -> put_path(acc, field.path, field.default) end)
  end

  @doc "Top-level content keys (`provider_constraints_document.allowed` → its document)."
  @spec content_keys() :: [binary()]
  def content_keys do
    fields() |> Enum.map(&(&1.path |> String.split(".") |> hd())) |> Enum.uniq()
  end

  defp requirement_fields do
    for %{path: @prefix <> path} = field <- TemplateSchema.fields() do
      %{field | path: path, group: "requirement", visible_when: unprefixed(field.visible_when)}
    end
  end

  defp unprefixed(%{path: @prefix <> path} = condition), do: %{condition | path: path}
  defp unprefixed(condition), do: condition

  defp window do
    [
      field("spacecraft_id", "Spacecraft", :reference, required: true),
      field("earliest_start", "Window opens", :datetime,
        required: true,
        help: "The contact may start no earlier than this."
      ),
      field("latest_end", "Window closes", :datetime,
        required: true,
        help: "The contact must end by this; after the window opens."
      )
    ]
  end

  # Domain's wording (#74); TemplateSchema will carry the same field in a follow-up.
  defp max_gap do
    field("max_gap_seconds", "Longest time without a contact", :integer,
      unit: "s",
      range: @max_gap_range,
      advanced: true,
      help:
        "Longest stretch from one contact's end to the next contact's start, counting the " <>
          "window's start and end. Empty means no limit."
    )
  end

  defp field(path, label, type, opts) do
    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: nil,
      range: Keyword.get(opts, :range),
      default: nil,
      required: Keyword.get(opts, :required, false),
      help: Keyword.get(opts, :help),
      visible_when: nil,
      group: if(path == "max_gap_seconds", do: "requirement", else: "window"),
      advanced: Keyword.get(opts, :advanced, false)
    }
  end

  defp put_path(map, path, value) do
    case String.split(path, ".") do
      [key] -> Map.put(map, key, value)
      [key, sub] -> Map.update(map, key, %{sub => value}, &Map.put(&1, sub, value))
    end
  end
end
