defmodule Mix.Tasks.Cadence.Questdb.Smoke do
  @moduledoc """
  Runs a live QuestDB telemetry storage smoke check.

  The task applies pending QuestDB SQL migrations through the REST `/exec` API,
  writes one telemetry observation, reads bounded history, reads native
  decimation, reads a watermark, and fails if any part of the round trip is not
  visible.

  ## Usage

      mix cadence.questdb.smoke

  ## Options

    * `--http-endpoint` - QuestDB HTTP endpoint, defaults to `http://127.0.0.1:9000`
    * `--host` - retained for future PGWire support
    * `--port` - retained for future PGWire support
    * `--database` - database name, defaults to `qdb`
    * `--username` - username, defaults to `admin`
    * `--password` - password, defaults to `quest`
    * `--organization-id` - smoke organization id
    * `--mission-id` - smoke mission id
    * `--point-id` - smoke point id
    * `--data-source-id` - data source id filter
    * `--binding-id` - source binding id
    * `--help`, `-h` - show this help
  """

  use Mix.Task

  alias Cadence.Telemetry.Storage.QuestDB.Smoke

  @shortdoc "Smoke-test live QuestDB telemetry storage"

  @impl true
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          host: :string,
          http_endpoint: :string,
          port: :integer,
          database: :string,
          username: :string,
          password: :string,
          organization_id: :string,
          mission_id: :string,
          point_id: :string,
          data_source_id: :string,
          binding_id: :string,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    maybe_handle_help_or_invalid_opts(opts, remaining, invalid)

    case Smoke.run(smoke_opts(opts)) do
      {:ok, result} ->
        Mix.shell().info("""
        QuestDB smoke check passed.
        sample_id: #{result.sample_id}
        mission_id: #{result.mission_id}
        point_id: #{result.point_id}
        value: #{result.value}
        bounded_history_count: #{result.bounded_history_count}
        decimated_bucket_count: #{result.decimated_bucket_count}
        watermark_sample_count: #{result.watermark.sample_count}
        applied_migrations: #{length(result.applied_migrations)}
        """)

      {:error, reason} ->
        Mix.raise("QuestDB smoke check failed: #{inspect(reason)}")
    end
  end

  defp maybe_handle_help_or_invalid_opts(opts, remaining, invalid) do
    if opts[:help] || invalid != [] || remaining != [] do
      Mix.shell().info(@moduledoc)
      maybe_raise_invalid_opts(invalid)
      maybe_raise_remaining_args(remaining)
      System.halt(0)
    end
  end

  defp maybe_raise_invalid_opts([]), do: :ok
  defp maybe_raise_invalid_opts(invalid), do: Mix.raise("Invalid options: #{inspect(invalid)}")

  defp maybe_raise_remaining_args([]), do: :ok

  defp maybe_raise_remaining_args(remaining),
    do: Mix.raise("Unexpected arguments: #{inspect(remaining)}")

  defp smoke_opts(opts) do
    [
      hostname: opts[:host],
      http_endpoint: opts[:http_endpoint],
      port: opts[:port],
      database: opts[:database],
      username: opts[:username],
      password: opts[:password],
      organization_id: opts[:organization_id],
      mission_id: opts[:mission_id],
      point_id: opts[:point_id],
      data_source_id: opts[:data_source_id],
      binding_id: opts[:binding_id]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
