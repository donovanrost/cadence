---
title: Sequence
aliases: [sequences, procedure sequence]
tags: [glossary, procedures, sequence]
related:
  - "[[procedure]]"
  - "[[automation]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Sequence

A **Sequence** is a step-based [Procedure](procedure.md) optimized for predictability and approval workflows. Sequences use a DSL that compiles to Lua.

## Characteristics

| Aspect | Sequence Behavior |
|--------|-------------------|
| Definition | JSON/Elixir step DSL |
| Execution | Compiles to Lua, runs in Luerl VM |
| Approval | Versioned, requires approval before use |
| Visibility | Steps visible in UI before execution |

## Step Types

| Step | Purpose |
|------|---------|
| `check` | Evaluate condition, abort/skip/warn on failure |
| `command` | Send command to target |
| `wait` | Wait for duration |
| `wait_for` | Wait for telemetry condition |
| `branch` | Conditional goto |
| `log` | Record message |

## Example

```elixir
%{
  steps: [
    %{type: "check", condition: "telemetry.POWER.voltage >= 24", on_fail: "abort"},
    %{type: "command", name: "HEATER_ON", args: %{zone: 1}},
    %{type: "wait_for", item: "THERMAL.temp", operator: ">", value: 20, timeout: 30000},
    %{type: "command", name: "PAYLOAD_ON"}
  ]
}
```

## Why Sequences?

Sequences answer "what will this do?" before execution:
- Steps are visible and reviewable
- Approval workflow ensures oversight
- Predictable behavior for critical operations

For complex custom logic, use Scripts instead.

## Related Concepts

- [Procedure](procedure.md) - Parent concept
- [Automation](automation.md) - Simpler trigger-action alternative

## See Also

- [Procedures Design](../design/procedures.md)
