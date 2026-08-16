defmodule Cadence.Runtime.MissionModelPlanDecoder do
  @moduledoc """
  Decodes executable Mission Model target plans at the runtime boundary.

  Target plans are persisted as JSON documents, so this module is the single
  bounded conversion point from string-keyed documents into the existing
  telemetry and command runtime structs. It never creates atoms from plan
  content.
  """

  alias Cadence.Catalog.Command.{MatchCriteria, StateEffect, TypeEncoding}

  alias Cadence.Catalog.Command.Compiler.{
    ArgumentSpec,
    ConstraintPlan,
    EncodingStep,
    OperationalBinding,
    RuntimeDefinition,
    VerifierPlan
  }

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.SemanticRuntime.PlanDecoder, as: SemanticPlanDecoder
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @telemetry_contract "2"
  @command_contract "2"

  @spec validate(%{optional(atom()) => RuntimePlan.t()}) :: :ok | {:error, term()}
  def validate(plans) when is_map(plans) do
    with :ok <- SemanticPlanDecoder.validate(plans),
         {:ok, _packet_definitions} <- telemetry_packet_definitions(plans),
         {:ok, _command_catalog} <- command_catalog(plans) do
      :ok
    end
  end

  @spec resolve_telemetry_configuration(map(), term()) ::
          {:ok, term()} | {:error, term()}
  def resolve_telemetry_configuration(plans, %PacketDefinition{} = configured) do
    with {:ok, packet_definitions} <- telemetry_packet_definitions(plans) do
      find_telemetry_configuration(packet_definitions, configured)
    end
  end

  def resolve_telemetry_configuration(_plans, configuration),
    do: {:error, {:invalid_mission_model_telemetry_binding, configuration}}

  defp find_telemetry_configuration(definitions, configured) do
    case Enum.find(definitions, &(&1.packet_definition_id == configured.packet_definition_id)) do
      %PacketDefinition{} = definition ->
        {:ok, definition}

      nil ->
        {:error, {:mission_model_packet_definition_not_found, configured.packet_definition_id}}
    end
  end

  @spec telemetry_packet_definitions(map()) ::
          {:ok, [PacketDefinition.t()]} | {:error, term()}
  def telemetry_packet_definitions(plans) when is_map(plans) do
    case Map.get(plans, :telemetry) do
      nil ->
        {:error, {:mission_model_runtime_plan_required, :telemetry}}

      %RuntimePlan{
        status: :ready,
        target_contract_version: @telemetry_contract,
        plan: plan
      } ->
        decode_telemetry_plan(plan)

      %RuntimePlan{} = plan ->
        {:error,
         {:unsupported_mission_model_runtime_plan, :telemetry, plan.target_contract_version}}

      _other ->
        {:error, {:invalid_mission_model_runtime_plan, :telemetry}}
    end
  end

  @spec command_basis(map(), binary()) ::
          {:ok,
           %{
             runtime_definition: RuntimeDefinition.t(),
             constraint_plans: [ConstraintPlan.t()],
             verifier_plans: [VerifierPlan.t()],
             operational_binding: OperationalBinding.t(),
             plan_id: binary()
           }}
          | {:error, term()}
  def command_basis(plans, command_id) when is_map(plans) and is_binary(command_id) do
    with {:ok, catalog} <- command_catalog(plans),
         {:ok, runtime_definition} <-
           find_runtime_definition(catalog.runtime_definitions, command_id),
         {:ok, operational_binding} <-
           find_operational_binding(catalog.operational_bindings, command_id) do
      {:ok,
       %{
         runtime_definition: runtime_definition,
         constraint_plans: Enum.filter(catalog.constraint_plans, &(&1.command_id == command_id)),
         verifier_plans: Enum.filter(catalog.verifier_plans, &(&1.command_id == command_id)),
         operational_binding: operational_binding,
         plan_id: catalog.plan_id
       }}
    end
  end

  defp decode_telemetry_plan(plan) when is_map(plan) do
    case value(plan, :runtime_contract) do
      "mission_model_telemetry_v1" ->
        plan
        |> list(:packet_definitions)
        |> decode_many(&decode_packet_definition/1, :telemetry)

      contract ->
        {:error, {:unsupported_mission_model_runtime_contract, :telemetry, contract}}
    end
  end

  defp decode_telemetry_plan(_plan),
    do: {:error, {:invalid_mission_model_runtime_plan, :telemetry}}

  defp decode_packet_definition(document) when is_map(document) do
    fields =
      document
      |> list(:fields)
      |> Enum.map(fn field ->
        FieldDefinition.new(%{
          field_id: value(field, :field_id),
          parameter_id: value(field, :parameter_id),
          qualified_name: value(field, :qualified_name),
          name: value(field, :name),
          offset_bits: value(field, :offset_bits, 0),
          size_bits: value(field, :size_bits),
          data_type: value(field, :data_type, :uint),
          byte_order: value(field, :byte_order, :big_endian),
          engineering_unit: value(field, :engineering_unit)
        })
      end)

    PacketDefinition.new(%{
      packet_definition_id: value(document, :packet_definition_id),
      organization_id: value(document, :organization_id),
      mission_id: value(document, :mission_id),
      packet_name: value(document, :packet_name),
      apid: value(document, :apid),
      version: value(document, :version, 1),
      fields: fields
    })
  end

  defp command_catalog(plans) do
    case Map.get(plans, :command) do
      nil ->
        {:error, {:mission_model_runtime_plan_required, :command}}

      %RuntimePlan{
        status: :ready,
        target_contract_version: @command_contract,
        plan_id: plan_id,
        plan: plan
      } ->
        decode_command_plan(plan_id, plan)

      %RuntimePlan{} = plan ->
        {:error,
         {:unsupported_mission_model_runtime_plan, :command, plan.target_contract_version}}

      _other ->
        {:error, {:invalid_mission_model_runtime_plan, :command}}
    end
  end

  defp decode_command_plan(plan_id, plan) when is_map(plan) do
    case value(plan, :runtime_contract) do
      "mission_model_command_v1" ->
        decode_command_runtime_plan(plan_id, plan)

      contract ->
        {:error, {:unsupported_mission_model_runtime_contract, :command, contract}}
    end
  end

  defp decode_command_plan(_plan_id, _plan),
    do: {:error, {:invalid_mission_model_runtime_plan, :command}}

  defp decode_command_runtime_plan(plan_id, plan) do
    with {:ok, runtime_definitions} <-
           decode_many(list(plan, :runtime_definitions), &decode_runtime_definition/1, :command),
         {:ok, constraint_plans} <-
           decode_many(list(plan, :constraint_plans), &decode_constraint_plan/1, :command),
         {:ok, verifier_plans} <-
           decode_many(list(plan, :verifier_plans), &decode_verifier_plan/1, :command),
         {:ok, operational_bindings} <-
           decode_many(
             list(plan, :operational_bindings),
             &decode_operational_binding/1,
             :command
           ) do
      {:ok,
       %{
         plan_id: plan_id,
         runtime_definitions: runtime_definitions,
         constraint_plans: constraint_plans,
         verifier_plans: verifier_plans,
         operational_bindings: operational_bindings
       }}
    end
  end

  defp decode_runtime_definition(document) do
    RuntimeDefinition.new(%{
      command_id: value(document, :command_id),
      mission_model_revision_id: value(document, :mission_model_revision_id),
      name: value(document, :name),
      display_name: value(document, :display_name),
      description: value(document, :description),
      layout_id: value(document, :layout_id),
      layout_kind:
        enum(value(document, :layout_kind), [
          :binary_container,
          :space_packet,
          :service_data_unit,
          :raw_payload
        ]),
      byte_order: enum(value(document, :byte_order), [:big_endian, :little_endian]),
      apid: value(document, :apid),
      service_type: value(document, :service_type),
      service_subtype: value(document, :service_subtype),
      opcode: value(document, :opcode),
      opcode_size_bits: value(document, :opcode_size_bits),
      size_bits: value(document, :size_bits),
      max_size_bits: value(document, :max_size_bits),
      argument_specs: Enum.map(list(document, :argument_specs), &decode_argument_spec/1),
      encoding_steps: Enum.map(list(document, :encoding_steps), &decode_encoding_step/1),
      default_argument_values: value(document, :default_argument_values, %{}),
      fixed_argument_values: value(document, :fixed_argument_values, %{}),
      state_effects: Enum.map(list(document, :state_effects), &decode_state_effect/1),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_argument_spec(document) do
    ArgumentSpec.new(%{
      argument_id: value(document, :argument_id),
      name: value(document, :name),
      description: value(document, :description),
      base_type:
        enum(value(document, :base_type), [
          :integer,
          :float,
          :string,
          :binary,
          :boolean,
          :enumerated
        ]),
      required: value(document, :required, true),
      encoding: document |> value(:encoding, %{}) |> TypeEncoding.new(),
      default_value: value(document, :default_value),
      fixed_value: value(document, :fixed_value),
      hazardous_values: list(document, :hazardous_values),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_encoding_step(document) do
    EncodingStep.new(%{
      step_kind: enum(value(document, :step_kind), [:argument_ref, :fixed_value]),
      argument_id: value(document, :argument_id),
      bit_offset: value(document, :bit_offset),
      bit_offset_from: enum(value(document, :bit_offset_from), [:layout_start]),
      size_bits: value(document, :size_bits),
      fixed_value: value(document, :fixed_value),
      display_order: value(document, :display_order),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_state_effect(document) do
    StateEffect.new(%{
      effect_id: value(document, :effect_id),
      target_ref: value(document, :target_ref),
      operation: value(document, :operation),
      argument_ref: value(document, :argument_id),
      value: value(document, :value),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_constraint_plan(document) do
    ConstraintPlan.new(%{
      command_id: value(document, :command_id),
      constraint_id: value(document, :constraint_id),
      name: value(document, :name),
      description: value(document, :description),
      constraint_type:
        enum(value(document, :constraint_type), [
          :precondition,
          :interlock,
          :timing_window,
          :custom
        ]),
      criteria: decode_criteria(value(document, :criteria)),
      timeout_ms: value(document, :timeout_ms),
      blocking: value(document, :blocking, true),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_verifier_plan(document) do
    VerifierPlan.new(%{
      command_id: value(document, :command_id),
      verifier_id: value(document, :verifier_id),
      name: value(document, :name),
      description: value(document, :description),
      phase: enum(value(document, :phase), [:acceptance, :start, :completion, :custom]),
      success_criteria: decode_criteria(value(document, :success_criteria)),
      failure_criteria: decode_criteria(value(document, :failure_criteria)),
      timeout_ms: value(document, :timeout_ms),
      delay_ms: value(document, :delay_ms),
      severity: enum(value(document, :severity), [nil, :info, :warning, :error, :critical]),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_operational_binding(document) do
    OperationalBinding.new(%{
      command_id: value(document, :command_id),
      name: value(document, :name),
      display_name: value(document, :display_name),
      significance:
        enum(value(document, :significance), [nil, :routine, :warning, :critical, :hazardous]),
      critical: value(document, :critical, false),
      hazardous: value(document, :hazardous, false),
      subsystem: value(document, :subsystem),
      group_name: value(document, :group_name),
      preferred_uplink_service: value(document, :preferred_uplink_service),
      release_policy_hint: value(document, :release_policy_hint),
      apid: value(document, :apid),
      service_type: value(document, :service_type),
      service_subtype: value(document, :service_subtype),
      opcode: value(document, :opcode),
      metadata: value(document, :metadata, %{})
    })
  end

  defp decode_criteria(nil), do: nil
  defp decode_criteria(criteria) when is_map(criteria), do: MatchCriteria.new(criteria)

  defp find_runtime_definition(items, command_id) do
    case Enum.find(items, &(&1.command_id == command_id)) do
      nil -> {:error, {:command_runtime_definition_not_found, command_id}}
      item -> {:ok, item}
    end
  end

  defp find_operational_binding(items, command_id) do
    case Enum.find(items, &(&1.command_id == command_id)) do
      nil -> {:error, {:command_operational_binding_not_found, command_id}}
      item -> {:ok, item}
    end
  end

  defp decode_many(documents, decoder, target) do
    {:ok, Enum.map(documents, decoder)}
  rescue
    error in [KeyError, ArgumentError] ->
      {:error, {:invalid_mission_model_runtime_plan, target, Exception.message(error)}}
  end

  defp enum(value, allowed) when is_binary(value) do
    Enum.find(allowed, fn
      item when is_atom(item) -> Atom.to_string(item) == value
      _other -> false
    end)
  end

  defp enum(value, allowed), do: if(value in allowed, do: value, else: nil)

  defp list(map, key) do
    case value(map, key, []) do
      items when is_list(items) -> items
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
