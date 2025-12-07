defmodule Mix.Tasks.Cadence.StressDerived do
  @moduledoc """
  Creates stress test derived items for performance testing.

  ## Usage

      mix cadence.stress_derived --mission-id <uuid> --count 20

  ## Options

    * `--mission-id`, `-m` - Mission UUID (required)
    * `--count`, `-c` - Number of derived items to create (default: 10)
    * `--clear` - Clear existing derived items first
  """

  use Mix.Task

  @shortdoc "Create stress test derived items"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [mission_id: :string, count: :integer, clear: :boolean],
        aliases: [m: :mission_id, c: :count]
      )

    mission_id = opts[:mission_id] || raise "Missing --mission-id"
    count = opts[:count] || 10

    alias Cadence.Repo
    alias Cadence.Missions.Mission
    alias Cadence.Telemetry.Database.DerivedItem
    import Ecto.Query

    # Get mission
    mission = Repo.get!(Mission, mission_id)
    Mix.shell().info("Creating #{count} derived items for mission: #{mission.name}")

    # Clear existing if requested
    if opts[:clear] do
      {deleted, _} =
        from(d in DerivedItem, where: d.mission_id == ^mission_id)
        |> Repo.delete_all()

      Mix.shell().info("Cleared #{deleted} existing derived items")
    end

    # Create derived items in batches
    # Layer 1: Simple calculations on raw telemetry
    layer1_items = [
      {"BATTERY_POWER", "HEALTH.battery_voltage * HEALTH.battery_current", "W"},
      {"TEMP_KELVIN", "HEALTH.cpu_temp + 273.15", "K"},
      {"ROLL_ABS", "abs(ATTITUDE.roll)", "deg"},
      {"PITCH_ABS", "abs(ATTITUDE.pitch)", "deg"},
      {"YAW_ABS", "abs(ATTITUDE.yaw)", "deg"},
      {"SOLAR_POWER", "POWER.solar_panel_voltage * POWER.solar_panel_current", "W"},
      {"BUS_POWER", "POWER.bus_voltage * POWER.bus_current", "W"},
      {"TOTAL_RATE",
       "abs(ATTITUDE.roll_rate) + abs(ATTITUDE.pitch_rate) + abs(ATTITUDE.yaw_rate)", "deg/s"},
      {"UPTIME_HOURS", "HEALTH.uptime_seconds / 3600", "h"},
      {"MEMORY_PERCENT", "HEALTH.memory_used_mb / 1024 * 100", "%"}
    ]

    # Layer 2: Derived from Layer 1 (tests dependency ordering)
    layer2_items = [
      {"POWER_EFFICIENCY", "SOLAR_POWER / max(BUS_POWER, 0.001) * 100", "%"},
      {"ATTITUDE_MAG", "sqrt(ROLL_ABS * ROLL_ABS + PITCH_ABS * PITCH_ABS + YAW_ABS * YAW_ABS)",
       "deg"},
      {"BATTERY_POWER_SCALED", "BATTERY_POWER * 10", "dW"},
      {"TEMP_NORMALIZED", "(TEMP_KELVIN - 273) / 100", ""},
      {"RATE_SEVERITY", "if TOTAL_RATE > 10 then 2 else if TOTAL_RATE > 5 then 1 else 0", ""}
    ]

    # Layer 3: More complex chains
    layer3_items = [
      {"SYSTEM_HEALTH_SCORE", "100 - ATTITUDE_MAG - clamp(TOTAL_RATE, 0, 50)", ""},
      {"POWER_MARGIN", "SOLAR_POWER - BUS_POWER", "W"}
    ]

    all_items = layer1_items ++ layer2_items ++ layer3_items

    # Take requested count
    items_to_create = Enum.take(all_items, count)

    # Create items
    created =
      Enum.with_index(items_to_create, 1)
      |> Enum.map(fn {{name, expression, units}, idx} ->
        case DerivedItem.create(%{
               organization_id: mission.organization_id,
               mission_id: mission_id,
               name: name,
               expression: expression,
               units: units,
               display_order: idx,
               enabled: true
             }) do
          {:ok, item} ->
            Mix.shell().info("  ✓ #{name}")
            item

          {:error, changeset} ->
            errors = inspect(changeset.errors)
            Mix.shell().info("  ✗ #{name}: #{errors}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Mix.shell().info("\nCreated #{length(created)} derived items")
    Mix.shell().info("Run profiler to test performance:")
    Mix.shell().info("  mix cadence.profile -n cadence -m #{mission_id}")
  end
end
