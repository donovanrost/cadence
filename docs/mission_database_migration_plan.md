---
title: Mission Database Migration Plan
tags: [architecture, migration, database, missions]
related:
  - "[[mission]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Mission Database Migration Plan

## Overview

This document outlines the migration from the current telemetry/command schema to the new `Cadence.MissionDatabase` model. Since this is a greenfield project with no production data, we can do a clean migration without backward compatibility concerns.

## Current State

### Existing Schemas (to be replaced)

| Module | Table | Purpose |
|--------|-------|---------|
| `Cadence.Telemetry.Database.DefinitionSet` | `definition_sets` | Versioned C&T database |
| `Cadence.Telemetry.Packet.PacketDefinition` | `packet_definitions` | Telemetry packets |
| `Cadence.Telemetry.Packet.PacketItem` | `packet_items` | Telemetry points |
| `Cadence.Commands.CommandDefinition` | `command_definitions` | Commands |
| `Cadence.Commands.CommandParameter` | `command_parameters` | Command arguments |
| `Cadence.Telemetry.Conversions.Conversion` | `conversions` | Base conversion |
| `Cadence.Telemetry.Conversions.PolynomialConversion` | `polynomial_conversions` | Polynomial calibration |
| `Cadence.Telemetry.Conversions.StateTableConversion` | `state_table_conversions` | State mapping |
| `Cadence.Telemetry.Conversions.GenericConversion` | `generic_conversions` | Custom module |
| `Cadence.Telemetry.Database.DerivedItem` | `derived_items` | Computed telemetry |

### Existing Migrations (in order)

1. `20251116213958_create_packet_definitions.exs`
2. `20251116214033_create_packet_items.exs`
3. `20251116214035_create_command_definitions.exs`
4. `20251116214036_create_command_parameters.exs`
5. `20251118000002_create_conversions.exs`
6. `20251121025944_rename_bit_length_to_bit_size.exs`
7. `20251123000001_add_endianness_to_packet_items.exs`
8. `20251123000002_create_definition_sets.exs`
9. `20251123175132_add_derived_items_support.exs`
10. `20251123204226_create_derived_items.exs`
11. `20251123204227_add_definition_set_to_commands.exs`
12. `20251125022310_update_derived_items_to_qualified_names.exs`
13. `20251125030000_add_type_byte_to_packet_definitions.exs`

---

## Target State

### New Namespace: `Cadence.MissionDatabase`

```
lib/cadence/mission_database/
├── definition_set.ex           # Root versioned container
├── data_type.ex                # Shared type definitions
├── data_encoding.ex            # Embedded: binary encoding config
├── enumeration_value.ex        # Embedded: enum value/label
├── aggregate_member.ex         # Embedded: struct member
├── array_dimensions.ex         # Embedded: array sizing
├── unit.ex                     # Unit definitions
├── algorithm.ex                # Calibrators/conversions
├── spline_point.ex             # Embedded: interpolation point
├── context_calibrator.ex       # Condition-dependent calibration
├── container.ex                # Telemetry packets
├── container_entry.ex          # Parameter refs in container
├── parameter.ex                # Telemetry parameters
├── match_criteria.ex           # Embedded: conditions
├── alarm_definition.ex         # Embedded: limit thresholds
├── alarm_range.ex              # Embedded: single range
├── context_alarm.ex            # Condition-dependent alarms
├── meta_command.ex             # Command definitions
├── command_interlock.ex        # Embedded: sequential constraints
├── argument.ex                 # Command arguments
├── hazardous_state.ex          # Embedded: per-value hazard
├── transmission_constraint.ex  # Command preconditions
├── command_verifier.ex         # Multi-stage verification
├── stream.ex                   # Framing/protocol definition
├── command_container.ex        # Command binary layout
├── command_container_entry.ex  # Entries in command container
└── derived_item.ex             # Runtime overlay (mission-scoped)
```

---

## Migration Strategy

### Approach: Clean Replacement

Since there's no production data, we'll:
1. Create new tables with `mdb_` prefix for clarity
2. Create new Ecto schemas in `Cadence.MissionDatabase`
3. Update importers (YAML, eventually XTCE) to use new schemas
4. Update runtime components to use new schemas
5. Remove old schemas and tables
6. Optionally rename tables to remove `mdb_` prefix

### Phase 1: Core Schema (Foundation)

**Goal:** Establish the foundational types that everything else depends on.

**New Tables:**
- `mdb_definition_sets` - Versioned database root
- `mdb_units` - Unit definitions
- `mdb_algorithms` - Calibrators/conversions (unified)
- `mdb_data_types` - Shared type definitions

**New Modules:**
- `Cadence.MissionDatabase.DefinitionSet`
- `Cadence.MissionDatabase.Unit`
- `Cadence.MissionDatabase.Algorithm`
- `Cadence.MissionDatabase.SplinePoint` (embedded)
- `Cadence.MissionDatabase.DataType`
- `Cadence.MissionDatabase.DataEncoding` (embedded)
- `Cadence.MissionDatabase.EnumerationValue` (embedded)
- `Cadence.MissionDatabase.AggregateMember` (embedded)
- `Cadence.MissionDatabase.ArrayDimensions` (embedded)
- `Cadence.MissionDatabase.MatchCriteria` (embedded)
- `Cadence.MissionDatabase.AlarmDefinition` (embedded)
- `Cadence.MissionDatabase.AlarmRange` (embedded)

**Tasks:**
- [ ] Create migration for `mdb_definition_sets`
- [ ] Create migration for `mdb_units`
- [ ] Create migration for `mdb_algorithms`
- [ ] Create migration for `mdb_data_types`
- [ ] Create migration for `mdb_context_calibrators`
- [ ] Create migration for `mdb_context_alarms`
- [ ] Create all Ecto schema modules
- [ ] Write tests for schema validations

---

### Phase 2: Telemetry (Containers & Parameters)

**Goal:** Model telemetry packets with proper inheritance and identification.

**New Tables:**
- `mdb_parameters` - Telemetry parameters (separate from containers)
- `mdb_containers` - Telemetry packet definitions
- `mdb_container_entries` - Parameter refs within containers
- `mdb_streams` - Framing/protocol definitions

**New Modules:**
- `Cadence.MissionDatabase.Parameter`
- `Cadence.MissionDatabase.Container`
- `Cadence.MissionDatabase.ContainerEntry`
- `Cadence.MissionDatabase.Stream`

**Key Changes from Current:**
- Parameters are now standalone entities, not embedded in packets
- Containers reference parameters via ContainerEntry
- Containers support inheritance (`base_container_ref`)
- Containers have `restriction_criteria` for identification
- Streams define framing protocols

**Tasks:**
- [ ] Create migration for `mdb_streams`
- [ ] Create migration for `mdb_parameters`
- [ ] Create migration for `mdb_containers`
- [ ] Create migration for `mdb_container_entries`
- [ ] Create Ecto schema modules
- [ ] Write tests for inheritance resolution
- [ ] Write tests for restriction criteria matching

---

### Phase 3: Commands (MetaCommands & Verification)

**Goal:** Full command model with constraints and multi-stage verification.

**New Tables:**
- `mdb_meta_commands` - Command definitions
- `mdb_arguments` - Command arguments
- `mdb_transmission_constraints` - Command preconditions
- `mdb_command_verifiers` - Multi-stage verification
- `mdb_command_containers` - Command binary layout
- `mdb_command_container_entries` - Entries in command layout

**New Modules:**
- `Cadence.MissionDatabase.MetaCommand`
- `Cadence.MissionDatabase.CommandInterlock` (embedded)
- `Cadence.MissionDatabase.Argument`
- `Cadence.MissionDatabase.HazardousState` (embedded)
- `Cadence.MissionDatabase.TransmissionConstraint`
- `Cadence.MissionDatabase.CommandVerifier`
- `Cadence.MissionDatabase.CommandContainer`
- `Cadence.MissionDatabase.CommandContainerEntry`

**Key Changes from Current:**
- Commands support inheritance (`base_command_ref`)
- Multi-stage verification (8 stages vs current single-stage)
- Transmission constraints for preconditions
- Interlocks for sequential command dependencies
- Per-argument hazardous states

**Tasks:**
- [ ] Create migration for `mdb_meta_commands`
- [ ] Create migration for `mdb_arguments`
- [ ] Create migration for `mdb_transmission_constraints`
- [ ] Create migration for `mdb_command_verifiers`
- [ ] Create migration for `mdb_command_containers`
- [ ] Create migration for `mdb_command_container_entries`
- [ ] Create Ecto schema modules
- [ ] Write tests for command inheritance
- [ ] Write tests for constraint evaluation

---

### Phase 4: Derived Items (Runtime Overlay)

**Goal:** Migrate derived items to work with new parameter references.

**New Tables:**
- `mdb_derived_items` - Runtime computed telemetry

**Changes:**
- Update to reference new parameter naming scheme
- Ensure backward compatibility with existing expressions

**Tasks:**
- [ ] Create migration for `mdb_derived_items`
- [ ] Create `Cadence.MissionDatabase.DerivedItem`
- [ ] Update expression evaluator for new parameter refs
- [ ] Write migration script for existing derived item expressions

---

### Phase 5: Importers

**Goal:** Update all importers to produce new schema structures.

**Modules to Update/Create:**
- `Cadence.MissionDatabase.Importers.Yaml` - Current YAML format
- `Cadence.MissionDatabase.Importers.Xtce` - NEW: XTCE parser
- `Cadence.MissionDatabase.Importers.Cosmos` - NEW: OpenC3 format
- `Cadence.MissionDatabase.Importers.Csv` - NEW: Simple CSV format

**Tasks:**
- [ ] Refactor `YamlImporter` to new namespace and schemas
- [ ] Update YAML format to support new features (inheritance, constraints)
- [ ] Create XTCE importer (can be Phase 6)
- [ ] Create COSMOS importer (can be Phase 6)
- [ ] Write comprehensive importer tests

---

### Phase 6: Runtime Integration

**Goal:** Update all runtime components to use new schemas.

**Modules to Update:**

| Module | Changes Needed |
|--------|----------------|
| `Cadence.Telemetry.PacketIdentifier` | Use `Container` + `restriction_criteria` |
| `Cadence.Telemetry.Decommutation` | Use `ContainerEntry` + `Parameter` + `DataType` |
| `Cadence.Telemetry.Conversions` | Use `Algorithm` (unified) |
| `Cadence.Telemetry.Limits.Evaluator` | Use `DataType.default_alarm` + context alarms |
| `Cadence.Telemetry.CurrentValueTable` | Use new parameter naming |
| `Cadence.Commands.Encoder` | Use `CommandContainer` + `Argument` |
| `Cadence.Commands.Verification` | Use `CommandVerifier` (multi-stage) |
| `Cadence.Commands.Dispatcher` | Use `TransmissionConstraint` |
| `Cadence.Databases` (context) | Update all queries |

**Tasks:**
- [ ] Update `PacketIdentifier` for restriction criteria
- [ ] Update `Decommutation` for new type system
- [ ] Update `Conversions` module
- [ ] Update `Limits.Evaluator` for context alarms
- [ ] Update `CVT` for new parameter structure
- [ ] Update `Commands.Encoder`
- [ ] Update `Commands.Verification` for multi-stage
- [ ] Update `Commands.Dispatcher` for constraints
- [ ] Update `Databases` context module
- [ ] Comprehensive integration tests

---

### Phase 7: Cleanup

**Goal:** Remove old schemas and tables.

**Tasks:**
- [ ] Remove old Ecto schemas from `lib/cadence/telemetry/`
- [ ] Remove old Ecto schemas from `lib/cadence/commands/`
- [ ] Create migration to drop old tables
- [ ] Optionally rename `mdb_*` tables to remove prefix
- [ ] Update all documentation
- [ ] Final integration test pass

---

## Table Naming Convention

### New Tables

| Table Name | Schema Module |
|------------|---------------|
| `mdb_definition_sets` | `Cadence.MissionDatabase.DefinitionSet` |
| `mdb_units` | `Cadence.MissionDatabase.Unit` |
| `mdb_algorithms` | `Cadence.MissionDatabase.Algorithm` |
| `mdb_data_types` | `Cadence.MissionDatabase.DataType` |
| `mdb_context_calibrators` | `Cadence.MissionDatabase.ContextCalibrator` |
| `mdb_context_alarms` | `Cadence.MissionDatabase.ContextAlarm` |
| `mdb_parameters` | `Cadence.MissionDatabase.Parameter` |
| `mdb_containers` | `Cadence.MissionDatabase.Container` |
| `mdb_container_entries` | `Cadence.MissionDatabase.ContainerEntry` |
| `mdb_streams` | `Cadence.MissionDatabase.Stream` |
| `mdb_meta_commands` | `Cadence.MissionDatabase.MetaCommand` |
| `mdb_arguments` | `Cadence.MissionDatabase.Argument` |
| `mdb_transmission_constraints` | `Cadence.MissionDatabase.TransmissionConstraint` |
| `mdb_command_verifiers` | `Cadence.MissionDatabase.CommandVerifier` |
| `mdb_command_containers` | `Cadence.MissionDatabase.CommandContainer` |
| `mdb_command_container_entries` | `Cadence.MissionDatabase.CommandContainerEntry` |
| `mdb_derived_items` | `Cadence.MissionDatabase.DerivedItem` |

---

## Embedded Schemas (No Tables)

These are embedded in their parent schemas using Ecto's `embeds_one`/`embeds_many`:

| Schema | Embedded In |
|--------|-------------|
| `DataEncoding` | `DataType.encoding` |
| `EnumerationValue` | `DataType.enumerations` |
| `AggregateMember` | `DataType.members` |
| `ArrayDimensions` | `DataType.array_dimensions` |
| `SplinePoint` | `Algorithm.spline_points` |
| `MatchCriteria` | Multiple (Container, TransmissionConstraint, etc.) |
| `AlarmDefinition` | `DataType.default_alarm`, `ContextAlarm.alarm_definition` |
| `AlarmRange` | `AlarmDefinition.*_range` |
| `CommandInterlock` | `MetaCommand.interlock` |
| `HazardousState` | `Argument.hazardous_states` |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Large scope creep | Medium | High | Strict phase boundaries; don't gold-plate |
| Runtime integration complexity | Medium | Medium | Comprehensive tests before runtime changes |
| YAML format breaking changes | Low | Medium | Version YAML format, support old + new |
| Performance regression | Low | Medium | Benchmark packet identification, decom |

---

## Open Questions

1. **Should we keep `mdb_` prefix permanently?**
   - Pro: Clear namespace separation
   - Con: Verbose in queries
   - Recommendation: Keep for now, revisit after cleanup

2. **How to handle the transition period?**
   - Option A: Big bang (create all new, delete all old at once)
   - Option B: Gradual (new and old coexist during development)
   - Recommendation: Option A since no production data

3. **YAML format versioning?**
   - Should new YAML format be backward compatible?
   - Recommendation: Create v2 format, but support v1 import with warnings

---

## Next Steps

1. Review and approve this plan
2. Create Phase 1 migrations and schemas
3. Iterate through phases
4. Final cleanup and documentation

---

## Timeline Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: Core Schema | 2-3 days | None |
| Phase 2: Telemetry | 2-3 days | Phase 1 |
| Phase 3: Commands | 2-3 days | Phase 1 |
| Phase 4: Derived Items | 1 day | Phase 2 |
| Phase 5: Importers | 2-3 days | Phases 1-3 |
| Phase 6: Runtime | 3-5 days | Phases 1-5 |
| Phase 7: Cleanup | 1 day | Phase 6 |

**Total: ~2-3 weeks** (depending on runtime complexity)
