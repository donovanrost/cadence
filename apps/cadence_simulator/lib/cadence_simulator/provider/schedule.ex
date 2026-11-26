defmodule CadenceSimulator.Provider.Schedule do
  @moduledoc false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Contacts, Store}

  defstruct generation: nil,
            by_run: %{},
            resources: %{},
            deadlines: :gb_sets.empty(),
            next_due: nil

  def refresh(schedule) do
    generation = Store.schedule_generation()
    changes = Store.take_schedule_changes()
    {schedule, reset?} = load_generation(schedule, generation)

    keys =
      Enum.reduce(changes, MapSet.new(), fn
        {:run, id}, keys -> MapSet.union(keys, Map.get(schedule.by_run, id, MapSet.new()))
        key, keys -> MapSet.put(keys, key)
      end)

    {Enum.reduce(keys, schedule, &update(&2, &1)), reset?, keys}
  end

  def take_due(%{next_due: nil} = schedule, _now), do: {[], schedule}

  def take_due(schedule, now) do
    now = deadline(now)

    if schedule.next_due <= now do
      {due, schedule} = take_due(schedule, now, [])
      {due, cache_next_due(schedule)}
    else
      {[], schedule}
    end
  end

  def update(schedule, {kind, id} = key) do
    schedule
    |> delete(key)
    |> insert(kind, id)
    |> cache_next_due()
  end

  defp insert(schedule, kind, id) do
    key = {kind, id}

    with {:ok, resource} <- Store.fetch(kind, id),
         false <- terminal?(kind, resource["status"]) do
      run_id = resource["run_id"]

      run =
        case Provider.fetch_run(run_id) do
          {:ok, run} -> run
          {:error, :not_found} -> %{}
        end

      time = next_deadline(kind, resource, run)
      item = {time, key}
      deadlines = if time, do: :gb_sets.add(item, schedule.deadlines), else: schedule.deadlines

      %{
        schedule
        | resources: Map.put(schedule.resources, key, {run_id, time}),
          by_run: Map.update(schedule.by_run, run_id, MapSet.new([key]), &MapSet.put(&1, key)),
          deadlines: deadlines
      }
    else
      _other -> schedule
    end
  end

  def terminal?(:contact, status), do: Contacts.terminal_status?(status)
  def terminal?(:reservation, status), do: Provider.terminal_reservation_status?(status)

  def prepass_at(starts_at), do: DateTime.add(starts_at, -2)
  def postpass_at(ends_at), do: DateTime.add(ends_at, -1)

  def midpoint(starts_at, ends_at),
    do: DateTime.add(starts_at, div(DateTime.diff(ends_at, starts_at), 2))

  def fault?(run, resource, key, kind) do
    rate = get_in(run, ["scenario_snapshot", "fault_profile", key]) || 0
    roll = :erlang.phash2({run["seed"], resource["id"], kind}, 1_000_000) / 1_000_000
    rate > 0 and roll < rate
  end

  defp load_generation(%{generation: generation} = schedule, generation), do: {schedule, false}

  defp load_generation(_schedule, generation) do
    schedule =
      Enum.reduce([:reservation, :contact], %__MODULE__{generation: generation}, fn kind, acc ->
        Enum.reduce(Store.list(kind), acc, &update(&2, {kind, &1["id"]}))
      end)

    {schedule, true}
  end

  defp delete(schedule, key) do
    case Map.pop(schedule.resources, key) do
      {nil, _resources} ->
        schedule

      {{run_id, time}, resources} ->
        remaining = schedule.by_run |> Map.fetch!(run_id) |> MapSet.delete(key)

        by_run =
          if MapSet.size(remaining) == 0,
            do: Map.delete(schedule.by_run, run_id),
            else: Map.put(schedule.by_run, run_id, remaining)

        %{
          schedule
          | resources: resources,
            by_run: by_run,
            deadlines: :gb_sets.delete_any({time, key}, schedule.deadlines)
        }
    end
  end

  defp cache_next_due(schedule) do
    next_due =
      if :gb_sets.is_empty(schedule.deadlines),
        do: nil,
        else: elem(:gb_sets.smallest(schedule.deadlines), 0)

    %{schedule | next_due: next_due}
  end

  defp take_due(schedule, now, acc) do
    with false <- :gb_sets.is_empty(schedule.deadlines),
         {{time, key}, rest} when time <= now <- :gb_sets.take_smallest(schedule.deadlines) do
      take_due(%{schedule | deadlines: rest}, now, [key | acc])
    else
      _other -> {Enum.reverse(acc), schedule}
    end
  end

  defp next_deadline(_kind, _resource, %{"state" => "completed"}), do: {0, 0}
  defp next_deadline(:reservation, %{"status" => "pending"}, _run), do: {0, 0}

  defp next_deadline(kind, resource, %{"state" => "running"} = run) do
    case transition_at(kind, resource, run) do
      :immediate ->
        {0, 0}

      %DateTime{} = time ->
        time |> DateTime.add(run["paused_duration_seconds"] || 0) |> deadline()

      nil ->
        nil
    end
  end

  defp next_deadline(_kind, _resource, _run), do: nil

  defp transition_at(:contact, %{"status" => "pending"}, _run), do: :immediate

  defp transition_at(:contact, %{"status" => "confirmed", "pass_phase" => phase} = contact, _run) do
    case {phase, timestamp(contact["starts_at"])} do
      {"scheduled", %DateTime{} = starts} -> prepass_at(starts)
      {"prepass", starts} -> starts
      _other -> nil
    end
  end

  defp transition_at(:reservation, %{"status" => "scheduled"} = reservation, _run) do
    case timestamp(reservation["starts_at"]) do
      %DateTime{} = starts -> prepass_at(starts)
      nil -> nil
    end
  end

  defp transition_at(:reservation, %{"status" => "acquiring"} = reservation, _run),
    do: timestamp(reservation["starts_at"])

  defp transition_at(kind, %{"status" => "active"} = resource, run) do
    with %DateTime{} = starts <- timestamp(resource["starts_at"]),
         %DateTime{} = ends <- timestamp(resource["ends_at"]) do
      active_deadline(kind, resource, run, starts, ends)
    end
  end

  defp transition_at(_kind, _resource, _run), do: nil

  defp active_deadline(:contact, contact, run, starts, ends) do
    delivery = get_in(contact, ["delivery", "status"])

    if delivery in ["connected", "ready"] do
      :immediate
    else
      next_phase = if contact["pass_phase"] == "pass", do: postpass_at(ends), else: ends
      halfway = midpoint(starts, ends)

      if delivery not in ["failed", "ended"] and early_termination?(run, contact) and
           DateTime.before?(halfway, next_phase),
         do: halfway,
         else: next_phase
    end
  end

  defp active_deadline(:reservation, reservation, run, starts, ends) do
    if early_termination?(run, reservation), do: midpoint(starts, ends), else: ends
  end

  defp early_termination?(run, resource),
    do: fault?(run, resource, "early_termination_rate", :early_termination)

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time
      _error -> nil
    end
  end

  defp timestamp(_value), do: nil

  defp deadline(time), do: {1, DateTime.to_unix(time, :microsecond)}
end
