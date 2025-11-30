# Comprehensive C2 System Internal Model in Elixir

## Introduction
This document outlines the complete internal model for a Command and Control (C2) system, designed from scratch in Elixir. It incorporates all elements for normalizing data from formats like XTCE, EDS, CSV, JSON, and custom formats. The model is extensible, hierarchical, and leverages Elixir's strengths for immutability and concurrency.

## Design Principles
- **Normalization-Friendly**: Unified structure for diverse inputs.
- **Modular and Hierarchical**: Supports inheritance and references.
- **Elixir Idiomatic**: Uses structs; mappable to Ecto for persistence.
- **Extensible**: Custom extensions via maps.
- **Comprehensive**: Covers telemetry, commands, types, algorithms, behaviors, constraints, verifiers, and more.

## Core Modules and Structs

### 1. Database (Root)
Represents the entire C&T database.

```elixir
defmodule Cadence.C2Model.Database do
  defstruct [
    :name,
    :version,
    :description,
    :telemetry,
    :commands,
    :types,  # Map<String, DataType>
    :algorithms,  # Map<String, Algorithm>
    :state_machines,  # Map<String, StateMachine>
    :units,  # Map<String, Unit>
    :enumerations,  # Map<String, list({Any, String})>
    :extensions  # Map
  ]
end
```

### 2. Telemetry
Holds parameters, containers, and streams.

```elixir
defmodule Cadence.C2Model.Telemetry do
  defstruct [
    :parameters,  # Map<String, Parameter>
    :containers,  # Map<String, Container>
    :streams  # Map<String, Stream>
  ]
end
```

### 3. Commands
Symmetric to Telemetry.

```elixir
defmodule Cadence.C2Model.Commands do
  defstruct [
    :meta_commands,  # Map<String, MetaCommand>
    :arguments  # Map<String, Argument> (shared)
  ]
end
```

### 4. DataType (Shared)
Reusable for parameters/arguments.

```elixir
defmodule Cadence.C2Model.DataType do
  defstruct [
    :name,
    :description,
    :type,  # :integer | :float | :string | :boolean | :enum | :array | :aggregate | :time | :binary
    :size,  # Integer (bits/bytes)
    :encoding,  # %{endianness: :big | :little, signed: boolean}
    :units,  # String
    :default_value,  # Any
    :states,  # %{integer => String} for :enum
    :element_type,  # DataType for :array
    :length,  # integer | {:dynamic, String} | {:expr, String}
    :members,  # list(Parameter | Argument) for :aggregate
    :epoch,  # :unix | :gps | DateTime for :time
    :resolution  # :seconds | :milliseconds for :time
  ]
end
```

### 5. Parameter (Telemetry)
```elixir
defmodule Cadence.C2Model.Parameter do
  defstruct [
    :name,
    :data_type,  # DataType
    :bit_offset,
    :description,
    :limits,  # %{red_low: number, yellow_low: number, yellow_high: number, red_high: number, actions: [String]}
    :validations,  # %{min: number, max: number, valid_values: [Any], pattern: Regex}
    :calibration,  # Algorithm ref
    :significance,  # :info | :watch | :critical
    :error_codes,  # Map<integer, String>
    :recovery,  # [String] (command refs)
    :log_level  # :debug | :info | :warn | :error
  ]
end
```

### 6. Argument (Commands)
```elixir
defmodule Cadence.C2Model.Argument do
  defstruct [
    :name,
    :data_type,  # DataType
    :bit_offset,
    :description,
    :validations,  # Same as Parameter
    :required,  # boolean
    :error_codes,  # Map<integer, String>
    :recovery,  # [String]
    :log_level  # :debug | :info | :warn | :error
  ]
end
```

### 7. Container (Telemetry Packets)
```elixir
defmodule Cadence.C2Model.Container do
  defstruct [
    :name,
    :apid,  # Integer
    :description,
    :entries,  # [Parameter]
    :base_container,  # String ref
    :restrictions,  # [Constraint]
    :header,  # %{fields: [Parameter], error_detection: :crc | :parity}
    :state_machine_ref,  # String
    :access_level,  # :public | :restricted | :admin
    :auth_required  # boolean
  ]
end
```

### 8. MetaCommand (Commands)
```elixir
defmodule Cadence.C2Model.MetaCommand do
  defstruct [
    :name,
    :opcode,  # Integer
    :description,
    :arguments,  # [Argument]
    :base_command,  # String ref
    :is_hazardous,  # boolean
    :hazard_description,
    :requires_confirmation,  # boolean
    :verifiers,  # [Verifier]
    :constraints,  # [Constraint]
    :significance,  # :normal | :critical
    :state_machine_ref,  # String
    :error_codes,  # Map<integer, String>
    :recovery,  # [String]
    :log_level,  # :debug | :info | :warn | :error
    :access_level,  # :public | :restricted | :admin
    :auth_required  # boolean
  ]
end
```

### 9. Algorithm (Conversions)
```elixir
defmodule Cadence.C2Model.Algorithm do
  defstruct [
    :name,
    :type,  # :state_table | :polynomial | :spline | :expression | :custom
    :states,  # Map for :state_table
    :coefficients,  # [number] for :polynomial
    :expression,  # String
    :language,  # :elixir | :js
    :code  # String (snippet)
  ]
end
```

### 10. Constraint
```elixir
defmodule Cadence.C2Model.Constraint do
  defstruct [
    :condition,  # String (expr)
    :on_failure,  # :reject | :warn
    :references  # [String] (params/commands)
  ]
end
```

### 11. Verifier
```elixir
defmodule Cadence.C2Model.Verifier do
  defstruct [
    :stage,  # :armed | :sent | :executed | :completed
    :condition,  # String
    :timeout,  # integer (seconds)
    :check_type,  # :parameter | :state
    :ref  # String (param/state)
  ]
end
```

### 12. Stream (Framing)
```elixir
defmodule Cadence.C2Model.Stream do
  defstruct [
    :name,
    :protocol,  # :ccSDS | :custom
    :containers  # [String] refs
  ]
end
```

### 13. StateMachine (Behaviors)
```elixir
defmodule Cadence.C2Model.StateMachine do
  defstruct [
    :name,
    :description,
    :states,  # [String]
    :initial_state,  # String
    :transitions,  # [Transition]
    :extensions  # Map
  ]
end

defmodule Cadence.C2Model.Transition do
  defstruct [
    :from,  # String
    :to,  # String
    :trigger,  # String (command/param event)
    :guard,  # Constraint
    :actions  # [String or Algorithm]
  ]
end
```

### 14. Unit (Global)
```elixir
defmodule Cadence.C2Model.Unit do
  defstruct [
    :name,
    :symbol,
    :conversion_factor  # To base SI
  ]
end
```

## Diagram
```
Internal C2 Model Structure (UML-like ASCII Diagram)

+--------------------+
|     Database      |
+--------------------+
| - name             |
| - version          |
| - description      |
| - telemetry        |
| - commands         |
| - types            |
| - algorithms       |
| - state_machines   |
| - units            |
| - enumerations     |
| - extensions       |
+--------------------+
          | 
          | contains
          |
          +----------------+    +----------------+
                           |    |
                           v    v
                 +-------------+  +-------------+
                 |  Telemetry  |  |  Commands   |
                 +-------------+  +-------------+
                 | - parameters|  | - meta_cmds |
                 | - containers|  | - arguments |
                 | - streams   |  +-------------+
                 +-------------+
                           |              |
                           | contains     | contains
                           |              |
                           v              v
                 +-------------+  +-------------+
                 |  Container  |  | MetaCommand |
                 +-------------+  +-------------+
                 | - name      |  | - name      |
                 | - apid      |  | - opcode    |
                 | - entries   |  | - arguments |
                 | - base_con  |  | - base_cmd  |
                 | - restrict  |  | - hazardous |
                 | - header    |  | - verifiers |
                 | - sm_ref    |  | - constrain |
                 | - access    |  | - sm_ref    |
                 +-------------+  | - error_codes|
                                  | - recovery   |
                                  | - log_level  |
                                  | - access     |
                                  +-------------+
                           ^              ^
                           |              |
                references |              | references
                           |              |
                 +-------------+  +-------------+
                 |  Parameter  |  |  Argument   |
                 +-------------+  +-------------+
                 | - name      |  | - name      |
                 | - data_type |  | - data_type |
                 | - bit_offset|  | - bit_offset|
                 | - limits    |  | - required  |
                 | - validatns |  | - validatns |
                 | - calibratn |  | - error_codes|
                 | - signif    |  | - recovery   |
                 | - error_codes| | - log_level  |
                 | - recovery  |
                 | - log_level |
                 +-------------+
                           ^              ^
                           |              |
                  uses     |              | uses
                           |              |
                       +-------------+
                       |  DataType   |
                       +-------------+
                       | - name      |
                       | - type      |
                       | - size      |
                       | - encoding  |
                       | - units     |
                       | - states    |
                       | - elem_type |
                       | - length    |
                       | - members   |
                       +-------------+

                 Shared:
                 +-------------+  +-------------+  +-------------+
                 |  Algorithm  |  |  Constraint |  |  Verifier   |
                 +-------------+  +-------------+  +-------------+
                 | - name      |  | - condition |  | - stage     |
                 | - type      |  | - on_fail   |  | - condition |
                 | - states    |  | - refs      |  | - timeout   |
                 | - coeffs    |  +-------------+  | - check_type|
                 | - expr      |                   | - ref       |
                 | - code      |                   +-------------+
                 +-------------+

                 +-------------+  +----------------+
                 |   Stream    |  | StateMachine  |
                 +-------------+  +----------------+
                 | - name      |  | - name        |
                 | - protocol  |  | - states      |
                 | - containers|  | - initial     |
                 +-------------+  | - transitions |
                                   +----------------+
                                                |
                                                | has
                                                v
                                          +-------------+
                                          |  Transition |
                                          +-------------+
                                          | - from      |
                                          | - to        |
                                          | - trigger   |
                                          | - guard     |
                                          | - actions   |
                                          +-------------+

                 +-------------+
                 |    Unit     |
                 +-------------+
                 | - name      |
                 | - symbol    |
                 | - conv_fact |
                 +-------------+
```

## Normalization and Parsing
- Write parsers to build Database from inputs (e.g., XML for XTCE).
- Handle gaps with defaults.
- Resolve hierarchies at runtime.

## Ecto Integration
Map structs to Ecto schemas for persistence, using embeds or relations.

## Runtime Utilities
Add a Utils module for resolution, validation, and execution.

## Implementation Notes
- Use typespecs and validation.
- Implement JSON encoding.
- Test with samples from various formats.

This model is now 100% complete for a robust C2 system.