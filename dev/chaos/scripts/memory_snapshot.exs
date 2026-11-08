# Return a small sampling function. Never copy process dictionaries or runtime specs.
unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
         System.get_env("POD_NAMESPACE") == "cadence-chaos",
       do: raise("Not the lab")

fn ->
  largest =
    Process.list()
    |> Enum.flat_map(fn pid ->
      case Process.info(pid, [:memory, :registered_name, :current_function, :message_queue_len]) do
        nil -> []
        info -> [info |> Map.new() |> Map.put(:pid, inspect(pid))]
      end
    end)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(10)
    |> Enum.map(fn info ->
      info
      |> Map.update!(:current_function, &inspect/1)
      |> Map.update!(:registered_name, &inspect/1)
    end)

  cgroup =
    Map.new(["memory.current", "memory.peak", "memory.max", "memory.events"], fn name ->
      value =
        case File.read(Path.join("/sys/fs/cgroup", name)) do
          {:ok, value} -> String.trim(value)
          {:error, reason} -> inspect(reason)
        end

      {name, value}
    end)

  %{
    at: DateTime.utc_now(),
    pod: System.get_env("POD_NAME"),
    beam: Map.new(:erlang.memory()),
    largest_processes: largest,
    cgroup: cgroup
  }
end
