defmodule Cadence.Reads.ContactPlanOverview.Demand do
  @moduledoc """
  A plan version's demand for plan detail (`Cadence.Reads.ContactPlanOverview`): per-spacecraft
  rule evaluation with its measures (S2 demand), the rules in words, and the requirements the
  version leaves unmet (what an approver must acknowledge).
  """

  alias Cadence.ContactPlanning.{ContactOpportunitySnapshot, ContactPlanVersion}
  alias Cadence.Management.Contacts
  alias Cadence.Reads.PlanMeasures

  @doc """
  Per-spacecraft rule evaluation from a plan version's coverage, plus the rules, with each
  spacecraft's measures over the version's selected `passes` (`PlanMeasures`).
  """
  @spec demand(binary(), binary(), ContactPlanVersion.t(), [ContactOpportunitySnapshot.t()]) ::
          map()
  def demand(organization_id, mission_id, %ContactPlanVersion{} = version, passes) do
    evaluations = (version.coverage_document || %{})["requirements"] || []

    rules =
      Enum.flat_map(evaluations, fn evaluation ->
        case Contacts.fetch_requirement_version(
               organization_id,
               mission_id,
               evaluation["contact_requirement_id"],
               evaluation["contact_requirement_version"]
             ) do
          {:ok, requirement} -> [{requirement, evaluation}]
          _missing -> []
        end
      end)

    day = PlanMeasures.day(passes)
    by_craft = Enum.group_by(passes, &(&1.route_binding_document || %{})["spacecraft_id"])

    spacecraft =
      rules
      |> Enum.group_by(fn {requirement, _evaluation} -> requirement.spacecraft_id end)
      |> Enum.map(fn {spacecraft_id, items} ->
        mine = Map.get(by_craft, spacecraft_id, [])

        spacecraft_id
        |> spacecraft_demand(items)
        |> Map.merge(%{
          longest_gap: items |> Enum.map(&elem(&1, 0)) |> PlanMeasures.spacecraft_gap(mine, day),
          uplink_passes: PlanMeasures.uplink_passes(organization_id, mission_id, mine)
        })
      end)
      |> Enum.sort_by(&{&1.rule_met, &1.spacecraft_id})

    %{
      spacecraft: spacecraft,
      rule_met: Enum.count(spacecraft, & &1.rule_met),
      rule_total: length(spacecraft),
      rules: Enum.map(rules, fn {requirement, _evaluation} -> rule(requirement) end)
    }
  end

  @doc "Requirements the version leaves unsatisfied (what an approver must acknowledge)."
  @spec unmet(binary(), binary(), ContactPlanVersion.t()) :: [map()]
  def unmet(organization_id, mission_id, version) do
    ((version.unsatisfied_document || %{})["requirements"] || [])
    |> Enum.map(fn item ->
      spacecraft_id =
        case Contacts.fetch_requirement_version(
               organization_id,
               mission_id,
               item["contact_requirement_id"],
               item["contact_requirement_version"]
             ) do
          {:ok, requirement} -> requirement.spacecraft_id
          _missing -> nil
        end

      %{
        requirement_id: item["contact_requirement_id"],
        requirement_version: item["contact_requirement_version"],
        spacecraft_id: spacecraft_id,
        why: Enum.map((item["hard_failures"] || []) ++ (item["search_failures"] || []), &reason/1)
      }
    end)
  end

  defp spacecraft_demand(spacecraft_id, items) do
    {have, need} =
      Enum.reduce(items, {0, 0}, fn {requirement, evaluation}, {have, need} ->
        facts = evaluation["facts"] || %{}
        {have + (facts["selected_count"] || 0), need + (requirement.contact_count || 1)}
      end)

    %{
      spacecraft_id: spacecraft_id,
      rule_met: Enum.all?(items, fn {_requirement, evaluation} -> evaluation["satisfied"] end),
      contacts: %{have: have, need: need},
      reasons:
        items
        |> Enum.flat_map(fn {_requirement, evaluation} ->
          (evaluation["hard_failures"] || []) ++ (evaluation["search_failures"] || [])
        end)
        |> Enum.map(&reason/1)
        |> Enum.uniq()
    }
  end

  defp rule(requirement) do
    %{
      requirement_id: requirement.contact_requirement_id,
      version: requirement.version,
      spacecraft_id: requirement.spacecraft_id,
      text: rule_text(requirement),
      source: "requirement",
      window: %{from: requirement.earliest_start, to: requirement.latest_end}
    }
  end

  @doc "A requirement version's rule in words (\"2 downlink contacts of at least 8 min\")."
  @spec rule_text(map()) :: binary()
  def rule_text(requirement) do
    count = requirement.contact_count || 1
    direction = requirement.service_direction && to_string(requirement.service_direction)

    base = "#{count} #{direction || "contact"} #{if count == 1, do: "contact", else: "contacts"}"

    case requirement.success_measure do
      :minimum_duration ->
        base <> " of at least #{div(requirement.minimum_duration_seconds || 0, 60)} min"

      :minimum_data_volume ->
        base <> " moving at least #{requirement.minimum_data_volume_bytes} bytes"

      _other ->
        base
    end
  end

  defp reason(failure) when is_binary(failure), do: failure
  defp reason(%{"code" => code}), do: code
  defp reason(failure), do: inspect(failure)
end
