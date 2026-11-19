defmodule CadenceWeb.Console.PlanDetail do
  @moduledoc """
  Plan detail for the contact-plan reads and writes that answer with it (show, S4 edit, the
  send-back), so they all carry the same keys. Contract: docs/apogee/api/scheduling.md.
  """

  alias Cadence.ContactPlanning.RepairChain
  alias Cadence.Control.{PlanConfirmation, Scheduling}
  alias Cadence.Reads.PlanRepairHeader

  @doc """
  The plan detail of a plan read (`ContactPlanOverview.plan`): the effective state, each pass's
  booking (K1 8e), U30 `unconfirmed` and the execution summary, and the repair `chain`.
  """
  @spec build(Plug.Conn.t(), map()) :: map()
  def build(conn, plan) do
    # U30 unconfirmed, the execution summary and each pass's booking (lead), from one read.
    {bookings, confirmation} =
      conn |> org_id() |> PlanConfirmation.detail(mission_id(conn), plan.id) |> Map.pop(:bookings)

    conn
    |> effective_state(plan)
    |> with_bookings(bookings)
    |> Map.merge(confirmation)
    |> Map.merge(chain(conn, plan.id))
    |> Map.put(
      :repair,
      PlanRepairHeader.for_plan(org_id(conn), mission_id(conn), plan.id, DateTime.utc_now())
    )
  end

  # K1 8e: passes[].booking, null for a pass the approved version doesn't book (or before approval).
  defp with_bookings(%{passes: passes} = plan, bookings) when is_list(passes),
    do: %{plan | passes: Enum.map(passes, &Map.put(&1, :booking, bookings[&1.snapshot_id]))}

  defp with_bookings(plan, _bookings), do: plan

  # qa #30: the day's repair chain (root first, then applied repairs) and its head.
  defp chain(conn, plan_id) do
    case RepairChain.load(org_id(conn), mission_id(conn), plan_id) do
      {:ok, chain} ->
        %{
          chain: Enum.map(chain.plans, &%{id: &1, version: chain.versions[&1]}),
          chain_head: chain.head
        }

      {:error, _not_found} ->
        %{chain: [], chain_head: nil}
    end
  end

  @doc "A plan read with its derived state (`interrupted`, `unconfirmed`, …)."
  @spec effective_state(Plug.Conn.t(), map()) :: map()
  def effective_state(conn, plan),
    do: %{
      plan
      | state: Scheduling.plan_state(org_id(conn), mission_id(conn), plan.id, plan.state)
    }

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
