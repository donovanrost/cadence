---
title: "ADR-002: Luerl for Procedure Execution"
aliases: [luerl decision, lua runtime]
tags: [adr, procedures, runtime, luerl]
status: accepted
created: 2025-01-27
updated: 2025-01-27
---

# ADR-002: Luerl for Procedure Execution

## Status

Accepted

## Context

Cadence needs a runtime for executing [Procedures](../glossary/procedure.md) - operational logic that can:

- Access telemetry (read-only)
- Send commands
- Wait for conditions
- Be paused, resumed, and aborted
- Serialize state for checkpointing

Options considered:

1. **Native Elixir** - Write procedures as Elixir modules
2. **Custom DSL** - Build a domain-specific language
3. **Embedded scripting** - Use an embedded language (Lua, JavaScript, etc.)

## Decision

Use **Luerl** (Lua implemented in Erlang) as the procedure execution runtime.

All procedure types compile to or are written as Lua:
- [Sequences](../glossary/sequence.md) compile from step DSL to Lua
- Scripts are raw Lua
- [Automations](../glossary/automation.md) execute as simple Lua functions

### Implementation

Each execution runs in its own GenServer holding a Luerl VM:

```elixir
defmodule Cadence.Procedures.Engine.ExecutionProcess do
  def init(procedure) do
    {:ok, lua_state} = :luerl.init()
    lua_state = inject_cadence_api(lua_state)
    {:ok, %{lua: lua_state, procedure: procedure}}
  end
end
```

The Cadence API is exposed to Lua:

```lua
cadence.telemetry.get("HEALTH.cpu_temp")
cadence.telemetry.wait_for("HEALTH.cpu_temp", "<", 80, timeout_ms)
cadence.command.send("POWER_ON", {subsystem = "PAYLOAD"})
cadence.wait(milliseconds)
cadence.checkpoint("step_name")
```

## Consequences

### Positive

- **Sandboxed** - Lua runs in isolated VM, can't access Elixir internals
- **Serializable** - Luerl state can be serialized for pause/resume
- **Familiar** - Lua is widely known, easy syntax for operators
- **Lightweight** - Luerl VMs are cheap to spawn
- **Interruptible** - Can check control signals between Lua operations

### Negative

- **Two languages** - Developers must know both Elixir and Lua
- **Debugging** - Stack traces cross language boundaries
- **Performance** - Luerl is slower than native Elixir
- **Limited stdlib** - Must explicitly expose functionality

### Mitigations

- Sequences use a step DSL that compiles to Lua (operators don't write Lua)
- Scripts require code review before approval
- Performance is acceptable for procedural operations (not hot path)

## Key Modules

| Module | Role |
|--------|------|
| `Cadence.Procedures.Engine.ExecutionProcess` | GenServer holding Luerl VM |
| `Cadence.Procedures.Engine.LuaApi` | Cadence API exposed to Lua |
| `Cadence.Procedures.Compiler` | Compiles step DSL to Lua |

## See Also

- [Procedures Design](../design/procedures.md)
- [Procedure](../glossary/procedure.md) glossary entry
- [Sequence](../glossary/sequence.md) glossary entry
