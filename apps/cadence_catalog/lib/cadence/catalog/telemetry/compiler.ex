defmodule Cadence.Catalog.Telemetry.Compiler do
  @moduledoc """
  Compiles canonical telemetry catalog snapshots into portable packet
  definitions and selector inputs.

  This compiler intentionally targets the existing definition-bound telemetry
  slice:

  - `Cadence.Telemetry.PacketDefinition`
  - persistence-independent selector and capability configuration documents

  It does not attempt to fully represent every canonical telemetry feature in
  the current runtime. Unsupported features produce diagnostics rather than
  silently disappearing.
  """

  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.MissionModel.{Canonical, LegacyNames}
  alias Cadence.Catalog.Telemetry.Compiler.{Result, SelectorInput}

  alias Cadence.Catalog.Telemetry.{
    MatchCriteria,
    Packet,
    PacketEntry,
    Point,
    Snapshot,
    Type
  }

  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @type compile_opt ::
          {:packet_definition_version, pos_integer()}
          | {:target_scope, :mission | :source_endpoint}
          | {:source_endpoint_ref, binary() | nil}
          | {:capability_family_key, atom()}

  @spec compile(Snapshot.t(), [compile_opt()]) :: Result.t()
  def compile(%Snapshot{} = snapshot, opts \\ []) when is_list(opts) do
    context = build_context(snapshot, opts)

    {packet_definitions, selector_inputs, diagnostics} =
      Enum.reduce(snapshot.packets, {[], [], []}, fn %Packet{} = packet, acc ->
        compile_packet(packet, context, acc)
      end)

    Result.new(%{
      packet_definitions: Enum.reverse(packet_definitions),
      selector_inputs: Enum.reverse(selector_inputs),
      diagnostics: Enum.reverse(diagnostics)
    })
  end

  defp compile_packet(%Packet{} = packet, context, {packet_defs, selectors, diagnostics}) do
    packet_diagnostics = packet_runtime_diagnostics(packet)

    if packet.abstract do
      {packet_defs, selectors, Enum.reverse(packet_diagnostics, diagnostics)}
    else
      case compile_packet_definition(packet, context) do
        {:ok, %PacketDefinition{} = packet_definition, entry_diagnostics} ->
          selector_input =
            compile_selector_input(packet, packet_definition, context, entry_diagnostics)

          {
            [packet_definition | packet_defs],
            [selector_input | selectors],
            Enum.reverse(entry_diagnostics, Enum.reverse(packet_diagnostics, diagnostics))
          }

        {:skip, entry_diagnostics} ->
          {packet_defs, selectors,
           Enum.reverse(entry_diagnostics, Enum.reverse(packet_diagnostics, diagnostics))}
      end
    end
  end

  defp compile_packet_definition(%Packet{} = packet, context) do
    point_by_id = Map.new(context.snapshot.points, &{&1.point_id, &1})
    type_by_id = Map.new(context.snapshot.types, &{&1.type_id, &1})

    {fields, diagnostics, supported?} =
      Enum.reduce(packet.entries, {[], [], true}, fn %PacketEntry{} = entry,
                                                     {fields, diagnostics, supported?} ->
        case compile_entry(packet, entry, point_by_id, type_by_id, context.parameter_paths) do
          {:field, %FieldDefinition{} = field, entry_diagnostics} ->
            {[field | fields], Enum.reverse(entry_diagnostics, diagnostics), supported?}

          {:omit, entry_diagnostics} ->
            {fields, Enum.reverse(entry_diagnostics, diagnostics), supported?}

          {:unsupported, entry_diagnostics} ->
            {fields, Enum.reverse(entry_diagnostics, diagnostics), false}
        end
      end)

    cond do
      not supported? ->
        {:skip, diagnostics}

      not is_integer(packet.apid) ->
        {:skip, diagnostics}

      true ->
        packet_definition =
          PacketDefinition.new(%{
            organization_id: context.snapshot.organization_id,
            mission_id: context.snapshot.mission_id,
            packet_definition_id: packet.packet_id,
            packet_name: packet.name,
            apid: packet.apid,
            version: context.packet_definition_version,
            fields: Enum.sort_by(fields, &{&1.offset_bits, &1.field_id})
          })

        {:ok, packet_definition, diagnostics}
    end
  end

  defp compile_selector_input(
         %Packet{} = packet,
         %PacketDefinition{} = packet_definition,
         context,
         diagnostics
       ) do
    SelectorInput.new(%{
      selector_input_id: packet.packet_id <> "_selector",
      packet_id: packet.packet_id,
      packet_definition_id: packet_definition.packet_definition_id,
      capability_instance_id: packet.packet_id <> "_telemetry",
      capability_family_key: context.capability_family_key,
      selector: %{
        scope: %{
          target_scope: context.target_scope,
          source_endpoint_ref: context.source_endpoint_ref
        },
        match: %{
          packet_kind: :space_packet,
          apid: packet.apid
        }
      },
      capability_config: %{
        config_type: :governed_packet_definition,
        document: %{
          "mission_id" => packet_definition.mission_id,
          "packet_definition_id" => packet_definition.packet_definition_id,
          "version" => packet_definition.version
        }
      },
      metadata: %{
        "packet_name" => packet.name,
        "diagnostic_count" => length(diagnostics)
      }
    })
  end

  defp compile_entry(
         %Packet{} = packet,
         %PacketEntry{} = entry,
         point_by_id,
         type_by_id,
         parameter_paths
       ) do
    case entry.entry_kind do
      :fixed_value ->
        {:omit,
         [
           diagnostic(
             :warning,
             "telemetry_compiler.fixed_value_omitted",
             "Fixed-value packet entries are omitted from the current runtime packet definition",
             packet,
             entry
           )
         ]}

      :point_ref ->
        compile_point_entry(packet, entry, point_by_id, type_by_id, parameter_paths)

      :nested_packet_ref ->
        {:unsupported,
         [
           diagnostic(
             :error,
             "telemetry_compiler.nested_packet_unsupported",
             "Nested packet entries are not supported by the current runtime packet definition compiler",
             packet,
             entry
           )
         ]}

      :array_point_ref ->
        {:unsupported,
         [
           diagnostic(
             :error,
             "telemetry_compiler.array_point_unsupported",
             "Array point entries are not supported by the current runtime packet definition compiler",
             packet,
             entry
           )
         ]}
    end
  end

  defp compile_point_entry(
         %Packet{} = packet,
         %PacketEntry{} = entry,
         point_by_id,
         type_by_id,
         parameter_paths
       ) do
    with :ok <- validate_entry_layout(packet, entry),
         {:ok, %Point{} = point} <- fetch_point(packet, entry, point_by_id),
         {:ok, %Type{} = point_type} <- fetch_type(packet, point, type_by_id),
         {:ok, field_data_type} <- compile_field_data_type(packet, entry, point, point_type),
         {:ok, size_bits} <- compile_field_size(packet, entry, point_type),
         {:ok, byte_order} <-
           compile_field_byte_order(packet, entry, point, point_type, size_bits) do
      field =
        FieldDefinition.new(%{
          field_id: point.point_id,
          parameter_id:
            parameter_paths
            |> Map.fetch!(point.point_id)
            |> then(&Canonical.semantic_id(:parameter, &1)),
          qualified_name: Map.fetch!(parameter_paths, point.point_id),
          name: point.name,
          offset_bits: entry.bit_offset,
          size_bits: size_bits,
          data_type: field_data_type,
          byte_order: byte_order,
          engineering_unit: point.unit_id
        })

      {:field, field, field_diagnostics(packet, entry, point, point_type)}
    else
      {:error, diagnostics} when is_list(diagnostics) ->
        {:unsupported, diagnostics}
    end
  end

  defp field_diagnostics(packet, entry, point, %Type{base_type: :binary} = point_type) do
    [custom_application_candidate_diagnostic(packet, entry, point, point_type)]
  end

  defp field_diagnostics(_packet, _entry, _point, _point_type), do: []

  defp validate_entry_layout(%Packet{} = packet, %PacketEntry{} = entry) do
    cond do
      not is_integer(entry.bit_offset) ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.absolute_bit_offset_required",
             "Packet entries must have an absolute bit offset for the current runtime packet definition compiler",
             packet,
             entry
           )
         ]}

      entry.bit_offset_from != :packet_start ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.relative_offsets_unsupported",
             "Relative packet entry offsets are not supported by the current runtime packet definition compiler",
             packet,
             entry
           )
         ]}

      entry.include_condition != nil ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.conditional_entries_unsupported",
             "Conditional packet entries are not supported by the current runtime packet definition compiler",
             packet,
             entry
           )
         ]}

      true ->
        :ok
    end
  end

  defp fetch_point(%Packet{} = packet, %PacketEntry{} = entry, point_by_id) do
    case Map.fetch(point_by_id, entry.point_id) do
      {:ok, %Point{} = point} ->
        {:ok, point}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.point_not_found",
             "Packet entry references a telemetry point that is not present in the snapshot",
             packet,
             entry,
             %{"point_id" => entry.point_id}
           )
         ]}
    end
  end

  defp fetch_type(%Packet{} = packet, %Point{} = point, type_by_id) do
    case Map.fetch(type_by_id, point.type_id) do
      {:ok, %Type{} = point_type} ->
        {:ok, point_type}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.type_not_found",
             "Telemetry point references a type that is not present in the snapshot",
             packet,
             point,
             %{"point_id" => point.point_id, "type_id" => point.type_id}
           )
         ]}
    end
  end

  defp compile_field_data_type(%Packet{} = packet, source, %Point{} = point, %Type{} = point_type) do
    case point_type.base_type do
      :integer ->
        compile_integer_data_type(packet, source, point, point_type)

      :float ->
        compile_float_data_type(packet, source, point, point_type)

      :enumerated ->
        compile_integer_data_type(packet, source, point, point_type)

      :boolean ->
        compile_boolean_data_type(packet, source, point, point_type)

      :binary ->
        {:ok, :binary}

      unsupported_base_type ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.type_unsupported",
             "Telemetry point type is not supported by the current runtime packet definition compiler",
             packet,
             source,
             %{
               "point_id" => point.point_id,
               "type_id" => point.type_id,
               "base_type" => Atom.to_string(unsupported_base_type),
               "diagnostic_stage" => "built_in_telemetry_binding"
             }
           )
         ]}
    end
  end

  defp compile_integer_data_type(
         %Packet{},
         _source,
         %Point{},
         %Type{} = point_type
       ),
       do: {:ok, integer_data_type(point_type)}

  defp compile_float_data_type(%Packet{} = packet, source, %Point{} = point, %Type{} = point_type) do
    encoding = point_type.encoding

    cond do
      is_nil(encoding) ->
        {:ok, :float}

      encoding.size_bits in [32, 64] ->
        {:ok, :float}

      is_integer(encoding.size_bits) ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.float_size_unsupported",
             "Current runtime packet definition compilation only supports 32-bit and 64-bit float encodings",
             packet,
             source,
             %{
               "point_id" => point.point_id,
               "type_id" => point.type_id,
               "size_bits" => encoding.size_bits
             }
           )
         ]}

      true ->
        {:ok, :float}
    end
  end

  defp compile_field_byte_order(
         %Packet{} = packet,
         source,
         %Point{} = point,
         %Type{} = point_type,
         size_bits
       ) do
    encoding = point_type.encoding

    cond do
      is_nil(encoding) ->
        {:ok, :big_endian}

      point_type.base_type in [:integer, :enumerated] ->
        compile_integer_byte_order(packet, source, point, point_type, size_bits)

      point_type.base_type == :float ->
        compile_float_byte_order(packet, source, point, point_type, size_bits)

      true ->
        {:ok, encoding.byte_order}
    end
  end

  defp compile_boolean_data_type(
         %Packet{} = packet,
         source,
         %Point{} = point,
         %Type{} = point_type
       ) do
    encoding = point_type.encoding

    cond do
      is_nil(encoding) ->
        {:ok, :bool}

      encoding.size_bits == 1 ->
        {:ok, :bool}

      true ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.bool_size_unsupported",
             "Current runtime packet definition compilation only supports one-bit boolean encodings",
             packet,
             source,
             %{
               "point_id" => point.point_id,
               "type_id" => point.type_id,
               "size_bits" => encoding.size_bits
             }
           )
         ]}
    end
  end

  defp compile_field_size(%Packet{} = packet, source, %Type{} = point_type) do
    case point_type.encoding do
      %{size_bits: size_bits} when is_integer(size_bits) and size_bits > 0 ->
        {:ok, size_bits}

      _missing_encoding ->
        {:error,
         [
           diagnostic(
             :error,
             "telemetry_compiler.encoding_size_missing",
             "Telemetry point type is missing a fixed encoded size required by the current runtime packet definition compiler",
             packet,
             source,
             %{"type_id" => point_type.type_id}
           )
         ]}
    end
  end

  defp integer_data_type(%Type{} = point_type) do
    encoding = point_type.encoding

    cond do
      encoding == nil ->
        :uint

      encoding.signed ->
        :int

      encoding.integer_encoding in [:twos_complement, :sign_magnitude, :ones_complement] ->
        :int

      true ->
        :uint
    end
  end

  defp integer_encoding_requires_byte_order?(%{size_bits: size_bits})
       when is_integer(size_bits) and size_bits > 8,
       do: true

  defp integer_encoding_requires_byte_order?(_encoding), do: false

  defp compile_integer_byte_order(
         %Packet{} = packet,
         source,
         %Point{} = point,
         %Type{} = point_type,
         size_bits
       ) do
    encoding = point_type.encoding

    if encoding.byte_order == :little_endian and
         integer_encoding_requires_byte_order?(encoding) and
         not little_endian_field_byte_aligned?(source, size_bits) do
      {:error,
       [
         diagnostic(
           :error,
           "telemetry_compiler.integer_little_endian_non_byte_aligned_unsupported",
           "Current runtime packet definition compilation only supports byte-aligned little-endian multi-byte integer fields",
           packet,
           source,
           %{
             "point_id" => point.point_id,
             "type_id" => point.type_id,
             "bit_offset" => source.bit_offset,
             "size_bits" => size_bits
           }
         )
       ]}
    else
      {:ok, encoding.byte_order}
    end
  end

  defp compile_float_byte_order(
         %Packet{} = packet,
         source,
         %Point{} = point,
         %Type{} = point_type,
         size_bits
       ) do
    encoding = point_type.encoding

    if encoding.byte_order == :little_endian and
         not little_endian_field_byte_aligned?(source, size_bits) do
      {:error,
       [
         diagnostic(
           :error,
           "telemetry_compiler.float_little_endian_non_byte_aligned_unsupported",
           "Current runtime packet definition compilation only supports byte-aligned little-endian float fields",
           packet,
           source,
           %{
             "point_id" => point.point_id,
             "type_id" => point.type_id,
             "bit_offset" => source.bit_offset,
             "size_bits" => size_bits
           }
         )
       ]}
    else
      {:ok, encoding.byte_order}
    end
  end

  defp little_endian_field_byte_aligned?(%PacketEntry{} = entry, size_bits)
       when is_integer(entry.bit_offset) and is_integer(size_bits) do
    rem(entry.bit_offset, 8) == 0 and rem(size_bits, 8) == 0
  end

  defp little_endian_field_byte_aligned?(_entry, _size_bits), do: false

  defp packet_runtime_diagnostics(%Packet{} = packet) do
    []
    |> maybe_add_abstract_packet_diagnostic(packet)
    |> maybe_add_missing_apid_diagnostic(packet)
    |> maybe_add_match_criteria_warning(packet)
  end

  defp maybe_add_abstract_packet_diagnostic(diagnostics, %Packet{abstract: true} = packet) do
    [
      diagnostic(
        :warning,
        "telemetry_compiler.abstract_packet_skipped",
        "Abstract packets are not compiled into current runtime packet definitions",
        packet,
        packet
      )
      | diagnostics
    ]
  end

  defp maybe_add_abstract_packet_diagnostic(diagnostics, %Packet{}), do: diagnostics

  defp maybe_add_missing_apid_diagnostic(diagnostics, %Packet{apid: apid} = packet)
       when not is_integer(apid) do
    [
      diagnostic(
        :error,
        "telemetry_compiler.apid_required",
        "Current runtime packet definition compilation requires packet APID identification",
        packet,
        packet
      )
      | diagnostics
    ]
  end

  defp maybe_add_missing_apid_diagnostic(diagnostics, %Packet{}), do: diagnostics

  defp maybe_add_match_criteria_warning(
         diagnostics,
         %Packet{
           apid: apid,
           packet_type: packet_type,
           match_criteria: %MatchCriteria{}
         } = packet
       )
       when is_integer(apid) and (not is_nil(packet_type) or packet.match_criteria != nil) do
    [
      diagnostic(
        :warning,
        "telemetry_compiler.selector_narrowed",
        "Current runtime selector compilation only preserves APID-based packet routing",
        packet,
        packet,
        %{
          "packet_type" => packet_type
        }
      )
      | diagnostics
    ]
  end

  defp maybe_add_match_criteria_warning(diagnostics, %Packet{}), do: diagnostics

  defp build_context(%Snapshot{} = snapshot, opts) do
    %{
      snapshot: snapshot,
      packet_definition_version: Keyword.get(opts, :packet_definition_version, 1),
      target_scope: Keyword.get(opts, :target_scope, :mission),
      source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref),
      capability_family_key:
        Keyword.get(opts, :capability_family_key, :definition_bound_telemetry),
      parameter_paths: LegacyNames.paths(snapshot.points, & &1.point_id, :parameter, & &1.name)
    }
  end

  defp diagnostic(severity, code, message, %Packet{} = packet, source, metadata \\ %{}) do
    source_id = diagnostic_source_id(source)
    source_kind = diagnostic_source_kind(source)
    path = diagnostic_path(packet, source)

    Diagnostic.new(%{
      severity: severity,
      code: code,
      message: message,
      path: path,
      metadata:
        Map.merge(
          %{
            "packet_id" => packet.packet_id,
            "source_kind" => source_kind,
            "source_id" => source_id
          },
          metadata
        )
    })
  end

  defp diagnostic_source_id(%PacketEntry{packet_entry_id: packet_entry_id}), do: packet_entry_id
  defp diagnostic_source_id(%Point{point_id: point_id}), do: point_id
  defp diagnostic_source_id(%Packet{packet_id: packet_id}), do: packet_id

  defp diagnostic_source_kind(%PacketEntry{}), do: "packet_entry"
  defp diagnostic_source_kind(%Point{}), do: "point"
  defp diagnostic_source_kind(%Packet{}), do: "packet"

  defp diagnostic_path(%Packet{} = packet, %PacketEntry{} = entry) do
    ["packets", packet.packet_id, "entries", entry.packet_entry_id]
  end

  defp diagnostic_path(%Packet{} = packet, %Point{} = point) do
    ["packets", packet.packet_id, "points", point.point_id]
  end

  defp diagnostic_path(%Packet{} = packet, %Packet{}) do
    ["packets", packet.packet_id]
  end

  defp custom_application_candidate_diagnostic(
         %Packet{} = packet,
         source,
         %Point{} = point,
         %Type{} = point_type
       ) do
    diagnostic(
      :warning,
      "telemetry_compiler.available_for_custom_application_binding",
      "Binary packet content is preserved in the imported catalog but is not compiled into built-in telemetry; this packet remains available for custom application binding",
      packet,
      source,
      %{
        "point_id" => point.point_id,
        "type_id" => point.type_id,
        "base_type" => Atom.to_string(point_type.base_type),
        "diagnostic_stage" => "built_in_telemetry_binding",
        "consumption_status" => "available_for_custom_application_binding",
        "consumption_summary" => "Preserved in catalog, not compiled into built-in telemetry",
        "custom_application_candidate_reason" => "binary_payload_field"
      }
    )
  end
end
