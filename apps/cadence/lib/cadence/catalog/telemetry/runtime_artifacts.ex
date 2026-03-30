defmodule Cadence.Catalog.Telemetry.RuntimeArtifacts do
  @moduledoc """
  Deterministic runtime-facing artifacts derived from a persisted canonical
  telemetry snapshot.

  This keeps "compile the snapshot" and "build the governed binding set shape"
  in one reusable place so import, recompilation, and diff flows share the same
  logic.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Catalog.Telemetry.Compiler
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: CompilerResult
  alias Cadence.Catalog.Telemetry.Snapshot

  @type t :: %{
          snapshot: Snapshot.t(),
          compiler_result: CompilerResult.t(),
          binding_set: BindingSet.t()
        }

  @spec compile(Snapshot.t(), keyword()) :: t()
  def compile(%Snapshot{} = snapshot, opts \\ []) when is_list(opts) do
    binding_set_version = Keyword.get(opts, :binding_set_version, 1)

    compiler_result =
      Compiler.compile(
        snapshot,
        Keyword.merge(
          [
            packet_definition_version: binding_set_version,
            capability_family_key: :definition_bound_telemetry
          ],
          opts
        )
      )

    %{
      snapshot: snapshot,
      compiler_result: compiler_result,
      binding_set:
        build_binding_set(snapshot, compiler_result, binding_set_version: binding_set_version)
    }
  end

  @spec build_binding_set(Snapshot.t(), CompilerResult.t(), keyword()) :: BindingSet.t()
  def build_binding_set(%Snapshot{} = snapshot, %CompilerResult{} = compiler_result, opts \\ []) do
    binding_set_version = Keyword.get(opts, :binding_set_version, 1)

    packet_definitions_by_id =
      Map.new(compiler_result.packet_definitions, fn packet_definition ->
        {packet_definition.packet_definition_id, packet_definition}
      end)

    capability_instances =
      Enum.map(compiler_result.selector_inputs, fn selector_input ->
        CapabilityInstance.new(%{
          capability_instance_id: selector_input.capability_instance_id,
          family_key: selector_input.capability_family_key,
          target_scope: selector_input.selector.scope.target_scope,
          source_endpoint_ref: selector_input.selector.scope.source_endpoint_ref,
          capability_config: selector_input.capability_config,
          runtime_configuration:
            Map.get(packet_definitions_by_id, selector_input.packet_definition_id)
        })
      end)

    rules =
      Enum.map(compiler_result.selector_inputs, fn selector_input ->
        BindingRule.new(%{
          binding_rule_id: selector_input.selector_input_id <> "_rule",
          capability_instance_id: selector_input.capability_instance_id,
          selector: selector_input.selector,
          priority: 100,
          fanout_mode: :exclusive
        })
      end)

    BindingSet.new(%{
      binding_set_id: binding_set_id(snapshot),
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      version: binding_set_version,
      capability_instances: capability_instances,
      rules: rules
    })
  end

  @spec binding_set_id(Snapshot.t() | binary()) :: binary()
  def binding_set_id(%Snapshot{} = snapshot), do: binding_set_id(snapshot.import_run_id)

  def binding_set_id(import_run_id) when is_binary(import_run_id),
    do: "catalog_import:" <> import_run_id
end
