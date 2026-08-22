# Seed packet definitions for testing
# Run with: mix run priv/repo/seeds/packet_definitions.exs

import Ecto.Query
alias Cadence.Repo
alias Cadence.Telemetry.Packet.{PacketDefinition, PacketItem}

# Mission ID for testing - update this to match your mission
mission_id = "e4bc9d7a-43a4-42f7-9964-6ae3eadb7215"

# Get the organization_id from the mission
mission = Repo.get!(Cadence.Missions.Mission, mission_id)
organization_id = mission.organization_id

IO.puts("Seeding packet definitions for mission: #{mission_id}")

# Delete existing packet definitions for this mission to allow re-seeding
Repo.delete_all(from p in PacketDefinition, where: p.mission_id == ^mission_id)

# HEALTH Packet Definition (APID 100)
{:ok, health_packet} =
  %PacketDefinition{}
  |> PacketDefinition.changeset(%{
    organization_id: organization_id,
    mission_id: mission_id,
    name: "HEALTH",
    description: "Spacecraft health and status telemetry",
    apid: 100,
    packet_type: "telemetry",
    is_big_endian: true
  })
  |> Repo.insert()

IO.puts("Created HEALTH packet definition (APID 100)")

# HEALTH Packet Items
health_items = [
  %{
    name: "CPU_TEMP",
    description: "CPU temperature in Celsius",
    bit_offset: 0,
    bit_size: 32,
    data_type: "float",
    units: "°C",
    display_order: 1
  },
  %{
    name: "BATTERY_VOLTAGE",
    description: "Battery voltage",
    bit_offset: 32,
    bit_size: 32,
    data_type: "float",
    units: "V",
    display_order: 2
  },
  %{
    name: "BATTERY_CURRENT",
    description: "Battery current",
    bit_offset: 64,
    bit_size: 32,
    data_type: "float",
    units: "A",
    display_order: 3
  },
  %{
    name: "BATTERY_PERCENTAGE",
    description: "Battery charge percentage",
    bit_offset: 96,
    bit_size: 8,
    data_type: "uint",
    units: "%",
    display_order: 4
  },
  %{
    name: "UPTIME_SECONDS",
    description: "System uptime in seconds",
    bit_offset: 104,
    bit_size: 32,
    data_type: "uint",
    units: "s",
    display_order: 5
  },
  %{
    name: "MEMORY_USED_MB",
    description: "Memory used in megabytes",
    bit_offset: 136,
    bit_size: 16,
    data_type: "uint",
    units: "MB",
    display_order: 6
  }
]

Enum.each(health_items, fn item_attrs ->
  %PacketItem{}
  |> PacketItem.changeset(Map.put(item_attrs, :packet_definition_id, health_packet.id))
  |> Repo.insert!()

  IO.puts("  - Created item: #{item_attrs.name}")
end)

# ATTITUDE Packet Definition (APID 101)
{:ok, attitude_packet} =
  %PacketDefinition{}
  |> PacketDefinition.changeset(%{
    organization_id: organization_id,
    mission_id: mission_id,
    name: "ATTITUDE",
    description: "Spacecraft attitude and rotation telemetry",
    apid: 101,
    packet_type: "telemetry",
    is_big_endian: true
  })
  |> Repo.insert()

IO.puts("Created ATTITUDE packet definition (APID 101)")

# ATTITUDE Packet Items
attitude_items = [
  %{
    name: "ROLL",
    description: "Roll angle",
    bit_offset: 0,
    bit_size: 32,
    data_type: "float",
    units: "deg",
    display_order: 1
  },
  %{
    name: "PITCH",
    description: "Pitch angle",
    bit_offset: 32,
    bit_size: 32,
    data_type: "float",
    units: "deg",
    display_order: 2
  },
  %{
    name: "YAW",
    description: "Yaw angle",
    bit_offset: 64,
    bit_size: 32,
    data_type: "float",
    units: "deg",
    display_order: 3
  },
  %{
    name: "ROLL_RATE",
    description: "Roll rate",
    bit_offset: 96,
    bit_size: 32,
    data_type: "float",
    units: "deg/s",
    display_order: 4
  },
  %{
    name: "PITCH_RATE",
    description: "Pitch rate",
    bit_offset: 128,
    bit_size: 32,
    data_type: "float",
    units: "deg/s",
    display_order: 5
  },
  %{
    name: "YAW_RATE",
    description: "Yaw rate",
    bit_offset: 160,
    bit_size: 32,
    data_type: "float",
    units: "deg/s",
    display_order: 6
  }
]

Enum.each(attitude_items, fn item_attrs ->
  %PacketItem{}
  |> PacketItem.changeset(Map.put(item_attrs, :packet_definition_id, attitude_packet.id))
  |> Repo.insert!()

  IO.puts("  - Created item: #{item_attrs.name}")
end)

# POWER Packet Definition (APID 102)
{:ok, power_packet} =
  %PacketDefinition{}
  |> PacketDefinition.changeset(%{
    organization_id: organization_id,
    mission_id: mission_id,
    name: "POWER",
    description: "Spacecraft power system telemetry",
    apid: 102,
    packet_type: "telemetry",
    is_big_endian: true
  })
  |> Repo.insert()

IO.puts("Created POWER packet definition (APID 102)")

# POWER Packet Items
power_items = [
  %{
    name: "SOLAR_PANEL_VOLTAGE",
    description: "Solar panel voltage",
    bit_offset: 0,
    bit_size: 32,
    data_type: "float",
    units: "V",
    display_order: 1
  },
  %{
    name: "SOLAR_PANEL_CURRENT",
    description: "Solar panel current",
    bit_offset: 32,
    bit_size: 32,
    data_type: "float",
    units: "A",
    display_order: 2
  },
  %{
    name: "BUS_VOLTAGE",
    description: "Power bus voltage",
    bit_offset: 64,
    bit_size: 32,
    data_type: "float",
    units: "V",
    display_order: 3
  },
  %{
    name: "BUS_CURRENT",
    description: "Power bus current",
    bit_offset: 96,
    bit_size: 32,
    data_type: "float",
    units: "A",
    display_order: 4
  },
  %{
    name: "POWER_MODE",
    description: "Power mode (0=nominal, 1=battery, 2=charging)",
    bit_offset: 128,
    bit_size: 8,
    data_type: "uint",
    display_order: 5
  }
]

Enum.each(power_items, fn item_attrs ->
  %PacketItem{}
  |> PacketItem.changeset(Map.put(item_attrs, :packet_definition_id, power_packet.id))
  |> Repo.insert!()

  IO.puts("  - Created item: #{item_attrs.name}")
end)

IO.puts("\n✓ Packet definitions seeded successfully!")
IO.puts("  - HEALTH (APID 100): #{length(health_items)} items")
IO.puts("  - ATTITUDE (APID 101): #{length(attitude_items)} items")
IO.puts("  - POWER (APID 102): #{length(power_items)} items")
