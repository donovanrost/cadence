defmodule Cadence.ContactPlanning.RepairPairing do
  @moduledoc """
  Which lost booking each new pass of a repair replaces (qa #30), fixed when the repair's
  candidate plan is created and persisted on its run (`result_summary_document["replaces"]`,
  `%{new snapshot_id => lost key}`).

  The repair records the lost bookings it started from in its input
  (`input_document["repair"]["lost_bookings"]`, from `RepairChain` at repair start). New passes
  are the candidate's selected passes that aren't locked. They pair per spacecraft in time
  order, the same way the repair diff pairs moves.
  """

  alias Cadence.ContactPlanning.ContactPlans

  @doc "`%{\"replaces\" => pairs}` for a repair run's candidate version, else `%{}`."
  @spec summary(struct(), struct()) :: map()
  def summary(
        %{input_document: %{"repair" => %{"lost_bookings" => [_ | _] = lost}}} = run,
        version
      ) do
    locked = MapSet.new(version.locked_snapshot_ids)

    fresh =
      run.organization_id
      |> ContactPlans.selected_snapshots(run.mission_id, version.contact_plan_id, version.version)
      |> Enum.reject(&MapSet.member?(locked, &1.contact_opportunity_snapshot_id))
      |> Enum.map(
        &%{
          id: &1.contact_opportunity_snapshot_id,
          spacecraft_id: (&1.route_binding_document || %{})["spacecraft_id"],
          starts_at: &1.starts_at
        }
      )

    lost =
      Enum.map(lost, fn booking ->
        {:ok, starts_at, _} = DateTime.from_iso8601(booking["starts_at"])
        %{id: booking["key"], spacecraft_id: booking["spacecraft_id"], starts_at: starts_at}
      end)

    %{"replaces" => pair(lost, fresh)}
  end

  def summary(_run, _version), do: %{}

  @doc "Pairs `%{id, spacecraft_id, starts_at}` lists per spacecraft in time order: `%{new id => lost id}`."
  @spec pair([map()], [map()]) :: %{binary() => binary()}
  def pair(lost, fresh) do
    lost_by = Enum.group_by(lost, & &1.spacecraft_id)

    for {spacecraft_id, new} <- Enum.group_by(fresh, & &1.spacecraft_id),
        {to, from} <-
          Enum.zip(
            Enum.sort_by(new, & &1.starts_at, DateTime),
            lost_by |> Map.get(spacecraft_id, []) |> Enum.sort_by(& &1.starts_at, DateTime)
          ),
        into: %{},
        do: {to.id, from.id}
  end
end
