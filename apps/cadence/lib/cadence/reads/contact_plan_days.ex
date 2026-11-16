defmodule Cadence.Reads.ContactPlanDays do
  @moduledoc """
  DECISIONS #100's K1 day strip (fe-setup, ux): for each UTC day in a range of at most 14, the
  day's plan and how much there is to plan, in one read.

    * `plan`: the day's plan by the console's own rule (`planOfDay`): repair proposals aside, the
      newest plan that isn't superseded or canceled, else the newest if it's a superseded draft.
      Its stored state here; the controller folds in the derived ones (interrupted, unconfirmed)
      and the execution counts, as the plan list does.
    * `sent_back`: the plan is a draft whose latest decision is a rejection.
    * `requirements_count`: the day's contacts needed (`PlanningSetup.demand_days/3`, as Setup's
      demand), 0 when there's nothing to plan.

  Plans come from one list read (newest first, capped at 100), grouped by their window's day.
  """

  alias Cadence.Reads.{ContactPlanOverview, PlanApproval, PlanningSetup}

  @max_days 14

  @spec load(binary(), binary(), Date.t(), Date.t()) ::
          {:ok, [map()]} | {:error, {:invalid_params, map()}}
  def load(org, mission, %Date{} = from, %Date{} = to) do
    span = Date.diff(to, from) + 1

    if span in 1..@max_days do
      days = Enum.map(0..(span - 1), &Date.add(from, &1))
      demand = PlanningSetup.demand_days(org, mission, days)

      by_day =
        org
        |> ContactPlanOverview.list(mission, %{})
        |> Enum.filter(&(&1.repair_of == nil and &1.window.from != nil))
        |> Enum.group_by(&DateTime.to_date(&1.window.from))

      {:ok,
       Enum.map(days, fn day ->
         plan = plan_of_day(Map.get(by_day, day, []))

         %{
           day: day,
           plan: plan,
           sent_back: plan != nil and sent_back?(org, mission, plan),
           requirements_count: demand |> Map.fetch!(day) |> Map.fetch!(:contacts_needed)
         }
       end)}
    else
      {:error, {:invalid_params, %{to: "Ask for 1 to #{@max_days} days, from on or before to"}}}
    end
  end

  # The console's planOfDay: the current plan, else the newest if it's a superseded draft.
  defp plan_of_day(plans) do
    case Enum.find(plans, &(&1.state not in [:superseded, :canceled])) do
      nil ->
        case plans do
          [%{state: :superseded, superseded: %{}} = newest | _] -> newest
          _none -> nil
        end

      current ->
        current
    end
  end

  defp sent_back?(org, mission, %{state: :draft, id: id, version: version}),
    do: match?(%{decision: :rejected}, PlanApproval.latest(org, mission, id, version))

  defp sent_back?(_org, _mission, _plan), do: false
end
