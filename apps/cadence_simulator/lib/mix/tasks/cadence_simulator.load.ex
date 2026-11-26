defmodule Mix.Tasks.CadenceSimulator.Load do
  use Mix.Task

  alias CadenceSimulator.Load
  alias CadenceSimulator.Load.Shape

  @default_output Path.expand("../../../../../var/simulator-load.jsonl", __DIR__)

  @shortdoc "Measure simulator TCP throughput and scheduler use"
  @moduledoc """
  Run a simulator-only load test and write one JSON object per measured second.

      mix cadence_simulator.load --craft 1000 --shape peak --duration 600

  Options include `--per-site 8|16` for the average shape and
  `--output PATH` for the per-path JSONL results. Use `--binary-owners` to include
  per-process binary references in the ten-second diagnostics.
  """

  @impl true
  def run(args), do: run(args, nil)

  @doc false
  def run(args, target) do
    if Mix.env() != :dev, do: Mix.raise("Run the simulator load test with MIX_ENV=dev")

    case OptionParser.parse(args,
           strict: [
             craft: :integer,
             shape: :string,
             duration: :integer,
             per_site: :integer,
             output: :string,
             binary_owners: :boolean
           ]
         ) do
      {opts, [], []} -> execute(opts, target)
      _invalid -> Mix.raise(@moduledoc)
    end
  end

  defp execute(opts, target) do
    config = %{
      craft: Keyword.get(opts, :craft, 1000),
      shape: Keyword.get(opts, :shape, "peak"),
      duration: Keyword.get(opts, :duration, 600),
      per_site: Keyword.get(opts, :per_site, 8),
      output: Keyword.get(opts, :output, @default_output),
      binary_owners?: Keyword.get(opts, :binary_owners, false)
    }

    if config.duration < 1, do: Mix.raise("--duration must be a positive number of seconds")

    Mix.Task.run("app.config")

    result =
      with :ok <- Shape.validate(config.craft, config.shape, config.per_site) do
        Load.run(config, target)
      end

    case result do
      {:error, reason} -> Mix.raise(reason)
      success -> success
    end
  end
end
