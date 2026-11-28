defmodule Cadence.Observability.ScaleSampler.Host do
  @moduledoc """
  What else the machine was doing during a scale run (#717; the CTO's rule for every #686
  number): load average, swap in use and how many coding agents run on the host. A laptop shared
  with a dozen agents makes timings meaningless without it.

  macOS reads `sysctl`. Linux reads load and swap from `/proc` and counts available CPUs
  with `nproc`.
  """

  @type load_average :: %{one: float(), five: float(), fifteen: float()}
  @type swap :: %{swap_used_mb: float(), swap_total_mb: float()}
  @type pre_run :: %{
          load_one: number() | nil,
          swap_percent: number() | nil,
          settle_ms: non_neg_integer(),
          settled?: boolean()
        }

  @settle_interval_ms 10_000
  @settle_timeout_ms 300_000

  @doc "This second's host load, swap usage and agent processes."
  @spec sample() :: %{
          load: load_average() | nil,
          swap_used_mb: float() | nil,
          swap_total_mb: float() | nil,
          agents: integer() | nil
        }
  def sample do
    Map.put(load_and_swap(), :agents, agents())
  end

  @doc "Waits for a dedicated runner's pre-run load and swap to settle."
  @spec settle(keyword()) :: pre_run()
  def settle(opts \\ []) do
    read_host = Keyword.get(opts, :read_host, &load_and_swap/0)
    logical_cpus = Keyword.get_lazy(opts, :logical_cpus, &logical_cpus/0)
    timeout_ms = Keyword.get(opts, :timeout_ms, @settle_timeout_ms)
    settle(read_host, logical_cpus, System.monotonic_time(:millisecond), timeout_ms)
  end

  defp settle(read_host, logical_cpus, started, timeout_ms) do
    capacity = capacity_for([read_host.()], logical_cpus)
    elapsed_ms = System.monotonic_time(:millisecond) - started
    settled? = capacity.classification == :baseline

    if settled? or elapsed_ms >= timeout_ms do
      %{
        load_one: capacity.max_load_one,
        swap_percent: capacity.max_swap_percent,
        settle_ms: elapsed_ms,
        settled?: settled?
      }
    else
      Process.sleep(min(@settle_interval_ms, timeout_ms - elapsed_ms))
      settle(read_host, logical_cpus, started, timeout_ms)
    end
  end

  defp load_and_swap do
    swap = swap() || %{swap_used_mb: nil, swap_total_mb: nil}
    Map.put(swap, :load, load())
  end

  @doc """
  Reports the load and swap peaks during a run. A local run uses every sample to
  determine capacity. A dedicated runner uses its host sample from before the
  workload and reports during-run pressure separately.
  """
  @spec capacity([map()], pos_integer() | :unknown, :local | pre_run()) :: %{
          optional(:pre_run) => pre_run(),
          classification: :baseline | :ceiling_check,
          max_load_one: number() | nil,
          max_swap_percent: number() | nil
        }
  def capacity(samples, logical_cpus, pre_run \\ :local)

  def capacity(samples, logical_cpus, :local), do: capacity_for(samples, logical_cpus)

  def capacity(samples, logical_cpus, %{settled?: settled?} = pre_run) do
    during = capacity_for(samples, logical_cpus)

    Map.merge(during, %{
      classification: if(settled?, do: :baseline, else: :ceiling_check),
      pre_run: pre_run
    })
  end

  defp capacity_for(samples, logical_cpus) do
    {max_load, load_complete?} = samples |> Enum.map(&get_in(&1, [:load, :one])) |> measured_max()
    {max_swap, swap_complete?} = samples |> Enum.map(&swap_percent/1) |> measured_max()

    baseline? =
      load_complete? and swap_complete? and is_integer(logical_cpus) and logical_cpus > 0 and
        max_load <= logical_cpus and max_swap < 50.0

    %{
      classification: if(baseline?, do: :baseline, else: :ceiling_check),
      max_load_one: max_load,
      max_swap_percent: max_swap
    }
  end

  defp measured_max(values) do
    readings = Enum.filter(values, &is_number/1)
    {Enum.max(readings, fn -> nil end), readings != [] and length(readings) == length(values)}
  end

  defp swap_percent(%{swap_used_mb: used, swap_total_mb: total})
       when is_number(used) and used >= 0 and is_number(total) and total > 0,
       do: used / total * 100

  defp swap_percent(%{swap_used_mb: used, swap_total_mb: total}) when used == 0 and total == 0,
    do: 0.0

  defp swap_percent(_sample), do: nil

  @doc "Static facts for the run's `meta.host`."
  @spec info() :: map()
  def info do
    {:ok, hostname} = :inet.gethostname()

    %{
      hostname: to_string(hostname),
      os: :os.type() |> Tuple.to_list() |> Enum.join("/"),
      logical_cpus: logical_cpus(),
      ram_mb: ram_mb()
    }
  end

  defp logical_cpus do
    case :os.type() do
      {:unix, :linux} -> cmd("nproc", [], &parse_nproc/1) || :unknown
      _os -> :erlang.system_info(:logical_processors_available)
    end
  end

  @doc "Parses the count of available logical CPUs reported by Linux `nproc`."
  @spec parse_nproc(binary()) :: pos_integer() | nil
  def parse_nproc(text) do
    case text |> String.trim() |> Integer.parse() do
      {count, ""} when count > 0 -> count
      _unreadable -> nil
    end
  end

  # The machine's physical memory (the BEAM's own memory is in each row's `beam`).
  defp ram_mb do
    case :os.type() do
      {:unix, :darwin} -> cmd("sysctl", ["-n", "hw.memsize"], &bytes_to_mb/1)
      _linux -> read("/proc/meminfo", &meminfo_total_mb/1)
    end
  end

  defp bytes_to_mb(text), do: text |> String.trim() |> String.to_integer() |> div(1_048_576)

  defp meminfo_total_mb(text) do
    case Regex.run(~r/MemTotal:\s+(\d+) kB/, text) do
      [_, kb] -> div(String.to_integer(kb), 1024)
      nil -> nil
    end
  end

  @doc "Parses `sysctl -n vm.loadavg` (`{ 6.35 12.87 21.90 }`) or `/proc/loadavg`."
  @spec parse_load(binary()) :: load_average() | nil
  def parse_load(text) do
    case Regex.scan(~r/\d+(?:\.\d+)?/, text) |> Enum.take(3) do
      [[one], [five], [fifteen]] ->
        %{one: to_float(one), five: to_float(five), fifteen: to_float(fifteen)}

      _unreadable ->
        nil
    end
  end

  @doc "Parses swap used and total MB from `sysctl -n vm.swapusage`."
  @spec parse_macos_swap(binary()) :: swap() | nil
  def parse_macos_swap(text) do
    with [_, used, used_unit] <- Regex.run(~r/used = ([\d.]+)([KMG])/, text),
         [_, total, total_unit] <- Regex.run(~r/total = ([\d.]+)([KMG])/, text) do
      %{swap_used_mb: swap_mb(used, used_unit), swap_total_mb: swap_mb(total, total_unit)}
    end
  end

  defp swap_mb(value, unit),
    do: to_float(value) * Map.fetch!(%{"K" => 1 / 1024, "M" => 1, "G" => 1024}, unit)

  @doc "Parses swap used and total MB from `/proc/meminfo`."
  @spec parse_linux_swap(binary()) :: swap() | nil
  def parse_linux_swap(text) do
    with [_, total] <- Regex.run(~r/SwapTotal:\s+(\d+) kB/, text),
         [_, free] <- Regex.run(~r/SwapFree:\s+(\d+) kB/, text) do
      total_kb = String.to_integer(total)
      %{swap_used_mb: (total_kb - String.to_integer(free)) / 1024, swap_total_mb: total_kb / 1024}
    else
      _unreadable -> nil
    end
  end

  @doc "Counts coding-agent processes (Claude Code and Codex) in `ps -axo command=` output."
  @spec count_agents(binary()) :: non_neg_integer()
  def count_agents(ps_output) do
    ps_output
    |> String.split("\n", trim: true)
    |> Enum.count(&Regex.match?(~r{(^|/)claude(\s|$)|(^|/)codex(\s|$)|/codex\.js(\s|$)}, &1))
  end

  defp load do
    case :os.type() do
      {:unix, :darwin} -> cmd("sysctl", ["-n", "vm.loadavg"], &parse_load/1)
      _linux -> read("/proc/loadavg", &parse_load/1)
    end
  end

  defp swap do
    case :os.type() do
      {:unix, :darwin} -> cmd("sysctl", ["-n", "vm.swapusage"], &parse_macos_swap/1)
      _linux -> read("/proc/meminfo", &parse_linux_swap/1)
    end
  end

  defp agents, do: cmd("ps", ["-axo", "command="], &count_agents/1)

  defp cmd(program, args, parse) do
    case System.cmd(program, args, stderr_to_stdout: true) do
      {output, 0} -> parse.(output)
      _failed -> nil
    end
  rescue
    _unavailable -> nil
  end

  defp read(path, parse) do
    case File.read(path) do
      {:ok, text} -> parse.(text)
      {:error, _reason} -> nil
    end
  end

  defp to_float(text) do
    {value, _rest} = Float.parse(text)
    value
  end
end
