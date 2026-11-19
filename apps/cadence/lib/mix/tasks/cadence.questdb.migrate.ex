defmodule Mix.Tasks.Cadence.Questdb.Migrate do
  @moduledoc """
  Applies Cadence-managed QuestDB schema migrations through the REST `/exec`
  API.

  ## Usage

      mix cadence.questdb.migrate
      mix cadence.questdb.migrate --plan
      mix cadence.questdb.migrate --check

  ## Options

    * `--plan` - print local migration files without connecting to QuestDB
    * `--check` - read-only: exit 0 if QuestDB's schema is current for this build, 1 if it is
      behind (missing columns, unapplied migrations, or no table yet: run this task before
      restarting), 2 if the schema can't be read. Sends only `SELECT`s. A restart's pre-flight
      runs it. Every line names the endpoint it checked.

  Applying waits until QuestDB has applied the WAL (the check above passes), so the task never
  returns before the new columns are visible.
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
          check: :boolean,
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

    cond do
      opts[:plan] -> print_plan!(migrations_path)
      opts[:check] -> check!(migrations_path, opts)
      true -> apply_pending!(migrations_path, opts)
    end
  end

  @doc false
  # The exit status and message for a `SchemaMigrator.check/1` result (`--check`).
  # `endpoint` names the QuestDB checked (qa, #483: with no env set it's the default :9000).
  @spec check_report(SchemaMigrator.check_result(), binary()) :: {0 | 1 | 2, binary()}
  def check_report(result, endpoint) do
    {status, message} = check_report(result)
    {status, "QuestDB at #{endpoint}: #{message}"}
  end

  defp check_report(:ok), do: {0, "schema is current for this build."}

  defp check_report({:behind, %{missing_columns: missing, pending_migrations: pending}}) do
    {1,
     "schema is behind this build: missing columns #{list(missing)}; " <>
       "unapplied migrations #{list(pending)}. Run mix cadence.questdb.migrate before restarting."}
  end

  defp check_report({:error, reason}),
    do: {2, "could not read the schema: #{inspect(reason)}"}

  defp list([]), do: "none"
  defp list(items), do: Enum.join(items, ", ")

  defp check!(migrations_path, opts) do
    migrator_opts = migrator_opts(migrations_path, opts)

    {status, message} =
      migrator_opts
      |> SchemaMigrator.check()
      |> check_report(endpoint(migrator_opts))

    if status == 0 do
      Mix.shell().info(message)
    else
      Mix.shell().error(message)
      exit({:shutdown, status})
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

  defp migrator_opts(migrations_path, opts) do
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
  end

  defp apply_pending!(migrations_path, opts) do
    migrator_opts = migrator_opts(migrations_path, opts)
    endpoint = endpoint(migrator_opts)

    case SchemaMigrator.apply_pending(migrator_opts) do
      {:ok, migrations} ->
        Enum.each(migrations, fn migration ->
          Mix.shell().info("Applied QuestDB migration #{migration.version} #{migration.name}.")
        end)

        await_applied!(migrator_opts, endpoint)

      {:error, reason} ->
        Mix.raise("Failed to apply QuestDB migrations at #{endpoint}: #{inspect(reason)}")
    end
  end

  # qa (#483): QuestDB returns before the WAL applies an ALTER, so wait until the schema reads
  # as current before saying so.
  defp await_applied!(migrator_opts, endpoint) do
    case SchemaMigrator.await_current(migrator_opts) do
      :ok ->
        Mix.shell().info("QuestDB at #{endpoint}: schema is current for this build.")

      {:error, {:schema_not_current, last}} ->
        Mix.raise(
          "QuestDB at #{endpoint}: migrations were sent but the schema isn't current after " <>
            "waiting: #{inspect(last)}"
        )
    end
  end

  defp endpoint(migrator_opts),
    do: SchemaMigrator.connection_config(migrator_opts)[:http_endpoint]
end
