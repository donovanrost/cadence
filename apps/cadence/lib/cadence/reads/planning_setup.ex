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
    FleetPlanningPolicies
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
  def demand(organization_id, mission_id, %Date{} = day) do
    from = DateTime.new!(day, ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(Date.add(day, 1), ~T[00:00:00], "Etc/UTC")

    requirements =
      organization_id
      |> ContactRequirements.list(mission_id, lifecycle_state: :active)
      |> Enum.filter(fn {_requirement, version} -> overlaps?(version, from, until) end)

    requirement_needs =
      Enum.map(requirements, fn {_requirement, version} ->
        {version.spacecraft_id, version.contact_count || 1}
      end)

    # Occurrences already materialized are counted once, as their requirement.
    materialized = requirements |> Enum.map(&generated_from/1) |> MapSet.new()

    template_needs =
      organization_id
      |> ContactRequirementTemplates.list(mission_id, lifecycle_state: :active)
      |> Enum.flat_map(fn {template, version} ->
        count = (version.requirement_document || %{})["contact_count"] || 1

        version
        |> ContactRequirementTemplates.preview_occurrences(from, until)
        # The schedule range includes `until`; that occurrence belongs to the next day.
        |> Enum.filter(&DateTime.before?(&1, until))
        |> Enum.reject(fn occurrence ->
          MapSet.member?(
            materialized,
            {template.contact_requirement_template_id, DateTime.to_unix(occurrence)}
          )
        end)
        |> Enum.map(fn _occurrence -> {version.spacecraft_id, count} end)
      end)

    needs = requirement_needs ++ template_needs
    with_rules = needs |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1) |> MapSet.new()
    total = length(Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id))

    %{
      day: day,
      spacecraft_with_rules: MapSet.size(with_rules),
      contacts_needed: needs |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      without_rule: max(total - MapSet.size(with_rules), 0),
      spacecraft_total: total
    }
  end

  defp generated_from({_requirement, version}) do
    with %{"contact_requirement_template_id" => id, "occurrence_at" => at} <-
           (version.metadata || %{})["generation"],
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      {id, DateTime.to_unix(at)}
    else
      _not_generated -> nil
    end
  end

  defp overlaps?(version, from, until),
    do:
      DateTime.before?(version.earliest_start, until) and
        DateTime.after?(version.latest_end, from)
end
