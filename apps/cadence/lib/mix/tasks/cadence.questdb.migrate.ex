defmodule Mix.Tasks.Cadence.Questdb.Migrate do
  @moduledoc """
  Applies Cadence-managed QuestDB schema migrations through the REST `/exec`
  API.

  ## Usage

      mix cadence.questdb.migrate
      mix cadence.questdb.migrate --plan

  ## Options

    * `--plan` - print local migration files without connecting to QuestDB
    * `--migrations-path` - override the SQL migrations directory
    * `--http-endpoint` - QuestDB HTTP endpoint, defaults to `http://127.0.0.1:9000`
    * `--host` - retained for future PGWire support
    * `--port` - retained for future PGWire support
    * `--database` - database name, defaults to `qdb`
    * `--username` - username, defaults to `admin`
    * `--password` - password, defaults to `quest`
    * `--help`, `-h` - show this help
  """

  use Mix.Task

  alias Cadence.Telemetry.Storage.QuestDB.SchemaMigrator

  @shortdoc "Apply Cadence QuestDB schema migrations"

  @impl true
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          plan: :boolean,
          migrations_path: :string,
          http_endpoint: :string,
          host: :string,
          port: :integer,
          database: :string,
          username: :string,
          password: :string,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    maybe_handle_help_or_invalid_opts(opts, remaining, invalid)

    migrations_path = opts[:migrations_path] || SchemaMigrator.default_migrations_path()

    if opts[:plan] do
      print_plan!(migrations_path)
    else
      apply_pending!(migrations_path, opts)
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

  defp print_plan!(migrations_path) do
    case SchemaMigrator.migration_plan(migrations_path) do
      {:ok, []} ->
        Mix.shell().info("No QuestDB migrations found.")

      {:ok, migrations} ->
        Enum.each(migrations, fn migration ->
          Mix.shell().info("#{migration.version} #{migration.name}")
        end)

      {:error, reason} ->
        Mix.raise("Failed to read QuestDB migrations: #{inspect(reason)}")
    end
  end

  defp apply_pending!(migrations_path, opts) do
    migrator_opts =
      [
        migrations_path: migrations_path,
        http_endpoint: opts[:http_endpoint],
        hostname: opts[:host],
        port: opts[:port],
        database: opts[:database],
        username: opts[:username],
        password: opts[:password]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case SchemaMigrator.apply_pending(migrator_opts) do
      {:ok, []} ->
        Mix.shell().info("QuestDB schema is up to date.")

      {:ok, migrations} ->
        Enum.each(migrations, fn migration ->
          Mix.shell().info("Applied QuestDB migration #{migration.version} #{migration.name}.")
        end)

      {:error, reason} ->
        Mix.raise("Failed to apply QuestDB migrations: #{inspect(reason)}")
    end
  end
end
