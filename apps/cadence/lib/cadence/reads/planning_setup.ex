defmodule Cadence.Reads.PlanningSetup do
  @moduledoc """
  Whether a mission can draft contact plans, and the contact demand for a UTC
  day before any draft exists. Callers authorize first.

  Drafting needs an active fleet planning policy and at least one active
  contact requirement or requirement template. Day demand counts active
  requirements whose window overlaps the day plus template occurrences due
  that day (previewed from each template's schedule; nothing is materialized).
  """

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    TemplateTargets
  }

  @spec setup(binary(), binary()) :: map()
  def setup(organization_id, mission_id) do
    policy =
      case FleetPlanningPolicies.fetch_active(organization_id, mission_id) do
        {:ok, policy, version} -> %{id: policy.fleet_planning_policy_id, version: version.version}
        _none -> nil
      end

    requirements =
      length(ContactRequirements.list(organization_id, mission_id, lifecycle_state: :active))

    templates =
      length(
        ContactRequirementTemplates.list(organization_id, mission_id, lifecycle_state: :active)
      )

    missing =
      Enum.reject(
        [
          if(is_nil(policy), do: "fleet_planning_policy"),
          if(requirements + templates == 0, do: "contact_requirements")
        ],
        &is_nil/1
      )

    %{
      ready: missing == [],
      missing: missing,
      policy: policy,
      requirements: requirements,
      templates: templates
    }
  end

  @spec demand(binary(), binary(), Date.t()) :: map()
  def demand(organization_id, mission_id, %Date{} = day),
    do: organization_id |> demand_days(mission_id, [day]) |> Map.fetch!(day)

  @doc """
  `demand/3` for several UTC days in one pass (DECISIONS #100's day strip): requirements, templates
  and template targets are read once. `%{day => demand}`.
  """
  @spec demand_days(binary(), binary(), [Date.t()]) :: %{Date.t() => map()}
  def demand_days(organization_id, mission_id, days) do
    requirements = ContactRequirements.list(organization_id, mission_id, lifecycle_state: :active)

    templates =
      organization_id
      |> ContactRequirementTemplates.list(mission_id, lifecycle_state: :active)
      |> Enum.map(fn {template, version} ->
        {template, version,
         TemplateTargets.resolve(organization_id, mission_id, version.target_document)}
      end)

    total = length(Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id))

    Map.new(days, &{&1, day_demand(&1, requirements, templates, total)})
  end

  defp day_demand(day, requirements, templates, total) do
    from = DateTime.new!(day, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(Date.add(day, 1), ~T[00:00:00], "Etc/UTC")

    requirements =
      Enum.filter(requirements, fn {_requirement, version} -> overlaps?(version, from, until) end)

    requirement_needs =
      Enum.map(requirements, fn {_requirement, version} ->
        {version.spacecraft_id, version.contact_count || 1}
      end)

    # Occurrences already materialized are counted once, as their requirement.
    materialized = requirements |> Enum.map(&generated_from/1) |> MapSet.new()

    template_needs =
      Enum.flat_map(templates, fn {template, version, targets} ->
        count = (version.requirement_document || %{})["contact_count"] || 1

        # The schedule range includes `until`; that occurrence belongs to the next day.
        for occurrence <- ContactRequirementTemplates.preview_occurrences(version, from, until),
            DateTime.before?(occurrence, until),
            spacecraft_id <- targets,
            not MapSet.member?(
              materialized,
              {template.contact_requirement_template_id, DateTime.to_unix(occurrence),
               spacecraft_id}
            ),
            do: {spacecraft_id, count, occurrence}
      end)

    # U61: the first window that STARTS in the day. A requirement carried over from the day before
    # (its window opened then) doesn't start this day's countdown.
    window_starts =
      for(
        {_requirement, version} <- requirements,
        not DateTime.before?(version.earliest_start, from),
        do: version.earliest_start
      ) ++ Enum.map(template_needs, &elem(&1, 2))

    needs = requirement_needs ++ Enum.map(template_needs, fn {id, count, _at} -> {id, count} end)
    with_rules = needs |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1) |> MapSet.new()

    %{
      day: day,
      spacecraft_with_rules: MapSet.size(with_rules),
      contacts_needed: needs |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      without_rule: max(total - MapSet.size(with_rules), 0),
      spacecraft_total: total,
      first_window_at: Enum.min(window_starts, DateTime, fn -> nil end)
    }
  end

  defp generated_from({_requirement, version}) do
    with %{"contact_requirement_template_id" => id, "occurrence_at" => at} <-
           (version.metadata || %{})["generation"],
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      {id, DateTime.to_unix(at), version.spacecraft_id}
    else
      _not_generated -> nil
    end
  end

  defp overlaps?(version, from, until),
    do:
      DateTime.before?(version.earliest_start, until) and
        DateTime.after?(version.latest_end, from)
end
