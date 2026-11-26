defmodule Mix.Tasks.CadenceSimulator.Load do
  use Mix.Task

  @default_output Path.expand("../../../../../var/simulator-load.jsonl", __DIR__)

  @shortdoc "Measure simulator TCP throughput and scheduler use"
  @moduledoc """
  Run a simulator-only load test and write one JSON object per measured second.

      mix cadence_simulator.load --craft 1000 --shape peak --duration 600

  Options include `--per-site 8|16` for the average shape and
  `--output PATH` for the per-path JSONL results.
  """

  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("Run the simulator load test with MIX_ENV=dev")

    case OptionParser.parse(args,
           strict: [
             craft: :integer,
             shape: :string,
             duration: :integer,
             per_site: :integer,
             output: :string
           ]
         ) do
      {opts, [], []} -> execute(opts)
      _invalid -> Mix.raise(@moduledoc)
    end
  end

  defp execute(opts) do
    config = %{
      craft: Keyword.get(opts, :craft, 1000),
      shape: Keyword.get(opts, :shape, "peak"),
      duration: Keyword.get(opts, :duration, 600),
      per_site: Keyword.get(opts, :per_site, 8),
      output: Keyword.get(opts, :output, @default_output)
    }

    if config.duration < 1, do: Mix.raise("--duration must be a positive number of seconds")

    Mix.Task.run("app.config")

    with :ok <- CadenceSimulator.Load.Shape.validate(config.craft, config.shape, config.per_site),
         :ok <- CadenceSimulator.Load.run(config) do
      :ok
    else
      {:error, reason} -> Mix.raise(reason)
    end
  end
end
