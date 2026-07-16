defmodule CadenceSimulator.Provider.EventDelivery do
  @moduledoc "Applies durable run-scoped delivery faults to the provider event feed."

  alias CadenceSimulator.Provider.Store

  @spec page(map(), non_neg_integer(), pos_integer()) :: %{
          data: [map()],
          next_cursor: non_neg_integer()
        }
  def page(run, cursor, limit)
      when is_map(run) and is_integer(cursor) and cursor >= 0 and is_integer(limit) and
             limit > 0 do
    raw_page = Store.events_for_run(run["id"], cursor, limit)
    faults = get_in(run, ["scenario_snapshot", "fault_profile"]) || %{}

    if consume?(run, faults, "event_delay_poll_count") do
      %{data: [], next_cursor: cursor}
    else
      data =
        raw_page.data
        |> maybe_omit(run, faults)
        |> maybe_duplicate(run, faults)
        |> maybe_collide(run, faults)
        |> maybe_reorder(run, faults)
        |> Enum.take(limit)

      %{data: data, next_cursor: raw_page.next_cursor}
    end
  end

  defp maybe_omit([], _run, _faults), do: []

  defp maybe_omit([_event | rest] = events, run, faults) do
    if consume?(run, faults, "event_omission_count"), do: rest, else: events
  end

  defp maybe_duplicate([], _run, _faults), do: []

  defp maybe_duplicate([event | rest] = events, run, faults) do
    if consume?(run, faults, "event_duplication_count"),
      do: [event, event | rest],
      else: events
  end

  defp maybe_collide([], _run, _faults), do: []

  defp maybe_collide([event | rest] = events, run, faults) do
    if consume?(run, faults, "event_identity_collision_count") do
      collision =
        Map.update(event, "data", %{"simulated_identity_collision" => true}, fn data ->
          Map.put(data, "simulated_identity_collision", true)
        end)

      [event, collision | rest]
    else
      events
    end
  end

  defp maybe_reorder(events, run, faults) do
    if consume?(run, faults, "event_reordering_count"),
      do: Enum.reverse(events),
      else: events
  end

  defp consume?(run, faults, field) do
    Store.consume_fault(run["id"], field, Map.get(faults, field, 0))
  end
end
