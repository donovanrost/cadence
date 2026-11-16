defmodule CadenceWeb.Console.ContactPlanDaysController do
  @moduledoc """
  DECISIONS #100: `GET /contact-plans/days?from=YYYY-MM-DD&to=YYYY-MM-DD` (≤ 14 days), K1's day
  strip in one read. The days and plans come from `Cadence.Reads.ContactPlanDays`; here, as the
  plan list does, each plan's state gains the derived words (interrupted, unconfirmed) and its
  execution counts. Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.{PlanConfirmation, Scheduling}
  alias Cadence.Reads.ContactPlanDays
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, params) do
    org = conn.assigns.current_scope.organization_id
    mission = conn.assigns.current_mission.mission_id

    with {:ok, from} <- date(params["from"], :from),
         {:ok, to} <- date(params["to"], :to),
         {:ok, days} <- ContactPlanDays.load(org, mission, from, to) do
      json(conn, %{data: ConfigJSON.encode(%{days: Enum.map(days, &day(&1, org, mission))})})
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  defp day(%{plan: nil} = day, _org, _mission),
    do:
      Map.merge(day, %{
        booked_count: nil,
        unconfirmed_count: nil,
        requested_count: nil,
        first_window_at: Map.get(day, :first_window_at)
      })

  defp day(%{plan: plan} = day, org, mission) do
    execution = PlanConfirmation.detail(org, mission, plan.id).execution || %{}

    Map.merge(day, %{
      plan: %{
        id: plan.id,
        version: plan.version,
        state: Scheduling.plan_state(org, mission, plan.id, plan.state)
      },
      # Plan detail's execution counts (passes): confirmed, uncertain (unconfirmed), requested.
      booked_count: execution[:confirmed],
      unconfirmed_count: execution[:uncertain],
      requested_count: execution[:requested],
      # U61: the day demand's first window (domain's plan_coverage rule), null until it lands.
      first_window_at: Map.get(day, :first_window_at)
    })
  end

  defp date(value, field) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, {:invalid_params, %{field => "Use a UTC day, YYYY-MM-DD"}}}
    end
  end

  defp date(_value, field), do: {:error, {:invalid_params, %{field => "Choose a day"}}}
end
