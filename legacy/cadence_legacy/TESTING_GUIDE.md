# 🧪 Telemetry System Testing Guide

Complete guide to testing the new telemetry system (Phases 1-4).

---

## Quick Test (5 minutes)

### 1. Run Migrations

```bash
cd /Users/donovanrost/Projects/cadence/cadence
mix ecto.migrate
```

### 2. Start IEx

```bash
iex -S mix
```

### 3. Set Up Test Data

```elixir
# Aliases
alias Cadence.{Repo, Missions, Targets, Interfaces}
alias Cadence.Telemetry.{Packet, Conversions, CurrentValueTable}

# Create organization (adjust based on your schema)
org = Repo.insert!(%Cadence.Accounts.Organization{
  name: "Test Org",
  identifier: "TEST"
})

# Create mission
{:ok, mission} = Missions.create_mission(%{
  name: "Test Mission",
  description: "Testing telemetry",
  organization_id: org.id,
  status: "inactive"  # Start inactive
})

# Create target
{:ok, target} = Targets.create_target(%{
  name: "Test Satellite",
  identifier: "SAT-001",
  type: "spacecraft",
  mission_id: mission.id
})

# Create packet definition
{:ok, packet_def} = Packet.create_packet_definition(%{
  name: "HEALTH",
  target_id: target.id,
  mission_id: mission.id,
  type_byte: 1,
  description: "Health telemetry"
})

# Create temperature conversion (°C = -50 + 0.1 * ADC)
{:ok, temp_conv} = Conversions.create_polynomial_conversion(%{
  name: "TEMP_SENSOR",
  mission_id: mission.id,
  coefficients: [-50.0, 0.1]
})

# Create mode state table
{:ok, mode_conv} = Conversions.create_state_table_conversion(%{
  name: "POWER_MODE",
  mission_id: mission.id,
  states: %{"0" => "OFF", "1" => "STANDBY", "2" => "NOMINAL"},
  default_state: "UNKNOWN"
})

# Create packet items
{:ok, _} = Packet.create_packet_item(%{
  packet_definition_id: packet_def.id,
  name: "cpu_temp",
  bit_offset: 0,
  bit_size: 32,
  data_type: "uint",
  endianness: "big_endian",
  conversion_id: temp_conv.id
})

{:ok, _} = Packet.create_packet_item(%{
  packet_definition_id: packet_def.id,
  name: "battery_voltage",
  bit_offset: 32,
  bit_size: 32,
  data_type: "uint",
  endianness: "big_endian"
})

{:ok, _} = Packet.create_packet_item(%{
  packet_definition_id: packet_def.id,
  name: "power_mode",
  bit_offset: 64,
  bit_size: 8,
  data_type: "uint",
  endianness: "big_endian",
  conversion_id: mode_conv.id
})

# Create interface
{:ok, interface} = Interfaces.create_interface(%{
  name: "TCP_TEST",
  connection_type: "tcp_client",
  host: "127.0.0.1",
  port: 9999,
  mission_id: mission.id,
  config: %{"target_id" => target.id}
})

# Link target to interface
{:ok, _} = Interfaces.add_target_to_interface(target, interface, "read")
```

### 4. Activate Mission

```elixir
# This starts all the processes:
# - InterfaceSupervisor
# - Broadway Pipeline
# - PacketIdentifier
# - CVT
{:ok, _} = Missions.activate_mission(mission)

# Wait for startup
Process.sleep(500)
```

### 5. Send Test Telemetry

```elixir
# Build binary packet:
# cpu_temp = 1000 ADC → converts to 50.0°C (-50 + 0.1*1000)
# battery_voltage = 14200 mV (no conversion)
# power_mode = 2 → converts to "NOMINAL"

payload = <<
  1000::32-big-unsigned,   # cpu_temp
  14200::32-big-unsigned,  # battery_voltage
  2::8-unsigned            # power_mode
>>

# Wrap in simulator format
target_id_str = "SAT-001"
target_id_len = byte_size(target_id_str)

packet = <<
  1::8,                     # type_byte (HEALTH)
  target_id_len::8,         # target_id length
  target_id_str::binary,    # target_id
  payload::binary           # payload
>>

# Publish to Broadway
Phoenix.PubSub.broadcast(
  Cadence.PubSub,
  "mission:#{mission.id}:telemetry:raw",
  {:telemetry_packet, packet, %{received_at: DateTime.utc_now(), stored: false}}
)

# Wait for processing
Process.sleep(300)
```

### 6. Verify Results

```elixir
# Check CVT
cvt_data = CurrentValueTable.get_all(mission.id, target.id)

# Should show:
# %{
#   "HEALTH" => %{
#     "cpu_temp" => 50.0,           # ✅ Converted!
#     "battery_voltage" => 14200,    # ✅ Raw value
#     "power_mode" => "NOMINAL"      # ✅ State table!
#   }
# }

IO.inspect(cvt_data, label: "CVT Data")
```

### 7. Clean Up

```elixir
# Deactivate mission
Missions.deactivate_mission(mission.id)

# Clean up test data
Repo.delete(mission)
Repo.delete(org)
```

---

## What You Should See

### ✅ Success Indicators

1. **Mission activation logs:**
   ```
   [info] Starting InterfaceSupervisor for mission <id>
   [info] Starting telemetry pipeline for mission_id=<id>
   [info] Loaded 1 packet definitions for mission_id=<id>
   ```

2. **CVT contains converted values:**
   - `cpu_temp: 50.0` (not 1000)
   - `power_mode: "NOMINAL"` (not 2)

3. **No errors in logs**

### ❌ Troubleshooting

**Problem**: CVT is empty
- **Check**: Did you wait long enough? (Process.sleep(300))
- **Check**: Is the mission activated?
- **Check**: Are there errors in logs?

**Problem**: Values are wrong
- **Check**: Conversions created correctly?
- **Check**: Packet items linked to conversions?
- **Check**: Endianness matches your binary format?

**Problem**: Compilation errors
- **Run**: `mix compile` and check for errors
- **Check**: All migrations ran? `mix ecto.migrate`

---

## Advanced Testing

### Test Different Packet Types

```elixir
# ATTITUDE packet (type_byte = 2)
attitude_payload = <<
  45::32-big-unsigned,   # roll
  -10::32-big-signed,    # pitch
  180::32-big-unsigned   # yaw
>>

# Create ATTITUDE packet definition first...
```

### Test High-Throughput

```elixir
# Send 100 packets rapidly
for i <- 1..100 do
  payload = <<
    (1000 + i)::32-big-unsigned,   # Varying temp
    14200::32-big-unsigned,
    2::8-unsigned
  >>

  # ... build and send packet
  Process.sleep(10)
end

# Check Broadway handled them all
```

### Monitor Broadway Performance

```elixir
# Watch the pipeline process telemetry
:observer.start()

# Look for:
# - Cadence.Telemetry.BroadwayPipeline
# - Message queue length
# - Memory usage
```

---

## Integration with UI

Once telemetry is flowing to CVT, you can subscribe to updates:

```elixir
# Subscribe to CVT updates
Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:cvt:updates")

# You'll receive:
# %{
#   target_id: "SAT-001",
#   packet_name: "HEALTH",
#   item_name: "cpu_temp",
#   value: 50.0,
#   limits_state: :green,
#   received_time: ~U[...]
# }
```

---

## Next Steps

1. **Add more packet definitions** for different telemetry types
2. **Create real interfaces** that connect to actual hardware/simulators
3. **Implement Phase 5** (limits checking) for red/yellow violations
4. **Build LiveView dashboards** that subscribe to CVT updates
5. **Add commanding** (write path through protocols)

---

## Test Checklist

- [ ] Migrations run successfully
- [ ] Mission activates without errors
- [ ] Broadway pipeline starts
- [ ] Packet sent to PubSub
- [ ] CVT receives data
- [ ] Polynomial conversion works (temp)
- [ ] State table conversion works (mode)
- [ ] Raw values pass through (voltage)
- [ ] Mission deactivates cleanly

---

🎉 **If all checks pass, your telemetry system is working!**
