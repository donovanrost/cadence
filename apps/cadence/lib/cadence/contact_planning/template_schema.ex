defmodule Cadence.ContactPlanning.TemplateSchema do
  @moduledoc """
  The contact requirement template document as form fields (console CP3), in
  the same shape as `FleetPlanningPolicySchema.fields/0`: `path`, `label`,
  `type` (`integer | string | boolean | enum | datetime | time | list`),
  `unit`, `enum`, `range`, `default`, `required`, `help`, `visible_when`,
  `group`, `advanced`.

  Paths are `schedule.*`, `requirement.*` and `catch_up_policy.*`, matching
  the wire document `{schedule, requirement, catch_up_policy}`. Bounds mirror
  `RequirementSchedule`, `ContactRequirementVersion` and the template
  version's catch-up normalization; the domain still validates on save.
  """

  alias Cadence.ContactPlanning.ContactRequirementVersion

  @minute 60
  @hour 3_600
  @day 86_400
  @fixed %{path: "schedule.type", equals: "fixed_interval"}
  @daily %{path: "schedule.type", equals: "daily"}

  @spec fields() :: [map()]
  def fields, do: schedule() ++ requirement() ++ catch_up()

  @doc "The defaults document, keyed like the wire document."
  @spec defaults() :: map()
  def defaults do
    Enum.reduce(fields(), %{}, fn field, acc ->
      put_path(acc, String.split(field.path, "."), field.default)
    end)
  end

  defp put_path(map, [key], value), do: Map.put(map, key, value)

  defp put_path(map, [key | rest], value),
    do: Map.put(map, key, put_path(Map.get(map, key, %{}), rest, value))

  defp schedule do
    [
      field("schedule.type", "Repeats", :enum, "fixed_interval",
        required: true,
        enum: [
          %{value: "fixed_interval", label: "Every fixed interval"},
          %{value: "daily", label: "Daily at a UTC time"}
        ]
      ),
      field("schedule.anchor_at", "Starting from", :datetime, nil,
        required: true,
        help: "The first occurrence; later ones follow from it."
      ),
      field("schedule.ends_at", "Until", :datetime, nil, help: "Empty means no end."),
      int("schedule.interval_seconds", "Every", 6 * @hour, @minute, 31 * @day,
        unit: "s",
        required: true,
        visible_when: @fixed
      ),
      field("schedule.time_utc", "At (UTC)", :time, nil, required: true, visible_when: @daily),
      int("schedule.window_offset_seconds", "Window opens after", 0, -7 * @day, 7 * @day,
        unit: "s",
        help: "How long after each occurrence the contact window opens.",
        advanced: true
      ),
      int("schedule.window_duration_seconds", "Window length", 6 * @hour, @minute, 7 * @day,
        unit: "s",
        required: true,
        help: "How long each contact window stays open."
      )
    ]
  end

  defp requirement do
    [
      field("requirement.service_direction", "Contact", :enum, "downlink",
        required: true,
        enum: options(ContactRequirementVersion.directions())
      ),
      field("requirement.contact_intent", "Purpose", :string, "recurring_payload_downlink",
        required: true,
        help: "A short name for why the contact is needed, for example payload downlink."
      ),
      field("requirement.success_measure", "Met when", :enum, "minimum_duration",
        required: true,
        enum: options(ContactRequirementVersion.success_measures())
      ),
      int("requirement.minimum_duration_seconds", "Shortest useful contact", 5 * @minute, 1, @day,
        unit: "s",
        visible_when: %{path: "requirement.success_measure", equals: "minimum_duration"}
      ),
      int(
        "requirement.preferred_duration_seconds",
        "Preferred contact length",
        5 * @minute,
        1,
        @day,
        unit: "s",
        advanced: true
      ),
      int(
        "requirement.minimum_data_volume_bytes",
        "Least data per contact",
        nil,
        1,
        1_000_000_000_000_000,
        unit: "bytes",
        visible_when: %{path: "requirement.success_measure", equals: "minimum_data_volume"}
      ),
      int("requirement.contact_count", "Contacts per window", 1, 1, 100, required: true),
      int("requirement.minimum_separation_seconds", "Least time between contacts", 0, 0, @day,
        unit: "s",
        advanced: true
      ),
      # DECISIONS #74: carried by templates too; requirements generated from one inherit it.
      int("requirement.max_gap_seconds", "Longest time without a contact", nil, 600, 7 * @day,
        unit: "s",
        advanced: true,
        help:
          "Longest stretch from one contact's end to the next contact's start, counting the " <>
            "window's start and end. Empty means no limit."
      ),
      field("requirement.priority", "Priority", :enum, "routine",
        required: true,
        enum: options(ContactRequirementVersion.priorities())
      ),
      field("requirement.rationale", "Why", :string, nil,
        help: "Shown to reviewers and in the plan."
      ),
      list("requirement.provider_constraints_document.allowed", "Only these providers"),
      list("requirement.provider_constraints_document.excluded", "Never these providers"),
      list("requirement.station_constraints_document.allowed", "Only these stations"),
      list("requirement.station_constraints_document.excluded", "Never these stations")
    ]
  end

  defp catch_up do
    [
      int(
        "catch_up_policy.maximum_occurrences_per_run",
        "Occurrences per planning run",
        100,
        1,
        1_000,
        advanced: true,
        help: "Most occurrences one planning run generates for this template."
      ),
      int(
        "catch_up_policy.maximum_lookback_seconds",
        "Catch up on missed occurrences for",
        7 * @day,
        0,
        31 * @day,
        unit: "s",
        advanced: true
      )
    ]
  end

  defp options(atoms) do
    Enum.map(atoms, fn atom ->
      value = Atom.to_string(atom)
      %{value: value, label: value |> String.replace("_", " ") |> String.capitalize()}
    end)
  end

  defp list(path, label),
    do: field(path, label, :list, [], advanced: true, help: "Ids; empty means any.")

  defp int(path, label, default, min, max, opts),
    do: field(path, label, :integer, default, Keyword.put(opts, :range, %{min: min, max: max}))

  defp field(path, label, type, default, opts) do
    [group | _] = String.split(path, ".")

    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      default: default,
      required: Keyword.get(opts, :required, false),
      help: Keyword.get(opts, :help),
      visible_when: Keyword.get(opts, :visible_when),
      group: group,
      advanced: Keyword.get(opts, :advanced, false)
    }
  end
end
