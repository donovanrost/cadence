defmodule Cadence.Telemetry.Storage.QuestDB.SchemaMigrator do
  @moduledoc """
  Minimal schema migrator for Cadence-managed QuestDB databases.

  QuestDB is not managed through Ecto migrations. This migrator applies
  timestamp-prefixed SQL files from `priv/questdb/migrations` through QuestDB's
  REST `/exec` API and records applied versions in QuestDB itself.
  """

  @schema_migrations_table "cadence_schema_migrations"
  @migration_filename_regex ~r/^(\d{14})_(.+)\.sql$/

  @type migration :: %{
          version: binary(),
          name: binary(),
          path: binary(),
          sql: binary(),
          checksum: binary()
        }

  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @type connection_config :: [
          hostname: binary(),
          port: pos_integer(),
          database: binary(),
          username: binary(),
          password: binary(),
          timeout: pos_integer(),
          http_endpoint: binary()
        ]

  @spec default_migrations_path() :: binary()
  def default_migrations_path do
    :cadence
    |> :code.priv_dir()
    |> Path.join("questdb/migrations")
  end

  @spec connection_config(keyword()) :: connection_config()
  def connection_config(opts \\ []) when is_list(opts) do
    [
      hostname: Keyword.get(opts, :hostname, env("CADENCE_QUESTDB_HOST", "127.0.0.1")),
      port: Keyword.get(opts, :port, env_integer("CADENCE_QUESTDB_PORT", 8812)),
      database: Keyword.get(opts, :database, env("CADENCE_QUESTDB_DATABASE", "qdb")),
      username: Keyword.get(opts, :username, env("CADENCE_QUESTDB_USERNAME", "admin")),
      password: Keyword.get(opts, :password, env("CADENCE_QUESTDB_PASSWORD", "quest")),
      timeout: Keyword.get(opts, :timeout, 15_000),
      http_endpoint:
        Keyword.get(
          opts,
          :http_endpoint,
          env("CADENCE_QUESTDB_HTTP_ENDPOINT", "http://127.0.0.1:9000")
        )
    ]
  end

  @spec load_migrations(binary()) :: {:ok, [migration()]} | {:error, term()}
  def load_migrations(migrations_path) when is_binary(migrations_path) do
    with {:ok, files} <- migration_files(migrations_path) do
      files
      |> Enum.map(&load_migration/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.version)
      |> then(&{:ok, &1})
    end
  end

  @spec migration_plan(binary(), [binary()]) :: {:ok, [migration()]} | {:error, term()}
  def migration_plan(migrations_path, applied_versions \\ [])
      when is_binary(migrations_path) and is_list(applied_versions) do
    with {:ok, migrations} <- load_migrations(migrations_path) do
      applied = MapSet.new(applied_versions)
      {:ok, Enum.reject(migrations, &MapSet.member?(applied, &1.version))}
    end
  end

  @spec apply_pending(keyword()) :: {:ok, [migration()]} | {:error, term()}
  def apply_pending(opts \\ []) when is_list(opts) do
    migrations_path = Keyword.get(opts, :migrations_path, default_migrations_path())

    with :ok <- ensure_schema_migrations_table(opts),
         {:ok, applied_versions} <- applied_versions(opts),
         {:ok, pending} <- migration_plan(migrations_path, applied_versions),
         :ok <- apply_migrations(opts, pending) do
      {:ok, pending}
    end
  end

  @spec applied_versions(keyword()) :: {:ok, [binary()]} | {:error, term()}
  def applied_versions(opts \\ []) when is_list(opts) do
    case exec("SELECT version FROM #{@schema_migrations_table}", opts) do
      {:ok, %{"dataset" => rows}} ->
        {:ok, Enum.map(rows, fn [version] -> version end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp migration_files(migrations_path) do
    case File.ls(migrations_path) do
      {:ok, filenames} ->
        files =
          filenames
          |> Enum.filter(&String.ends_with?(&1, ".sql"))
          |> Enum.map(&Path.join(migrations_path, &1))

        {:ok, files}

      {:error, reason} ->
        {:error, {:migrations_path_unavailable, migrations_path, reason}}
    end
  end

  defp load_migration(path) do
    basename = Path.basename(path)

    with [_, version, name] <- Regex.run(@migration_filename_regex, basename),
         {:ok, sql} <- File.read(path) do
      %{
        version: version,
        name: name,
        path: path,
        sql: String.trim(sql),
        checksum: checksum(sql)
      }
    else
      _other -> nil
    end
  end

  defp ensure_schema_migrations_table(opts) do
    sql = """
    CREATE TABLE IF NOT EXISTS #{@schema_migrations_table} (
      applied_at TIMESTAMP,
      version STRING,
      name STRING,
      checksum STRING
    ) TIMESTAMP(applied_at) PARTITION BY YEAR WAL;
    """

    case exec(sql, opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_migrations(opts, migrations) do
    Enum.reduce_while(migrations, :ok, fn migration, :ok ->
      case apply_migration(opts, migration) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:migration_failed, migration.version, reason}}}
      end
    end)
  end

  defp apply_migration(opts, migration) do
    insert_sql = """
    INSERT INTO #{@schema_migrations_table}
    VALUES(
      #{sql_literal(DateTime.utc_now())},
      #{sql_literal(migration.version)},
      #{sql_literal(migration.name)},
      #{sql_literal(migration.checksum)}
    )
    """

    with {:ok, _result} <- exec(migration.sql, opts),
         {:ok, _result} <- exec(insert_sql, opts) do
      :ok
    end
  end

  defp exec(sql, opts) do
    exec_fun = Keyword.get(opts, :exec_fun, &RestClient.exec/2)
    exec_fun.(sql, opts)
  end

  defp sql_literal(value), do: SQL.literal(value)

  defp checksum(sql) do
    :sha256
    |> :crypto.hash(sql)
    |> Base.encode16(case: :lower)
  end

  defp env(name, default) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> integer
          _other -> default
        end

      _other ->
        default
    end
  end
end
