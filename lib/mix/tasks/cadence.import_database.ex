defmodule Mix.Tasks.Cadence.ImportDatabase do
  @moduledoc """
  Imports a telemetry database from a YAML file into Cadence.

  ## Usage

      mix cadence.import_database --mission-id <uuid> --file <path.yaml> [options]

  ## Required Options

    * `--mission-id`, `-m` - UUID of the mission to import into
    * `--file`, `-f` - Path to the YAML database file

  ## Optional

    * `--version`, `-v` - Version string (default: read from YAML or "1.0.0")
    * `--publish`, `-p` - Publish the version immediately after import
    * `--help`, `-h` - Show this help

  ## Examples

      # Import a database file
      mix cadence.import_database -m a1b2c3d4-... -f priv/databases/spacecraft_v1.yaml

      # Import with explicit version
      mix cadence.import_database -m a1b2c3d4-... -f db.yaml -v "2.0.0"

      # Import and publish immediately
      mix cadence.import_database -m a1b2c3d4-... -f db.yaml --publish

  ## YAML Format

  ```yaml
  version: "1.0.0"
  description: "Initial telemetry database"
  packets:
    - name: HEALTH
      apid: 100
      description: "Health telemetry"
      items:
        - name: cpu_temp
          bit_offset: 0
          bit_size: 32
          data_type: float
          endianness: big
          units: "°C"
  ```
  """

  use Mix.Task

  @shortdoc "Import a telemetry database from YAML"

  @impl Mix.Task
  def run(args) do
    {opts, _remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          mission_id: :string,
          file: :string,
          version: :string,
          publish: :boolean,
          help: :boolean
        ],
        aliases: [
          m: :mission_id,
          f: :file,
          v: :version,
          p: :publish,
          h: :help
        ]
      )

    if opts[:help] || invalid != [] do
      print_help()
      if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")
      System.halt(0)
    end

    # Validate required options
    mission_id = validate_mission_id!(opts)
    file_path = validate_file!(opts)

    # Start the application
    Mix.Task.run("app.start")

    # Get the mission
    mission = get_mission!(mission_id)

    Mix.shell().info("Importing telemetry database...")
    Mix.shell().info("  Mission: #{mission.name} (#{mission.id})")
    Mix.shell().info("  File: #{file_path}")

    if opts[:version] do
      Mix.shell().info("  Version: #{opts[:version]}")
    end

    # Import the file
    import_opts = if opts[:version], do: [version: opts[:version]], else: []

    case Cadence.Telemetry.Database.YamlImporter.import_file(mission, file_path, import_opts) do
      {:ok, definition_set} ->
        Mix.shell().info("")
        Mix.shell().info("✓ Import successful!")
        Mix.shell().info("  Version: #{definition_set.version}")
        Mix.shell().info("  Packets: #{length(definition_set.packet_definitions)}")

        total_items =
          definition_set.packet_definitions
          |> Enum.map(fn pd -> length(pd.packet_items) end)
          |> Enum.sum()

        Mix.shell().info("  Items: #{total_items}")

        # Publish if requested
        if opts[:publish] do
          case Cadence.Telemetry.Database.DefinitionSet.publish(definition_set) do
            {:ok, published} ->
              Mix.shell().info("")
              Mix.shell().info("✓ Published version #{published.version}")

            {:error, reason} ->
              Mix.shell().error("Failed to publish: #{inspect(reason)}")
              System.halt(1)
          end
        else
          Mix.shell().info("")
          Mix.shell().info("Note: Version not published. Use --publish flag or publish manually.")
        end

      {:error, {:yaml_parse_error, reason}} ->
        Mix.shell().error("YAML parse error: #{inspect(reason)}")
        System.halt(1)

      {:error, {:validation_error, message}} ->
        Mix.shell().error("Validation error: #{message}")
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("Import failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp validate_mission_id!(opts) do
    case opts[:mission_id] do
      nil ->
        Mix.raise("Missing required option: --mission-id")

      id ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> Mix.raise("Invalid mission ID format. Expected UUID, got: #{id}")
        end
    end
  end

  defp validate_file!(opts) do
    case opts[:file] do
      nil ->
        Mix.raise("Missing required option: --file")

      path ->
        if File.exists?(path) do
          path
        else
          Mix.raise("File not found: #{path}")
        end
    end
  end

  defp get_mission!(mission_id) do
    try do
      Cadence.Missions.get_mission!(mission_id)
    rescue
      Ecto.NoResultsError -> Mix.raise("Mission not found: #{mission_id}")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.import_database - Import a telemetry database from YAML

    Usage:
      mix cadence.import_database [options]

    Required Options:
      --mission-id, -m <uuid>    Mission UUID to import into
      --file, -f <path>          Path to YAML database file

    Optional:
      --version, -v <string>     Version string (default: from YAML or "1.0.0")
      --publish, -p              Publish the version immediately
      --help, -h                 Show this help

    Examples:
      mix cadence.import_database -m a1b2c3d4-... -f priv/databases/db.yaml
      mix cadence.import_database -m a1b2c3d4-... -f db.yaml -v "2.0.0" --publish
    """)
  end
end
