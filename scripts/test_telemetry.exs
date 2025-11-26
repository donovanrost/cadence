# Script to set up and test the telemetry pipeline
# Run with: mix run scripts/test_telemetry.exs

alias Cadence.{Accounts, Organizations, Missions, Targets, Repo}
alias Cadence.Missions.MissionSupervisor
alias Cadence.Simulator.PacketSimulator
alias Cadence.Telemetry.{CurrentValueTable, Pipeline}

IO.puts("\n🚀 Cadence Telemetry Pipeline Test\n")

# 1. Create organization
IO.puts("1. Creating test organization...")
{:ok, org} = Organizations.create_organization(%{
  name: "Test Org",
  slug: "test-org-#{System.unique_integer([:positive])}",
  status: "active",
  subscription_tier: "pro"
})
IO.puts("   ✅ Organization created: #{org.name} (#{org.id})")

# 2. Create test user with organization membership
IO.puts("\n2. Creating test user...")
{:ok, user} = Accounts.register_user(%{
  email: "test-#{System.unique_integer([:positive])}@example.com",
  organization_id: org.id,
  role: "admin"
})
IO.puts("   ✅ User created: #{user.email} (#{user.id})")

# 3. Create mission with creator (auto-creates mission_membership)
IO.puts("\n3. Creating test mission...")
{:ok, mission} = Missions.create_mission(%{
  organization_id: org.id,
  name: "Test Mission",
  slug: "test-mission-#{System.unique_integer([:positive])}",
  description: "Telemetry pipeline test",
  status: "active",
  creator_user_id: user.id
})
IO.puts("   ✅ Mission created: #{mission.name} (#{mission.id})")

# 4. Create targets
IO.puts("\n4. Creating targets...")
target_configs = [
  %{identifier: "SAT-1", name: "Satellite 1"},
  %{identifier: "SAT-2", name: "Satellite 2"},
  %{identifier: "SAT-3", name: "Satellite 3"}
]

Enum.each(target_configs, fn config ->
  {:ok, _target} = Targets.create_target(%{
    mission_id: mission.id,
    name: config.name,
    identifier: config.identifier,
    type: "spacecraft",
    status: "online"
  })
end)

target_ids = ["SAT-1", "SAT-2", "SAT-3"]  # Use uppercase for simulator
IO.puts("   ✅ Created 3 targets: #{Enum.join(target_ids, ", ")}")

# 5. Start mission (starts CVT, PacketIdentifier, Pipeline)
IO.puts("\n5. Starting mission runtime...")
{:ok, _pid} = MissionSupervisor.start_mission(mission)
Process.sleep(200) # Give processes time to initialize
IO.puts("   ✅ Mission runtime started")

# 6. Start packet simulator
IO.puts("\n6. Starting packet simulator...")
{:ok, sim_pid} = PacketSimulator.start_link(
  mission_id: mission.id,
  targets: target_ids,
  packet_types: [:health, :attitude, :power],
  rate_hz: 2.0,  # 2 packets per second
  output: nil     # PubSub only
)
IO.puts("   ✅ Simulator started (generating packets at 2 Hz)")

# 7. Wait and show telemetry
IO.puts("\n7. Waiting for telemetry packets...")
Process.sleep(2000)

# 8. Check pipeline stats
IO.puts("\n8. Pipeline Statistics:")
stats = Pipeline.stats(mission.id)
IO.puts("   Packets processed: #{stats.packets_processed}")
IO.puts("   Items processed: #{stats.items_processed}")
IO.puts("   Errors: #{stats.errors}")

# 9. Show some telemetry values
IO.puts("\n9. Sample Telemetry Values:")
{:ok, cpu_temp} = CurrentValueTable.get(mission.id, "SAT-1", "HEALTH", "cpu_temp")
IO.puts("   SAT-1 CPU Temp: #{Float.round(cpu_temp.value, 2)}°C")

{:ok, roll} = CurrentValueTable.get(mission.id, "SAT-2", "ATTITUDE", "roll")
IO.puts("   SAT-2 Roll: #{Float.round(roll.value, 2)}°")

{:ok, bus_voltage} = CurrentValueTable.get(mission.id, "SAT-3", "POWER", "bus_voltage")
IO.puts("   SAT-3 Bus Voltage: #{Float.round(bus_voltage.value, 2)} V")

# 10. CVT stats
cvt_stats = CurrentValueTable.stats(mission.id)
IO.puts("\n10. CVT Statistics:")
IO.puts("   Total entries: #{cvt_stats.total_entries}")
IO.puts("   Memory (bytes): #{cvt_stats.memory_bytes}")

IO.puts("\n✅ Test complete!")
IO.puts("\n📊 View live telemetry at:")
IO.puts("   http://localhost:4000/missions/#{mission.id}/telemetry")
IO.puts("\n👤 Test User Credentials:")
IO.puts("   Email: #{user.email}")
IO.puts("   (Create password via magic link login)")
IO.puts("\nℹ️  Simulator will keep running. To stop:")
IO.puts("   GenServer.stop(#{inspect(sim_pid)})")
IO.puts("   MissionSupervisor.stop_mission(\"#{mission.id}\")")
