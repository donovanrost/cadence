defmodule Cadence.Reads.PassBooking do
  @moduledoc """
  U74 (ux, fe-ops): the words for a pass's 'Booked' row ("From the 11-14 plan (R3) · for Block 1
  daily"), on pass detail:

    * `plan: %{id, version, day}`: `day` is the plan's UTC day, the day of its earliest selected
      pass (as plan detail derives it), `nil` when that can't be read;
    * `requirement: %{id, version, name}`: `name` per `RequirementLabels` (template name, else
      the rule in words), `nil` when the requirement can't be read.

  Both stay `nil` for a pass booked outside a plan.
  """

  alias Cadence.Management.Contacts
  alias Cadence.Reads.RequirementLabels

  @spec names(binary(), binary(), map()) :: %{plan: map() | nil, requirement: map() | nil}
  def names(org, mission, pass) do
    %{
      plan: plan(org, mission, pass[:plan]),
      requirement: requirement(org, mission, pass[:requirement])
    }
  end

  defp plan(_org, _mission, nil), do: nil

  defp plan(org, mission, %{id: id, version: version} = plan) do
    day =
      org
      |> Contacts.selected_opportunities(mission, id, version)
      |> Enum.map(& &1.starts_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(DateTime, fn -> nil end)
      |> then(&(&1 && DateTime.to_date(&1)))

    Map.put(plan, :day, day)
  end

  defp requirement(_org, _mission, nil), do: nil

  defp requirement(org, mission, %{id: id, version: version} = requirement) do
    label = RequirementLabels.load(org, mission, [{id, version}])[{id, version}]
    Map.put(requirement, :name, label && label.name)
  end
end
