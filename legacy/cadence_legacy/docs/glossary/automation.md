---
title: Automation
aliases: [automations, automation rule]
tags: [glossary, procedures, automation]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Automation

An **Automation** is a simple trigger → action rule. It's the lightest-weight [Procedure](procedure.md) type.

## Characteristics

| Aspect | Automation Behavior |
|--------|---------------------|
| Complexity | Low |
| Definition | Trigger condition + action |
| Execution | Triggered by events, runs via Oban |
| Use case | Simple reactive logic |

## Trigger Types

| Trigger | Example |
|---------|---------|
| Alarm | "When THERMAL_HIGH triggers, run cooling sequence" |
| Telemetry | "When battery < 20%, send alert" |
| Schedule | "Every hour, run health check" |
| Pass | "When ground pass starts, enable downlink" |

## vs Sequences

| Aspect | Automation | Sequence |
|--------|------------|----------|
| Complexity | Single action | Multi-step |
| Approval | Optional | Required |
| Visibility | Rule-based | Step-by-step |
| Use case | Reactive | Planned operations |

## Event Sourcing

Automations create [Recordings](recording.md):
- `AutomationTriggered`
- `AutomationCompleted` / `AutomationFailed` / `AutomationSkipped`

## Related Concepts

- [Procedure](procedure.md) - Parent concept
- [Sequence](sequence.md) - More complex alternative

## See Also

- [Procedures Design](../design/procedures.md)
