defmodule Cadence.Reads.PlanAlternatives do
  @moduledoc """
  S4 alternatives: for one spacecraft in a plan version, the eligible
  opportunities its planning runs found but the plan didn't select, each with
  its effect if added, evaluated with the pure `RequirementEvaluator` (nothing
  is persisted). Callers authorize first.

  Effect: `rule_met_after` (every requirement of the spacecraft satisfied with
  the pass added), `contacts_after` (`%{have, need}` for the spacecraft),
  `clashes_with` (selected passes of the same spacecraft that overlap it), and
  `longest_gap_after_seconds` (`PlanMeasures.spacecraft_gap/3` with the pass added;
  clashing passes stay in: the limited requirement's gap when one has a limit, else
  the plan-day measure). The top-level `longest_gap` is the
  spacecraft's today.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.ContactPlanning.{ContactOpportunitySnapshot, Planner, RequirementEvaluator}
  alias Cadence.Management.Contacts
  alias Cadence.Reads.PlanMeasures

  @spec load(binary(), binary(), binary(), binary()) :: {:ok, map()} | {:error, :plan_not_found}
  def load(organization_id, mission_id, plan_id, spacecraft_id) do
    case Contacts.fetch_plan(organization_id, mission_id, plan_id) do
      {:ok, _plan, version} ->
        {:ok, alternatives(organization_id, mission_id, plan_id, spacecraft_id, version)}

      _missing ->
        {:error, :plan_not_found}
    end
  end

  defp alternatives(organization_id, mission_id, plan_id, spacecraft_id, version) do
    selected =
      Contacts.selected_opportunities(organization_id, mission_id, plan_id, version.version)

    selected_ids = MapSet.new(selected, & &1.contact_opportunity_snapshot_id)
    mine = Enum.filter(selected, &spacecraft?(&1, spacecraft_id))

    candidates =
      ((version.planning_run_refs_document || %{})["runs"] || [])
      |> Enum.flat_map(&Planner.list_snapshots(organization_id, mission_id, &1))
      |> Enum.filter(&(&1.eligible and spacecraft?(&1, spacecraft_id)))
      |> Enum.reject(&MapSet.member?(selected_ids, &1.contact_opportunity_snapshot_id))
      |> Enum.uniq_by(& &1.contact_opportunity_snapshot_id)
      |> Enum.sort_by(& &1.starts_at, DateTime)

    requirements = requirements(organization_id, mission_id, mine ++ candidates)
    stations = StationRefs.index(organization_id, mission_id)
    # The plan's day; a plan with nothing selected yet takes it from the candidates.
    day = PlanMeasures.day(if selected == [], do: candidates, else: selected)

    %{
      plan_id: plan_id,
      version: version.version,
      spacecraft_id: spacecraft_id,
      rule_met: rule_met?(requirements, mine),
      contacts: contacts(requirements, mine),
      longest_gap: PlanMeasures.spacecraft_gap(requirements, mine, day),
      alternatives:
        Enum.map(candidates, fn candidate ->
          after_selection = [candidate | mine]

          %{
            snapshot_id: candidate.contact_opportunity_snapshot_id,
            requirement_id: candidate.contact_requirement_id,
            station: StationRefs.of_snapshot(candidate, stations),
            starts_at: candidate.starts_at,
            ends_at: candidate.ends_at,
            synthetic: candidate.synthetic,
            effect: %{
              rule_met_after: rule_met?(requirements, after_selection),
              contacts_after: contacts(requirements, after_selection),
              clashes_with:
                mine
                |> Enum.filter(&overlap?(&1, candidate))
                |> Enum.map(& &1.contact_opportunity_snapshot_id),
              longest_gap_after_seconds:
                gap_seconds(PlanMeasures.spacecraft_gap(requirements, after_selection, day))
            }
          }
        end)
    }
  end

  defp gap_seconds(%{seconds: seconds}), do: seconds
  defp gap_seconds(nil), do: nil

  defp requirements(organization_id, mission_id, snapshots) do
    snapshots
    |> Enum.map(&{&1.contact_requirement_id, &1.contact_requirement_version})
    |> Enum.uniq()
    |> Enum.flat_map(fn {id, version} ->
      case Contacts.fetch_requirement_version(organization_id, mission_id, id, version) do
        {:ok, requirement} -> [requirement]
        _missing -> []
      end
    end)
  end

  defp contacts(requirements, selection),
    do: %{
      have: length(selection),
      need: requirements |> Enum.map(&(&1.contact_count || 1)) |> Enum.sum()
    }

  defp rule_met?([], _selection), do: false

  defp rule_met?(requirements, selection) do
    Enum.all?(requirements, fn requirement ->
      own =
        Enum.filter(selection, &(&1.contact_requirement_id == requirement.contact_requirement_id))

      RequirementEvaluator.evaluate_selection(requirement, own)["satisfied"] == true
    end)
  end

  defp spacecraft?(%ContactOpportunitySnapshot{route_binding_document: route}, spacecraft_id),
    do: (route || %{})["spacecraft_id"] == spacecraft_id

  defp overlap?(left, right),
    do:
      DateTime.before?(left.starts_at, right.ends_at) and
        DateTime.before?(right.starts_at, left.ends_at)
end
