defmodule Mix.Tasks.Cadence.Telemetry.Replay do
  @moduledoc """
  Quick helper to stream a slice of persisted telemetry logs for inspection.

  ## Examples

      mix cadence.telemetry.replay --mission M1 --lane payload --shard 0 --count 5 --direction head
      mix cadence.telemetry.replay --mission M1 --lane payload --shard 0 --count 5 --direction tail
  """

  use Mix.Task

  @shortdoc "Print a head/tail slice of a shard log"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse!(args,
        switches: [
          mission: :string,
          lane: :string,
          shard: :integer,
          count: :integer,
          direction: :string,
          base_dir: :string
        ]
      )

    mission = Keyword.fetch!(opts, :mission)
    lane = Keyword.get(opts, :lane, "payload")
    shard = Keyword.fetch!(opts, :shard)
    count = Keyword.get(opts, :count, 10)
    direction = Keyword.get(opts, :direction, "head")
    base_dir = Keyword.get(opts, :base_dir, default_base_dir())

    paths = build_paths(base_dir, mission, lane, shard)

    if paths == [] do
      Mix.shell().error("Log not found for shard #{shard} in #{base_dir}")
      Mix.shell().info("Ensure the lanes pipeline is running and emitting to the file sink.")
      System.halt(1)
    end

    lines =
      paths
      |> Enum.flat_map(&File.stream!/1)
      |> slice(direction, count)

    decoded =
      lines
      |> Enum.map(&decode_line/1)
      |> Enum.map(fn env ->
        %{
          mission_id: env.mission_id,
          lane: env.lane,
          shard_id: env.shard_id,
          target: env.target_id,
          apid: env.apid,
          router_version: env.router_version,
          config_version: env.config_version,
          sequence: env.sequence,
          items: env.payload
        }
      end)

    Mix.shell().info("Showing #{length(decoded)} records from #{Enum.join(paths, ", ")}:")
    IO.puts(Enum.map_join(decoded, "\n", &inspect/1))
  end

  defp slice(list, "head", count), do: Enum.take(list, count)

  defp slice(list, "tail", count),
    do: list |> Enum.reverse() |> Enum.take(count) |> Enum.reverse()

  defp slice(list, _, count), do: Enum.take(list, count)

  defp decode_line(line) do
    line
    |> String.trim_trailing()
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end

  defp build_paths(base_dir, mission, lane, shard) do
    base_path = Path.join([base_dir, mission, lane])

    segment_paths =
      base_path
      |> Path.join("#{shard}-*.log")
      |> Path.wildcard()
      |> Enum.sort()

    if segment_paths != [] do
      segment_paths
    else
      path = Path.join(base_path, "#{shard}.log")

      if File.exists?(path) do
        [path]
      else
        []
      end
    end
  end

  defp default_base_dir do
    Path.join([File.cwd!(), "priv", "telemetry_logs"])
  end
end
