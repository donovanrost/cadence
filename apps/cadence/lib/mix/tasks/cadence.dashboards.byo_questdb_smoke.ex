defmodule Mix.Tasks.Cadence.Dashboards.ByoQuestdbSmoke do
  @moduledoc """
  Runs a live dashboard BYO QuestDB smoke check.

  The task creates or updates a customer-owned dashboard data source, resolves
  its endpoint through the env-profile credential material resolver, migrates
  the external QuestDB schema, writes one observation, probes the source, and
  resolves a dashboard history request against the same external endpoint.

  ## Usage

      mix cadence.dashboards.byo_questdb_smoke

  ## Options

    * `--http-endpoint` - customer QuestDB HTTP endpoint, defaults to `http://127.0.0.1:9100`
    * `--organization-id` - smoke organization id
    * `--mission-id` - smoke mission id
    * `--data-source-id` - smoke data source id
    * `--binding-id` - smoke data binding id
    * `--credentials-ref` - smoke credential reference
    * `--run-id` - smoke run id used to derive default record ids
    * `--point-id` - smoke telemetry point id
    * `--sample-id` - smoke sample id
    * `--value` - smoke integer value
    * `--history-read-attempts` - dashboard read-back attempts, defaults to 5
    * `--history-retry-sleep-ms` - delay between read-back attempts, defaults to 100
    * `--keep-records` - keep Cadence registry/health records after the smoke run for inspection
    * `--help`, `-h` - show this help

  By default, the task uses unique smoke ids and deletes the Cadence-side source,
  binding, credential, health, and generated mission records after the run. It
  does not delete observations written to the external QuestDB endpoint.
  """

  use Mix.Task

  alias Cadence.Dashboards.BYOQuestDBSmoke

  @shortdoc "Smoke-test a dashboard BYO QuestDB source"

  @impl true
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          http_endpoint: :string,
          organization_id: :string,
          mission_id: :string,
          data_source_id: :string,
          binding_id: :string,
          credentials_ref: :string,
          run_id: :string,
          point_id: :string,
          sample_id: :string,
          value: :integer,
          history_read_attempts: :integer,
          history_retry_sleep_ms: :integer,
          keep_records: :boolean,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    maybe_handle_help_or_invalid_opts(opts, remaining, invalid)

    case BYOQuestDBSmoke.run(smoke_opts(opts)) do
      {:ok, result} ->
        Mix.shell().info("""
        Dashboard BYO QuestDB smoke check passed.
        sample_id: #{result.sample_id}
        organization_id: #{result.organization_id}
        mission_id: #{result.mission_id}
        run_id: #{result.run_id}
        data_source_id: #{result.data_source_id}
        binding_id: #{result.binding_id}
        point_id: #{result.point_id}
        value: #{result.value}
        http_endpoint: #{result.http_endpoint}
        source_health: #{result.source_health}
        returned_frame_count: #{result.returned_frame_count}
        cleanup?: #{result.cleanup?}
        applied_migrations: #{length(result.applied_migrations)}
        """)

      {:error, reason} ->
        Mix.raise("Dashboard BYO QuestDB smoke check failed: #{inspect(reason)}")
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
      http_endpoint: opts[:http_endpoint],
      organization_id: opts[:organization_id],
      mission_id: opts[:mission_id],
      data_source_id: opts[:data_source_id],
      binding_id: opts[:binding_id],
      credentials_ref: opts[:credentials_ref],
      run_id: opts[:run_id],
      point_id: opts[:point_id],
      sample_id: opts[:sample_id],
      value: opts[:value],
      history_read_attempts: opts[:history_read_attempts],
      history_retry_sleep_ms: opts[:history_retry_sleep_ms],
      cleanup?: not Keyword.get(opts, :keep_records, false)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
