---
title: Cadence Mission Database Model v2
tags: [architecture, database, data-model]
related:
  - "[[mission]]"
  - "[[target]]"
  - "[[command]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Cadence Mission Database Model v2

## Overview

This document defines the complete internal model for the Mission Database (MDB) in Cadence - the command and telemetry definition layer. The model is designed to:

1. **Normalize** data from diverse formats: XTCE, OpenC3/COSMOS, EDS/SEDS, CSV, JSON
2. **Support multi-tenancy** with organization and mission scoping
3. **Enable versioning** with immutable published snapshots
4. **Be comprehensive** enough to round-trip any source format without loss

## Design Principles

- **XTCE as Reference**: XTCE 1.2/1.3 is the most comprehensive standard; we model everything it supports
- **Multi-tenant First**: All entities scoped to organization → mission
- **Versioned Immutability**: Published DefinitionSets are immutable snapshots
- **Type Reuse**: Shared type definitions referenced by name, not duplicated inline
- **Elixir Idiomatic**: Ecto schemas with proper associations and constraints

## Entity Relationship Overview

```
Organization (tenant)
    └── Mission
            └── DefinitionSet (versioned snapshot)
                    ├── DataType[]           (shared type definitions)
                    ├── Unit[]               (unit definitions)
                    ├── Algorithm[]          (calibrators/conversions)
                    ├── Container[]          (telemetry packets)
                    │       └── ContainerEntry[]
                    │               └── Parameter
                    ├── MetaCommand[]        (command definitions)
                    │       ├── Argument[]
                    │       ├── TransmissionConstraint[]
                    │       └── Verifier[]
                    └── Stream[]             (framing/protocol)
            └── DerivedItem[]        (runtime overlay, not versioned)
            └── AlarmDefinition[]    (can be versioned or runtime)
```

---

## Core Schemas

### 1. DefinitionSet (Root Container)

The atomic unit of a C&T database version. Contains all definitions for a specific version.

```elixir
defmodule Cadence.MissionDatabase.DefinitionSet do
  @moduledoc """
  A versioned, immutable snapshot of command and telemetry definitions.

  Only one DefinitionSet can be active per mission at any time.
  Published DefinitionSets are immutable - changes require a new version.
  """

  use Ecto.Schema

  schema "definition_sets" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :name, :string                    # Human-readable name
    field :version, :string                 # Semantic version (e.g., "1.2.0")
    field :description, :string

    # Source tracking for auditing and re-import detection
    field :source_format, Ecto.Enum, values: [:xtce, :cosmos, :eds, :yaml, :csv, :json]
    field :source_filename, :string
    field :source_hash, :string             # SHA256 of source content

    # Lifecycle
    field :published_at, :utc_datetime      # When activated
    field :superseded_at, :utc_datetime     # When replaced by newer version

    # Extensions for format-specific metadata
    field :extensions, :map, default: %{}

    # Associations
    has_many :data_types, Cadence.MissionDatabase.DataType
    has_many :units, Cadence.MissionDatabase.Unit
    has_many :algorithms, Cadence.MissionDatabase.Algorithm
    has_many :containers, Cadence.MissionDatabase.Container
    has_many :meta_commands, Cadence.MissionDatabase.MetaCommand
    has_many :streams, Cadence.MissionDatabase.Stream

    timestamps(type: :utc_datetime)
  end
end
```

---

### 2. DataType (Shared Type Definitions)

Reusable type definitions referenced by parameters and arguments. This is critical for XTCE compatibility where types are defined once and referenced by name.

```elixir
defmodule Cadence.MissionDatabase.DataType do
  @moduledoc """
  Shared data type definition that can be referenced by parameters and arguments.

  XTCE separates ParameterType and ArgumentType, but they share the same structure.
  We unify them with a `usage` field to indicate applicability.

  Types include: integer, float, string, binary, boolean, enumerated,
  aggregate (struct), array, absolute_time, relative_time
  """

  use Ecto.Schema

  schema "data_types" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string                    # Unique within definition_set
    field :description, :string

    # What this type can be used for
    field :usage, Ecto.Enum, values: [:parameter, :argument, :both], default: :both

    # Base type category
    field :base_type, Ecto.Enum, values: [
      :integer, :float, :string, :binary, :boolean,
      :enumerated, :aggregate, :array,
      :absolute_time, :relative_time
    ]

    # Encoding configuration (how raw bits map to value)
    embeds_one :encoding, Cadence.MissionDatabase.DataEncoding, on_replace: :update

    # For enumerated types: value → label mappings
    embeds_many :enumerations, Cadence.MissionDatabase.EnumerationValue, on_replace: :delete

    # For aggregate types: member definitions
    embeds_many :members, Cadence.MissionDatabase.AggregateMember, on_replace: :delete

    # For array types
    field :array_element_type_ref, :string  # Reference to another DataType
    embeds_one :array_dimensions, Cadence.MissionDatabase.ArrayDimensions, on_replace: :update

    # For time types
    field :epoch, Ecto.Enum, values: [:unix, :tai, :gps, :j2000, :custom]
    field :epoch_custom, :utc_datetime      # If epoch == :custom
    field :time_scale, :float               # Multiplier (e.g., 1000 for ms → s)
    field :time_offset, :float              # Offset to add after scaling

    # Calibrator reference (raw → engineering conversion)
    belongs_to :default_calibrator, Cadence.MissionDatabase.Algorithm

    # Context calibrators (condition-dependent calibration)
    has_many :context_calibrators, Cadence.MissionDatabase.ContextCalibrator

    # Alarm definitions
    embeds_one :default_alarm, Cadence.MissionDatabase.AlarmDefinition, on_replace: :update
    has_many :context_alarms, Cadence.MissionDatabase.ContextAlarm

    # Valid range (for validation, separate from alarms)
    field :valid_range_min, :float
    field :valid_range_max, :float
    field :valid_range_applies_to_calibrated, :boolean, default: true

    # Unit reference
    belongs_to :unit, Cadence.MissionDatabase.Unit

    # Initial/default value
    field :initial_value, :string           # Stored as string, parsed based on type

    # Extensions
    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.DataEncoding do
  @moduledoc """
  Describes how a value is encoded in binary format.
  """
  use Ecto.Schema

  embedded_schema do
    field :encoding_type, Ecto.Enum, values: [
      :integer, :float, :string, :binary, :boolean
    ]

    # Bit-level positioning
    field :size_in_bits, :integer
    field :byte_order, Ecto.Enum, values: [:big_endian, :little_endian], default: :big_endian

    # Integer-specific
    field :signed, :boolean, default: false
    field :integer_encoding, Ecto.Enum, values: [
      :unsigned, :twos_complement, :sign_magnitude, :ones_complement
    ], default: :unsigned

    # Float-specific
    field :float_encoding, Ecto.Enum, values: [:ieee754, :mil_std_1750a]

    # String-specific
    field :charset, :string, default: "UTF-8"
    field :string_termination, Ecto.Enum, values: [:null, :fixed_length, :length_prefixed]
    field :string_length_prefix_bits, :integer  # For length_prefixed

    # Dynamic size (reference to another parameter)
    field :dynamic_size_ref, :string
    field :dynamic_size_linear_adjustment, :map  # %{slope: float, intercept: float}
  end
end

defmodule Cadence.MissionDatabase.EnumerationValue do
  use Ecto.Schema

  embedded_schema do
    field :value, :integer
    field :label, :string
    field :description, :string
    field :max_value, :integer              # For ranges: value..max_value
  end
end

defmodule Cadence.MissionDatabase.AggregateMember do
  use Ecto.Schema

  embedded_schema do
    field :name, :string
    field :type_ref, :string                # Reference to DataType name
    field :description, :string
    field :initial_value, :string
  end
end

defmodule Cadence.MissionDatabase.ArrayDimensions do
  use Ecto.Schema

  embedded_schema do
    # Static dimensions
    field :dimensions, {:array, :integer}   # e.g., [10, 20] for 10x20 array

    # Dynamic dimensions (reference to parameter for size)
    field :dynamic_dimension_refs, {:array, :string}

    # Linear adjustment for dynamic sizes
    field :linear_adjustments, {:array, :map}  # [%{slope: 1, intercept: 0}]
  end
end
```

---

### 3. Unit (Unit Definitions)

```elixir
defmodule Cadence.MissionDatabase.Unit do
  @moduledoc """
  Unit of measure definition with optional SI conversion.
  """

  use Ecto.Schema

  schema "units" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string                    # Full name (e.g., "Celsius")
    field :symbol, :string                  # Short form (e.g., "°C")
    field :description, :string

    # SI conversion (value_in_si = value * factor + offset)
    field :si_conversion_factor, :float
    field :si_conversion_offset, :float
    field :si_unit, :string                 # Base SI unit name

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end
```

---

### 4. Algorithm (Calibrators and Conversions)

```elixir
defmodule Cadence.MissionDatabase.Algorithm do
  @moduledoc """
  Calibration/conversion algorithm. Transforms raw values to engineering units.

  Supports:
  - Polynomial: y = c0 + c1*x + c2*x² + ...
  - Spline: Piecewise linear/quadratic interpolation
  - MathOperation: RPN expression
  - StateTable: Discrete value mapping (for telemetry display)
  - Custom: Elixir module implementation
  """

  use Ecto.Schema

  schema "algorithms" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string

    field :algorithm_type, Ecto.Enum, values: [
      :polynomial, :spline, :math_operation, :state_table, :custom
    ]

    # Polynomial: y = sum(coefficients[i] * x^i)
    field :polynomial_coefficients, {:array, :float}

    # Spline: interpolation points
    embeds_many :spline_points, Cadence.MissionDatabase.SplinePoint, on_replace: :delete
    field :spline_order, :integer, default: 1         # 0=step, 1=linear, 2=quadratic
    field :spline_extrapolate, :boolean, default: false

    # MathOperation: RPN expression
    field :math_operation_expression, :string
    # Postfix tokens for the expression
    field :math_operation_postfix, {:array, :string}

    # StateTable: value → string mapping
    field :state_table, :map                # %{integer => string}
    field :state_table_default, :string

    # Custom: Elixir module
    field :custom_module, :string           # e.g., "Cadence.Calibrators.MyCustom"
    field :custom_config, :map, default: %{}

    # Input parameter references (for algorithms that reference other params)
    field :input_parameter_refs, {:array, :string}

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.SplinePoint do
  use Ecto.Schema

  embedded_schema do
    field :raw, :float
    field :calibrated, :float
  end
end

defmodule Cadence.MissionDatabase.ContextCalibrator do
  @moduledoc """
  Calibrator applied when a condition is met.
  """

  use Ecto.Schema

  schema "context_calibrators" do
    belongs_to :data_type, Cadence.MissionDatabase.DataType
    belongs_to :algorithm, Cadence.MissionDatabase.Algorithm

    # Condition that must be true for this calibrator to apply
    embeds_one :match_criteria, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # Priority (lower = higher priority)
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
```

---

### 5. Container (Telemetry Packets)

```elixir
defmodule Cadence.MissionDatabase.Container do
  @moduledoc """
  Telemetry packet/container definition.

  Containers can inherit from base containers, with RestrictionCriteria
  defining the conditions under which a container is identified.

  This maps to XTCE SequenceContainer and COSMOS TELEMETRY.
  """

  use Ecto.Schema

  schema "containers" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string
    field :short_description, :string       # For UI display

    # Inheritance
    field :base_container_ref, :string      # Name of parent container
    field :abstract, :boolean, default: false  # If true, cannot be directly identified

    # Identification criteria (conditions that must be true for this container)
    embeds_one :restriction_criteria, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # Common identification fields (shortcuts for CCSDS)
    field :apid, :integer                   # CCSDS Application Process ID (0-2047)
    field :packet_type, :integer            # Additional type discriminator

    # Packet structure
    field :byte_order, Ecto.Enum, values: [:big_endian, :little_endian], default: :big_endian

    # Sync pattern for packet detection
    field :sync_pattern, :binary
    field :sync_pattern_offset_bits, :integer

    # Size information
    field :size_in_bits, :integer           # Fixed size, nil if variable
    field :max_size_in_bits, :integer       # Maximum for variable-size packets

    # Rate information
    field :expected_rate_hz, :float         # Expected packet rate
    field :rate_tolerance_percent, :float   # Acceptable deviation

    # Processing hints
    field :allow_short, :boolean, default: false  # Accept truncated packets
    field :hidden, :boolean, default: false       # Hide from UIs but still process

    # Entries (parameters in this container)
    has_many :container_entries, Cadence.MissionDatabase.ContainerEntry

    # Stream association
    belongs_to :stream, Cadence.MissionDatabase.Stream

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.ContainerEntry do
  @moduledoc """
  An entry in a container - can be a parameter, fixed value, or nested container.
  """

  use Ecto.Schema

  schema "container_entries" do
    belongs_to :container, Cadence.MissionDatabase.Container

    field :entry_type, Ecto.Enum, values: [
      :parameter_ref,       # Reference to a parameter
      :fixed_value,         # Fixed binary value
      :container_ref,       # Nested container reference
      :array_parameter_ref  # Array of parameters
    ]

    # Position in container
    field :bit_offset, :integer             # Absolute bit offset
    field :bit_offset_from, Ecto.Enum, values: [
      :container_start,     # From start of this container
      :previous_entry,      # Relative to previous entry end
      :base_container_end   # From end of inherited base container
    ], default: :container_start

    # For parameter_ref
    belongs_to :parameter, Cadence.MissionDatabase.Parameter
    field :parameter_ref, :string           # Name reference (resolved at load)

    # For fixed_value
    field :fixed_value, :binary
    field :fixed_value_size_bits, :integer

    # For container_ref
    field :container_ref, :string           # Name of nested container

    # For array_parameter_ref
    field :array_size, :integer             # Static array size
    field :array_size_ref, :string          # Dynamic size from parameter

    # Inclusion condition (only include if condition is true)
    embeds_one :include_condition, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # Display order for UIs
    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end
end
```

---

### 6. Parameter (Telemetry Items)

```elixir
defmodule Cadence.MissionDatabase.Parameter do
  @moduledoc """
  A telemetry parameter definition.

  Parameters reference a DataType for their type information.
  The DataType contains encoding, calibration, and alarm definitions.
  """

  use Ecto.Schema

  schema "parameters" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string                    # Unique within definition_set
    field :description, :string
    field :short_description, :string

    # Type reference
    belongs_to :data_type, Cadence.MissionDatabase.DataType
    field :data_type_ref, :string           # Name reference (resolved at load)

    # Parameter source
    field :parameter_source, Ecto.Enum, values: [
      :telemetry,           # From spacecraft telemetry
      :derived,             # Computed from other parameters
      :constant,            # Fixed value
      :local                # Ground-side parameter
    ], default: :telemetry

    # For derived parameters
    field :derivation_expression, :string   # Expression to compute value
    field :derivation_trigger, Ecto.Enum, values: [
      :on_parameter_update, # Recompute when any input changes
      :on_container_update, # Recompute when container is received
      :periodic             # Recompute on schedule
    ]
    field :derivation_trigger_refs, {:array, :string}  # Parameter names that trigger

    # System-level parameters (auto-generated)
    field :system_parameter, :boolean, default: false

    # Persistence (for stale data handling)
    field :persistence, :integer            # Samples to persist
    field :stale_timeout_ms, :integer       # Time until value considered stale

    # Significance for operations
    field :significance, Ecto.Enum, values: [
      :none, :watch, :warning, :distress, :critical, :severe
    ], default: :none

    # Recording/logging
    field :record_to_archive, :boolean, default: true
    field :record_rate_limit_hz, :float     # Max archive rate

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end
```

---

### 7. Alarm Definitions

```elixir
defmodule Cadence.MissionDatabase.AlarmDefinition do
  @moduledoc """
  Alarm/limit definition for a parameter.

  XTCE supports multiple alarm levels: watch, warning, distress, critical, severe.
  OpenC3 uses: red_low, yellow_low, yellow_high, red_high (plus green_low, green_high).

  We support both models.
  """

  use Ecto.Schema

  embedded_schema do
    # Static range alarms (XTCE model)
    embeds_one :watch_range, Cadence.MissionDatabase.AlarmRange
    embeds_one :warning_range, Cadence.MissionDatabase.AlarmRange
    embeds_one :distress_range, Cadence.MissionDatabase.AlarmRange
    embeds_one :critical_range, Cadence.MissionDatabase.AlarmRange
    embeds_one :severe_range, Cadence.MissionDatabase.AlarmRange

    # Change alarms
    field :change_per_second_warning, :float
    field :change_per_second_critical, :float

    # Delta alarms (change since last sample)
    field :delta_warning, :float
    field :delta_critical, :float

    # Persistence (samples out-of-limits before alarm)
    field :min_violations, :integer, default: 1

    # Actions on alarm
    field :alarm_actions, {:array, :string}  # Command refs or action names
  end
end

defmodule Cadence.MissionDatabase.AlarmRange do
  use Ecto.Schema

  embedded_schema do
    field :min_inclusive, :float
    field :max_inclusive, :float
    field :min_exclusive, :float
    field :max_exclusive, :float
  end
end

defmodule Cadence.MissionDatabase.ContextAlarm do
  @moduledoc """
  Context-dependent alarm that overrides default alarm based on conditions.
  """

  use Ecto.Schema

  schema "context_alarms" do
    belongs_to :data_type, Cadence.MissionDatabase.DataType

    # Condition that activates this alarm set
    embeds_one :match_criteria, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # The alarm definition when this context is active
    embeds_one :alarm_definition, Cadence.MissionDatabase.AlarmDefinition, on_replace: :update

    # Priority (lower = higher priority, evaluated in order)
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
```

---

### 8. MetaCommand (Command Definitions)

```elixir
defmodule Cadence.MissionDatabase.MetaCommand do
  @moduledoc """
  Command definition with arguments, constraints, and verifiers.

  Commands support inheritance via base_command_ref.
  """

  use Ecto.Schema

  schema "meta_commands" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string
    field :short_description, :string

    # Inheritance
    field :base_command_ref, :string        # Name of parent command
    field :abstract, :boolean, default: false

    # Identification
    field :opcode, :integer                 # Command opcode/function code

    # Safety classification (XTCE Significance)
    field :significance, Ecto.Enum, values: [
      :none, :watch, :warning, :distress, :critical, :severe
    ], default: :none
    field :significance_reason, :string     # Why this significance level

    # OpenC3-style hazard flags
    field :is_hazardous, :boolean, default: false
    field :hazard_description, :string
    field :requires_confirmation, :boolean, default: false
    field :is_restricted, :boolean, default: false  # Requires approval workflow

    # Operational constraints
    field :allowed_phases, {:array, :string}  # Mission phases where allowed
    field :disabled, :boolean, default: false
    field :disabled_reason, :string

    # Encoding configuration
    field :encoding_format, Ecto.Enum, values: [:binary, :ascii, :json]
    field :encoding_config, :map, default: %{}

    # Interlock (must wait for previous command verification)
    embeds_one :interlock, Cadence.MissionDatabase.CommandInterlock, on_replace: :update

    # Associations
    has_many :arguments, Cadence.MissionDatabase.Argument
    has_many :transmission_constraints, Cadence.MissionDatabase.TransmissionConstraint
    has_many :verifiers, Cadence.MissionDatabase.CommandVerifier

    # Command container (for binary encoding layout)
    has_one :command_container, Cadence.MissionDatabase.CommandContainer

    # Related items for UI
    field :related_telemetry_items, {:array, :string}
    field :related_screen, :string

    # Expected response
    field :expected_response_container, :string

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.CommandInterlock do
  @moduledoc """
  Interlock requiring previous command to reach verification stage.
  """

  use Ecto.Schema

  embedded_schema do
    field :previous_command_ref, :string
    field :verification_stage, Ecto.Enum, values: [
      :transferred_to_range, :sent_from_range, :received,
      :accepted, :queued, :executing, :complete
    ]
    field :verification_progress_percent, :integer  # For :executing stage
    field :suspendable, :boolean, default: false
  end
end
```

---

### 9. Argument (Command Parameters)

```elixir
defmodule Cadence.MissionDatabase.Argument do
  @moduledoc """
  Command argument definition.
  """

  use Ecto.Schema

  schema "arguments" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Type reference
    belongs_to :data_type, Cadence.MissionDatabase.DataType
    field :data_type_ref, :string

    # Position in command
    field :bit_offset, :integer
    field :bit_length, :integer

    # Value constraints
    field :required, :boolean, default: true
    field :default_value, :string
    field :fixed_value, :string             # Cannot be changed by operator

    # Argument assignment from base command
    field :assigned_value, :string          # Value assigned when inheriting

    # Range overrides (can narrow from type definition)
    field :min_value, :float
    field :max_value, :float
    field :valid_values, {:array, :string}  # For enums

    # Display
    field :display_order, :integer
    field :hidden, :boolean, default: false

    # Hazardous states (specific values that are hazardous)
    embeds_many :hazardous_states, Cadence.MissionDatabase.HazardousState, on_replace: :delete

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.HazardousState do
  @moduledoc """
  Marks specific argument values as hazardous.
  """

  use Ecto.Schema

  embedded_schema do
    field :value, :string
    field :description, :string
  end
end
```

---

### 10. TransmissionConstraint (Command Preconditions)

```elixir
defmodule Cadence.MissionDatabase.TransmissionConstraint do
  @moduledoc """
  Precondition that must be satisfied before command transmission.

  Maps to XTCE TransmissionConstraint.
  """

  use Ecto.Schema

  schema "transmission_constraints" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Condition that must be true
    embeds_one :match_criteria, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # Timeout for condition to become true
    field :timeout_ms, :integer

    # Can this constraint be suspended by operator?
    field :suspendable, :boolean, default: false

    # What happens if constraint fails
    field :on_failure, Ecto.Enum, values: [:block, :warn], default: :block

    # Order of evaluation
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
```

---

### 11. CommandVerifier (Command Verification)

```elixir
defmodule Cadence.MissionDatabase.CommandVerifier do
  @moduledoc """
  Verifies command execution by checking telemetry conditions.

  XTCE defines 8 verification stages:
  - transferred_to_range: Confirmed sent to communication system
  - sent_from_range: Confirmed transmitted to spacecraft
  - received: Spacecraft acknowledged receipt
  - accepted: Spacecraft accepted command for execution
  - queued: Command queued for later execution
  - executing: Command is being executed (can have progress %)
  - complete: Command execution finished successfully
  - failed: Command execution failed
  """

  use Ecto.Schema

  schema "command_verifiers" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    field :stage, Ecto.Enum, values: [
      :transferred_to_range, :sent_from_range, :received,
      :accepted, :queued, :executing, :complete, :failed
    ]

    # Condition that indicates this stage is reached
    embeds_one :match_criteria, Cadence.MissionDatabase.MatchCriteria, on_replace: :update

    # Alternative: simple telemetry item to watch
    field :telemetry_item_ref, :string      # e.g., "HEALTH.CMD_ACCEPT_COUNT"
    field :expected_value, :string
    field :comparison, Ecto.Enum, values: [
      :equal, :not_equal, :greater, :less, :greater_equal, :less_equal, :changed
    ]

    # Timeout waiting for this stage
    field :timeout_ms, :integer

    # For :executing stage, expected progress updates
    field :progress_parameter_ref, :string  # Parameter containing % complete

    # Actions on success/failure
    field :on_success_action, :string
    field :on_failure_action, :string
    field :on_timeout_action, :string

    timestamps(type: :utc_datetime)
  end
end
```

---

### 12. MatchCriteria (Conditions)

```elixir
defmodule Cadence.MissionDatabase.MatchCriteria do
  @moduledoc """
  A condition that can be evaluated against current telemetry state.

  Used for:
  - Container identification (RestrictionCriteria)
  - Transmission constraints
  - Context calibrators/alarms
  - Command verifiers
  - Conditional container entries
  """

  use Ecto.Schema

  embedded_schema do
    # Simple comparison
    field :parameter_ref, :string           # Parameter to check
    field :comparison, Ecto.Enum, values: [
      :equal, :not_equal, :greater, :less,
      :greater_equal, :less_equal,
      :in_range, :not_in_range
    ]
    field :value, :string                   # Value to compare against
    field :use_calibrated, :boolean, default: true

    # For range comparisons
    field :range_min, :float
    field :range_max, :float

    # Boolean expression (alternative to simple comparison)
    field :boolean_expression, :string      # e.g., "A > 10 AND (B == 'ON' OR C < 5)"

    # Compound conditions
    field :operator, Ecto.Enum, values: [:and, :or]
    embeds_many :conditions, Cadence.MissionDatabase.MatchCriteria, on_replace: :delete

    # Algorithm-based condition
    field :algorithm_ref, :string           # Algorithm that returns boolean
  end
end
```

---

### 13. Stream (Framing and Protocol)

```elixir
defmodule Cadence.MissionDatabase.Stream do
  @moduledoc """
  Defines framing protocol for telemetry/command streams.

  A stream describes how raw bytes are framed into packets and how
  packets are identified to their container definitions.
  """

  use Ecto.Schema

  schema "streams" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string

    # Stream type
    field :stream_type, Ecto.Enum, values: [:telemetry, :command, :bidirectional]

    # Framing protocol
    field :framing_protocol, Ecto.Enum, values: [
      :ccsds_aos,           # CCSDS Advanced Orbiting Systems
      :ccsds_packet,        # CCSDS Space Packet Protocol
      :ccsds_tc,            # CCSDS Telecommand
      :hdlc,                # HDLC framing
      :slip,                # Serial Line IP
      :length_prefixed,     # Simple length-prefixed frames
      :delimiter,           # Delimiter-based framing
      :fixed_length,        # Fixed-length frames
      :custom               # Custom framing module
    ]

    # Framing configuration
    field :sync_pattern, :binary
    field :frame_length, :integer           # For fixed_length
    field :length_field_offset, :integer    # For length_prefixed
    field :length_field_size, :integer
    field :delimiter, :binary               # For delimiter-based

    # Custom framing
    field :custom_framer_module, :string
    field :custom_framer_config, :map

    # Error detection
    field :error_detection, Ecto.Enum, values: [:none, :crc16, :crc32, :checksum]
    field :error_detection_offset, :integer
    field :error_detection_polynomial, :integer  # For CRC

    # Associated containers
    has_many :containers, Cadence.MissionDatabase.Container

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end
end
```

---

### 14. CommandContainer (Command Binary Layout)

```elixir
defmodule Cadence.MissionDatabase.CommandContainer do
  @moduledoc """
  Defines the binary layout of a command packet.

  Similar to Container but for commands.
  """

  use Ecto.Schema

  schema "command_containers" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Inheritance
    field :base_container_ref, :string

    # Layout
    field :byte_order, Ecto.Enum, values: [:big_endian, :little_endian]

    # Fixed header/trailer
    field :header, :binary
    field :trailer, :binary

    # Size
    field :size_in_bits, :integer           # Fixed size
    field :max_size_in_bits, :integer

    # Entries
    has_many :entries, Cadence.MissionDatabase.CommandContainerEntry

    timestamps(type: :utc_datetime)
  end
end

defmodule Cadence.MissionDatabase.CommandContainerEntry do
  use Ecto.Schema

  schema "command_container_entries" do
    belongs_to :command_container, Cadence.MissionDatabase.CommandContainer

    field :entry_type, Ecto.Enum, values: [
      :argument_ref, :fixed_value, :parameter_ref
    ]

    field :bit_offset, :integer

    # For argument_ref
    belongs_to :argument, Cadence.MissionDatabase.Argument

    # For fixed_value
    field :fixed_value, :binary
    field :fixed_value_size_bits, :integer

    # For parameter_ref (parameter value injected into command)
    field :parameter_ref, :string

    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end
end
```

---

## Summary: Differences from Current Implementation

### Major Additions Needed

| Component | Status | Priority | Notes |
|-----------|--------|----------|-------|
| `DataType` (shared types) | **NEW** | HIGH | Critical for XTCE; enables type reuse |
| `Container.base_container_ref` | **NEW** | HIGH | Required for inheritance |
| `Container.restriction_criteria` | **NEW** | HIGH | Required for packet identification |
| `TransmissionConstraint` | **NEW** | HIGH | Command preconditions from XTCE |
| `CommandVerifier` (multi-stage) | **ENHANCE** | HIGH | Current impl is single-stage |
| `Stream` | **NEW** | MEDIUM | Framing protocol definition |
| `MatchCriteria` (embedded) | **NEW** | HIGH | Used throughout for conditions |
| `Algorithm` (spline, math) | **ENHANCE** | MEDIUM | Add spline, RPN expression types |
| `ContextCalibrator` | **NEW** | MEDIUM | Condition-dependent calibration |
| `ContextAlarm` | **NEW** | MEDIUM | Condition-dependent alarms |
| `Unit` | **NEW** | LOW | Nice-to-have for SI conversion |
| `CommandContainer` | **NEW** | MEDIUM | Binary layout for commands |
| `Argument.hazardous_states` | **NEW** | MEDIUM | Per-value hazard flags |
| `MetaCommand.interlock` | **NEW** | MEDIUM | Sequential command constraints |

### Enhancements to Existing

| Component | Change | Notes |
|-----------|--------|-------|
| `PacketDefinition` → `Container` | Rename + add inheritance | Add `base_container_ref`, `restriction_criteria`, `abstract` |
| `PacketItem` → `Parameter` | Separate from container | Parameters defined independently, referenced by containers |
| `CommandDefinition` → `MetaCommand` | Align with XTCE | Add `base_command_ref`, `abstract`, `significance` |
| `Conversion` → `Algorithm` | Rename + expand | Add spline, math_operation types |

---

## Sources

- [XTCE 1.2 Specification (CCSDS 660x0b2)](https://ccsds.org/Pubs/660x0b2.pdf)
- [XTCE 1.3 Specification (OMG)](https://www.omg.org/spec/XTCE)
- [OpenC3 Telemetry Configuration](https://docs.openc3.com/docs/configuration/telemetry)
- [OpenC3 Command Configuration](https://docs.openc3.com/docs/configuration/command)
- [Yamcs XTCE Implementation](https://docs.yamcs.org/yamcs-server-manual/mdb/data-types/)
- [CCSDS SEDS Specification (876x0b1)](https://ccsds.org/Pubs/876x0b1.pdf)
