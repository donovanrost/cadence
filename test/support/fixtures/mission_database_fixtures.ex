defmodule Cadence.MissionDatabaseFixtures do
  @moduledoc """
  Test helpers for creating Mission Database entities.
  """

  alias Cadence.Repo

  alias Cadence.MissionDatabase.{
    Algorithm,
    Argument,
    CommandContainer,
    CommandContainerEntry,
    CommandVerifier,
    Container,
    ContainerEntry,
    ContextAlarm,
    ContextCalibrator,
    Database,
    DataType,
    DefinitionSet,
    DerivedItem,
    MetaCommand,
    Parameter,
    Stream,
    TransmissionConstraint,
    Unit
  }

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures

  # ============================================================================
  # Database (Catalog Entry)
  # ============================================================================

  def database_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    {_org, mission} = get_or_create_org_mission(attrs)

    attrs =
      attrs
      |> Map.drop([:organization, :mission])
      |> Enum.into(%{
        mission_id: mission.id,
        name: "Test Database",
        slug: "test-database-#{System.unique_integer([:positive])}",
        description: "Test database for fixtures"
      })

    %Database{}
    |> Database.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # DefinitionSet
  # ============================================================================

  def definition_set_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    {org, mission, database} = get_or_create_org_mission_database(attrs)

    attrs =
      attrs
      |> Map.drop([:organization, :mission, :database])
      |> Enum.into(%{
        organization_id: org.id,
        database_id: database.id,
        name: "Test Definition Set",
        version: "1.0.#{System.unique_integer([:positive])}",
        description: "Test definition set",
        source_format: :yaml,
        source_filename: "test_database.yaml",
        source_hash: "abc123#{System.unique_integer([:positive])}"
      })

    %DefinitionSet{}
    |> DefinitionSet.changeset(attrs)
    |> Repo.insert!()
  end

  def published_definition_set_fixture(attrs \\ %{}) do
    ds = definition_set_fixture(attrs)
    {:ok, published} = DefinitionSet.publish(ds)
    published
  end

  # ============================================================================
  # Unit
  # ============================================================================

  def unit_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "unit-#{System.unique_integer([:positive])}",
        symbol: "u",
        description: "Test unit"
      })

    %Unit{}
    |> Unit.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # Algorithm (Calibrator)
  # ============================================================================

  def algorithm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "calibrator-#{System.unique_integer([:positive])}",
        algorithm_type: :polynomial,
        polynomial_coefficients: [0.0, 1.0]
      })

    %Algorithm{}
    |> Algorithm.changeset(attrs)
    |> Repo.insert!()
  end

  def polynomial_calibrator_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    algorithm_fixture(
      Map.merge(attrs, %{
        algorithm_type: :polynomial,
        polynomial_coefficients: [0.0, 0.01, 0.0001]
      })
    )
  end

  def state_table_calibrator_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    algorithm_fixture(
      Map.merge(attrs, %{
        algorithm_type: :state_table,
        state_table: %{
          0 => "OFF",
          1 => "ON",
          2 => "STANDBY"
        }
      })
    )
  end

  def spline_calibrator_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    algorithm_fixture(
      Map.merge(attrs, %{
        algorithm_type: :spline,
        spline_points: [
          %{raw: 0, calibrated: 0.0},
          %{raw: 100, calibrated: 25.0},
          %{raw: 200, calibrated: 50.0},
          %{raw: 400, calibrated: 100.0}
        ]
      })
    )
  end

  # ============================================================================
  # DataType
  # ============================================================================

  def data_type_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "type-#{System.unique_integer([:positive])}",
        base_type: :integer,
        encoding: %{
          encoding_type: :integer,
          size_in_bits: 16,
          byte_order: :big_endian,
          integer_encoding: :unsigned
        }
      })

    %DataType{}
    |> DataType.changeset(attrs)
    |> Repo.insert!()
  end

  def float_data_type_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    data_type_fixture(
      Map.merge(attrs, %{
        base_type: :float,
        encoding: %{
          encoding_type: :float,
          size_in_bits: 32,
          byte_order: :big_endian
        }
      })
    )
  end

  def enumerated_data_type_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    data_type_fixture(
      Map.merge(attrs, %{
        base_type: :enumerated,
        encoding: %{
          encoding_type: :integer,
          size_in_bits: 8,
          integer_encoding: :unsigned
        },
        enumerations: [
          %{value: 0, label: "OFF"},
          %{value: 1, label: "ON"},
          %{value: 2, label: "ERROR"}
        ]
      })
    )
  end

  def string_data_type_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    data_type_fixture(
      Map.merge(attrs, %{
        base_type: :string,
        encoding: %{
          encoding_type: :string,
          size_in_bits: 256,
          charset: "UTF-8",
          string_termination: :fixed_length
        }
      })
    )
  end

  # ============================================================================
  # ContextCalibrator
  # ============================================================================

  def context_calibrator_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    data_type = attrs[:data_type] || data_type_fixture()
    ds = Repo.get!(DefinitionSet, data_type.definition_set_id)
    algorithm = attrs[:algorithm] || algorithm_fixture(definition_set: ds)

    attrs =
      attrs
      |> Map.drop([:data_type, :algorithm, :definition_set])
      |> Enum.into(%{
        data_type_id: data_type.id,
        algorithm_id: algorithm.id,
        match_criteria: %{
          parameter_ref: "MODE.STATUS",
          comparison: :equal,
          value: "1"
        },
        display_order: 0
      })

    %ContextCalibrator{}
    |> ContextCalibrator.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # ContextAlarm
  # ============================================================================

  def context_alarm_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    data_type = attrs[:data_type] || data_type_fixture()

    attrs =
      attrs
      |> Map.drop([:data_type, :definition_set])
      |> Enum.into(%{
        data_type_id: data_type.id,
        match_criteria: %{
          parameter_ref: "MODE.STATUS",
          comparison: :equal,
          value: "1"
        },
        alarm_definition: %{
          watch_range: %{min_inclusive: 10.0, max_inclusive: 90.0},
          warning_range: %{min_inclusive: 5.0, max_inclusive: 95.0},
          critical_range: %{min_inclusive: 0.0, max_inclusive: 100.0}
        },
        display_order: 0
      })

    %ContextAlarm{}
    |> ContextAlarm.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # Stream
  # ============================================================================

  def stream_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "stream-#{System.unique_integer([:positive])}",
        stream_type: :telemetry,
        framing_protocol: :fixed_length,
        frame_length: 256,
        bit_rate: 115_200,
        sync_pattern: <<0x1A, 0xCF, 0xFC, 0x1D>>
      })

    %Stream{}
    |> Stream.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # Container (Telemetry Packet)
  # ============================================================================

  def container_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission, :stream])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "container-#{System.unique_integer([:positive])}",
        description: "Test telemetry container",
        byte_order: :big_endian
      })

    %Container{}
    |> Container.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # Parameter
  # ============================================================================

  def parameter_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)
    data_type = attrs[:data_type]

    # If no data_type provided, create one or use a ref
    {type_id, type_ref} =
      cond do
        data_type ->
          {data_type.id, nil}

        attrs[:data_type_ref] ->
          {nil, attrs[:data_type_ref]}

        attrs[:parameter_source] in [:derived, :constant, :local] ->
          # Non-telemetry parameters don't require data_type
          {nil, nil}

        true ->
          # Create a data_type for telemetry parameters
          dt = data_type_fixture(definition_set: ds)
          {dt.id, nil}
      end

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission, :data_type])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        data_type_id: type_id,
        data_type_ref: type_ref,
        name: "param-#{System.unique_integer([:positive])}",
        description: "Test parameter"
      })

    %Parameter{}
    |> Parameter.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # ContainerEntry
  # ============================================================================

  def container_entry_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    container = attrs[:container] || container_fixture()
    ds = Repo.get!(DefinitionSet, container.definition_set_id)
    parameter = attrs[:parameter] || parameter_fixture(definition_set: ds)

    attrs =
      attrs
      |> Map.drop([:container, :parameter, :definition_set])
      |> Enum.into(%{
        container_id: container.id,
        entry_type: :parameter_ref,
        parameter_id: parameter.id,
        bit_offset: 0,
        display_order: 0
      })

    %ContainerEntry{}
    |> ContainerEntry.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # MetaCommand
  # ============================================================================

  def meta_command_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    ds = get_or_create_definition_set(attrs)
    # Get mission_id through the database association
    database = Repo.get!(Database, ds.database_id)

    attrs =
      attrs
      |> Map.drop([:definition_set, :organization, :mission])
      |> Enum.into(%{
        organization_id: ds.organization_id,
        mission_id: database.mission_id,
        definition_set_id: ds.id,
        name: "command-#{System.unique_integer([:positive])}",
        description: "Test command",
        opcode: System.unique_integer([:positive]) |> rem(65_536)
      })

    %MetaCommand{}
    |> MetaCommand.changeset(attrs)
    |> Repo.insert!()
  end

  def hazardous_command_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)

    meta_command_fixture(
      Map.merge(attrs, %{
        is_hazardous: true,
        hazard_description: "This command will reset the spacecraft!",
        requires_confirmation: true,
        significance: :critical
      })
    )
  end

  # ============================================================================
  # Argument
  # ============================================================================

  def argument_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    meta_command = attrs[:meta_command] || meta_command_fixture()
    data_type = attrs[:data_type]

    attrs =
      attrs
      |> Map.drop([:meta_command, :data_type, :definition_set])
      |> Enum.into(%{
        meta_command_id: meta_command.id,
        data_type_id: data_type && data_type.id,
        name: "arg-#{System.unique_integer([:positive])}",
        description: "Test argument",
        display_order: 0
      })

    %Argument{}
    |> Argument.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # TransmissionConstraint
  # ============================================================================

  def transmission_constraint_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    meta_command = attrs[:meta_command] || meta_command_fixture()

    attrs =
      attrs
      |> Map.drop([:meta_command, :definition_set])
      |> Enum.into(%{
        meta_command_id: meta_command.id,
        name: "constraint-#{System.unique_integer([:positive])}",
        timeout_ms: 5000,
        match_criteria: %{
          parameter_ref: "HEALTH.MODE",
          comparison: :equal,
          value: "SAFE"
        }
      })

    %TransmissionConstraint{}
    |> TransmissionConstraint.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # CommandVerifier
  # ============================================================================

  def command_verifier_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    meta_command = attrs[:meta_command] || meta_command_fixture()

    attrs =
      attrs
      |> Map.drop([:meta_command, :definition_set])
      |> Enum.into(%{
        meta_command_id: meta_command.id,
        stage: :complete,
        telemetry_item_ref: "CMD_STATUS.ACK_COUNT",
        comparison: :changed,
        timeout_ms: 10_000
      })

    %CommandVerifier{}
    |> CommandVerifier.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # CommandContainer
  # ============================================================================

  def command_container_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    meta_command = attrs[:meta_command] || meta_command_fixture()

    attrs =
      attrs
      |> Map.drop([:meta_command, :definition_set])
      |> Enum.into(%{
        meta_command_id: meta_command.id,
        name: "cmd-container-#{System.unique_integer([:positive])}",
        byte_order: :big_endian,
        size_in_bits: 64
      })

    %CommandContainer{}
    |> CommandContainer.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # CommandContainerEntry
  # ============================================================================

  def command_container_entry_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    command_container = attrs[:command_container] || command_container_fixture()
    argument = attrs[:argument]

    entry_type = attrs[:entry_type] || if argument, do: :argument_ref, else: :fixed_value

    base_attrs = %{
      command_container_id: command_container.id,
      entry_type: entry_type,
      bit_offset: 0,
      display_order: 0
    }

    type_attrs =
      case entry_type do
        :argument_ref ->
          cmd = Repo.get!(MetaCommand, command_container.meta_command_id)
          arg = argument || argument_fixture(meta_command: cmd)
          %{argument_id: arg.id}

        :fixed_value ->
          %{fixed_value: <<0x45>>, fixed_value_size_bits: 8}

        :parameter_ref ->
          %{parameter_ref: "CONFIG.VALUE"}
      end

    final_attrs =
      attrs
      |> Map.drop([:command_container, :argument, :definition_set, :entry_type])
      |> Enum.into(Map.merge(base_attrs, type_attrs))

    %CommandContainerEntry{}
    |> CommandContainerEntry.changeset(final_attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # DerivedItem
  # ============================================================================

  def derived_item_fixture(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    {org, mission} = get_or_create_org_mission(attrs)

    attrs =
      attrs
      |> Map.drop([:organization, :mission])
      |> Enum.into(%{
        organization_id: org.id,
        mission_id: mission.id,
        name: "DERIVED_#{System.unique_integer([:positive])}",
        expression: "POWER.VOLTAGE * POWER.CURRENT",
        source_items: ["POWER.VOLTAGE", "POWER.CURRENT"],
        units: "W",
        data_type: "float"
      })

    %DerivedItem{}
    |> DerivedItem.changeset(attrs)
    |> Repo.insert!()
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp ensure_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp ensure_map(attrs) when is_map(attrs), do: attrs

  defp get_or_create_org_mission(attrs) do
    org = attrs[:organization] || organization_fixture()

    mission =
      attrs[:mission] ||
        mission_fixture(organization: org)

    {org, mission}
  end

  defp get_or_create_org_mission_database(attrs) do
    {org, mission} = get_or_create_org_mission(attrs)

    database =
      attrs[:database] ||
        database_fixture(organization: org, mission: mission)

    {org, mission, database}
  end

  defp get_or_create_definition_set(attrs) do
    case attrs[:definition_set] do
      nil ->
        definition_set_fixture(Map.take(attrs, [:organization, :mission, :database]))

      %DefinitionSet{} = ds ->
        ds

      other ->
        raise "definition_set must be a DefinitionSet struct, got: #{inspect(other)}"
    end
  end

  defp get_or_create_database(attrs, mission) do
    case attrs[:database] do
      nil ->
        database_fixture(mission: mission)

      %Database{} = db ->
        db

      other ->
        raise "database must be a Database struct, got: #{inspect(other)}"
    end
  end
end
