defmodule Cadence.Catalog.ImportExecution.ResultBuilder do
  @moduledoc false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  def build_document(
        import_run_id,
        telemetry_snapshot,
        telemetry_runtime_artifacts,
        binding_set,
        command_snapshot,
        command_compiler_result
      ) do
    %{
      "import_run_id" => import_run_id,
      "primary_snapshot_id" => primary_snapshot_id(telemetry_snapshot, command_snapshot),
      "snapshot" =>
        telemetry_snapshot_summary(telemetry_snapshot) ||
          command_snapshot_summary(command_snapshot),
      "telemetry_snapshot" => telemetry_snapshot_summary(telemetry_snapshot),
      "telemetry_runtime" =>
        telemetry_runtime_summary(telemetry_snapshot, telemetry_runtime_artifacts),
      "packet_definitions" => telemetry_packet_definitions(telemetry_runtime_artifacts),
      "selector_input_count" => telemetry_selector_input_count(telemetry_runtime_artifacts),
      "binding_set" =>
        case binding_set do
          %BindingSet{} ->
            %{
              "binding_set_id" => binding_set.binding_set_id,
              "version" => binding_set.version,
              "capability_instance_count" => length(binding_set.capability_instances),
              "rule_count" => length(binding_set.rules)
            }

          nil ->
            nil
        end,
      "command_snapshot" => command_snapshot_summary(command_snapshot),
      "command_runtime" => command_runtime_summary(command_compiler_result)
    }
  end

  def primary_snapshot_id(%TelemetrySnapshot{snapshot_id: snapshot_id}, _command_snapshot),
    do: snapshot_id

  def primary_snapshot_id(nil, %CommandSnapshot{snapshot_id: snapshot_id}), do: snapshot_id
  def primary_snapshot_id(nil, nil), do: nil

  def imported_definition_count(telemetry_snapshot, command_snapshot) do
    telemetry_count =
      case telemetry_snapshot do
        %TelemetrySnapshot{} = snapshot -> length(snapshot.packets)
        nil -> 0
      end

    command_count =
      case command_snapshot do
        %CommandSnapshot{} = snapshot -> length(snapshot.command_definitions)
        nil -> 0
      end

    telemetry_count + command_count
  end

  def telemetry_compiler_diagnostics(nil), do: []

  def telemetry_compiler_diagnostics(%{compiler_result: %{diagnostics: diagnostics}})
      when is_list(diagnostics),
      do: diagnostics

  def telemetry_compiler_diagnostics(_other), do: []

  defp telemetry_snapshot_summary(nil), do: nil

  defp telemetry_snapshot_summary(%TelemetrySnapshot{} = snapshot) do
    %{
      "snapshot_id" => snapshot.snapshot_id,
      "snapshot_name" => snapshot.snapshot_name,
      "snapshot_version" => snapshot.snapshot_version,
      "packet_count" => length(snapshot.packets),
      "point_count" => length(snapshot.points),
      "type_count" => length(snapshot.types),
      "unit_count" => length(snapshot.units),
      "calibration_algorithm_count" => length(snapshot.calibration_algorithms)
    }
  end

  defp telemetry_packet_definitions(nil), do: []

  defp telemetry_packet_definitions(%{compiler_result: %{packet_definitions: packet_definitions}})
       when is_list(packet_definitions) do
    Enum.map(packet_definitions, fn packet_definition ->
      %{
        "packet_definition_id" => packet_definition.packet_definition_id,
        "packet_name" => packet_definition.packet_name,
        "apid" => packet_definition.apid,
        "field_count" => length(packet_definition.fields)
      }
    end)
  end

  defp telemetry_packet_definitions(_other), do: []

  defp telemetry_selector_input_count(nil), do: 0

  defp telemetry_selector_input_count(%{compiler_result: %{selector_inputs: selector_inputs}})
       when is_list(selector_inputs),
       do: length(selector_inputs)

  defp telemetry_selector_input_count(_other), do: 0

  defp telemetry_runtime_summary(nil, _telemetry_runtime_artifacts), do: nil

  defp telemetry_runtime_summary(
         %TelemetrySnapshot{} = snapshot,
         %{compiler_result: %{packet_definitions: packet_definitions, diagnostics: diagnostics}}
       )
       when is_list(packet_definitions) and is_list(diagnostics) do
    custom_application_candidate_packets =
      custom_application_candidate_packets(snapshot, diagnostics)

    %{
      "packet_count" => length(snapshot.packets),
      "built_in_telemetry_packet_count" =>
        Enum.count(packet_definitions, &built_in_telemetry_packet?/1),
      "compiler_diagnostic_count" => length(diagnostics),
      "custom_application_candidate_packet_count" => length(custom_application_candidate_packets),
      "custom_application_candidate_packets" => custom_application_candidate_packets
    }
  end

  defp telemetry_runtime_summary(%TelemetrySnapshot{} = snapshot, _other) do
    %{
      "packet_count" => length(snapshot.packets),
      "built_in_telemetry_packet_count" => 0,
      "compiler_diagnostic_count" => 0,
      "custom_application_candidate_packet_count" => 0,
      "custom_application_candidate_packets" => []
    }
  end

  defp built_in_telemetry_packet?(packet_definition) do
    Enum.any?(packet_definition.fields, &(&1.data_type in [:uint, :int, :float, :bool]))
  end

  defp custom_application_candidate_packets(%TelemetrySnapshot{} = snapshot, diagnostics) do
    packet_names_by_id = Map.new(snapshot.packets, &{&1.packet_id, &1.name})

    diagnostics
    |> Enum.filter(fn diagnostic ->
      diagnostic.metadata["consumption_status"] == "available_for_custom_application_binding"
    end)
    |> Enum.reduce(%{}, fn diagnostic, acc ->
      packet_id = diagnostic.metadata["packet_id"]
      packet_name = Map.get(packet_names_by_id, packet_id)

      if is_binary(packet_id) do
        Map.put_new(acc, packet_id, %{
          "packet_id" => packet_id,
          "packet_name" => packet_name,
          "reason" =>
            diagnostic.metadata["custom_application_candidate_reason"] ||
              "custom_application_candidate"
        })
      else
        acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1["packet_name"] || "", &1["packet_id"]})
  end

  defp command_snapshot_summary(nil), do: nil

  defp command_snapshot_summary(%CommandSnapshot{} = snapshot) do
    %{
      "snapshot_id" => snapshot.snapshot_id,
      "snapshot_name" => snapshot.snapshot_name,
      "snapshot_version" => snapshot.snapshot_version,
      "command_count" => length(snapshot.command_definitions),
      "argument_count" => length(snapshot.arguments),
      "argument_type_count" => length(snapshot.argument_types),
      "encoding_layout_count" => length(snapshot.encoding_layouts)
    }
  end

  defp command_runtime_summary(%CommandCompilerResult{} = compiler_result) do
    %{
      "runtime_definition_count" => length(compiler_result.runtime_definitions),
      "constraint_plan_count" => length(compiler_result.constraint_plans),
      "verifier_plan_count" => length(compiler_result.verifier_plans),
      "operational_binding_count" => length(compiler_result.operational_bindings),
      "runtime_definitions" =>
        Enum.map(compiler_result.runtime_definitions, fn runtime_definition ->
          %{
            "command_id" => runtime_definition.command_id,
            "name" => runtime_definition.name,
            "apid" => runtime_definition.apid,
            "opcode" => runtime_definition.opcode,
            "argument_count" => length(runtime_definition.argument_specs)
          }
        end)
    }
  end
end
