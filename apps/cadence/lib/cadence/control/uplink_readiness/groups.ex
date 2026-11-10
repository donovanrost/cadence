defmodule Cadence.Control.UplinkReadiness.Groups do
  @moduledoc """
  The pass each command group waits for (#58). Requests queue per source-endpoint lane, not
  per contact: a release goes out on the target spacecraft's live uplink pass. So a group's
  `contact` is its spacecraft's live pass (any readiness), and `next_contact` the next booked
  pass that can command after it. Both carry `ground_station_ref`, `starts_at`/`ends_at`
  (AOS/LOS) and, when live,
  `readiness`. Groups are keyed by their first target; `targets` lists every target.
  """

  alias Cadence.Commanding.Groups.Waiting
  alias Cadence.Contacts.UplinkPasses
  alias Cadence.Control.UplinkReadiness
  alias Cadence.SourceEndpoints

  @spec for_command_groups(binary(), binary(), [binary()], keyword()) :: map()
  def for_command_groups(org, mission, group_ids, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    table = Keyword.get(opts, :table, UplinkReadiness.table())
    by_group = Waiting.endpoints(org, mission, group_ids)
    spacecraft = spacecraft_by_endpoint(org, mission)

    targets =
      Map.new(by_group, fn {group_id, refs} ->
        {group_id, refs |> Enum.map(&spacecraft[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()}
      end)

    ids = targets |> Map.values() |> List.flatten() |> Enum.uniq()
    live = live_by_spacecraft(org, mission, table)
    upcoming = UplinkPasses.upcoming(org, mission, ids, now, 2)

    Map.new(targets, fn {group_id, spacecraft_ids} ->
      per_target = Enum.map(spacecraft_ids, &target(&1, live, upcoming))
      first = List.first(per_target) || %{contact: nil, next_contact: nil}
      {group_id, %{contact: first.contact, next_contact: first.next_contact, targets: per_target}}
    end)
  end

  defp target(spacecraft_id, live, upcoming) do
    current = live[spacecraft_id]
    passes = Map.get(upcoming, spacecraft_id, [])

    next =
      passes
      |> Enum.reject(&(current && &1.scheduled_contact_id == current.scheduled_contact_id))
      |> List.first()

    %{
      spacecraft_id: spacecraft_id,
      contact: current && pass(current, UplinkReadiness.view(current)),
      next_contact: next && pass(next, nil)
    }
  end

  defp pass(pass, readiness),
    do: %{
      scheduled_contact_id: pass.scheduled_contact_id,
      ground_station_ref: pass.ground_station_ref,
      starts_at: pass.starts_at,
      ends_at: pass.ends_at,
      readiness: readiness
    }

  defp live_by_spacecraft(org, mission, table) do
    org
    |> UplinkReadiness.live(mission, table)
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  @doc false
  def spacecraft_by_endpoint(org, mission) do
    org
    |> SourceEndpoints.list_source_endpoints(mission)
    |> Map.new(&{&1.source_endpoint_id, &1.spacecraft_id})
  end
end
