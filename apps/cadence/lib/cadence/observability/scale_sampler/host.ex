defmodule Cadence.Observability.ScaleSampler.Host do
  @moduledoc """
  What else the machine was doing during a scale run (#717; the CTO's rule for every #686
  number): load average, swap in use and how many coding agents run on the host. A laptop shared
  with a dozen agents makes timings meaningless without it.

  macOS reads `sysctl`; Linux reads `/proc`. A value that can't be read is `nil`.
  """

  @doc "This second's host line: 1/5/15-minute load, swap used (MB) and agent processes."
  @spec sample() :: %{load: [float()] | nil, swap_used_mb: float() | nil, agents: integer() | nil}
  def sample do
    %{load: load(), swap_used_mb: swap_used_mb(), agents: agents()}
  end

  @doc "Static facts for the run's `meta.host`."
  @spec info() :: map()
  def info do
    {:ok, hostname} = :inet.gethostname()

    %{
      hostname: to_string(hostname),
      os: :os.type() |> Tuple.to_list() |> Enum.join("/"),
      logical_cpus: :erlang.system_info(:logical_processors_available),
      ram_mb: ram_mb()
    }
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
  @spec parse_load(binary()) :: [float()] | nil
  def parse_load(text) do
    case Regex.scan(~r/\d+(?:\.\d+)?/, text) |> Enum.take(3) do
      [[a], [b], [c]] -> Enum.map([a, b, c], &to_float/1)
      _unreadable -> nil
    end
  end

  @doc "Parses `sysctl -n vm.swapusage` (`... used = 8028.50M ...`) into MB."
  @spec parse_macos_swap(binary()) :: float() | nil
  def parse_macos_swap(text) do
    case Regex.run(~r/used = ([\d.]+)([KMG])/, text) do
      [_, value, unit] ->
        to_float(value) * Map.fetch!(%{"K" => 1 / 1024, "M" => 1, "G" => 1024}, unit)

      nil ->
        nil
    end
  end

  @doc "Parses `/proc/meminfo` into swap used in MB."
  @spec parse_linux_swap(binary()) :: float() | nil
  def parse_linux_swap(text) do
    with [_, total] <- Regex.run(~r/SwapTotal:\s+(\d+) kB/, text),
         [_, free] <- Regex.run(~r/SwapFree:\s+(\d+) kB/, text) do
      (String.to_integer(total) - String.to_integer(free)) / 1024
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

  defp swap_used_mb do
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
