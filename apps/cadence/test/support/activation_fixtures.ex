defmodule Cadence.ActivationFixtures do
  @moduledoc false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer, Reference}
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.MissionModels
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias Cadence.Telemetry.PacketDefinition

  def activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Cadence.Governance.fetch_binding_set(
             organization_id,
             mission_id,
             binding_set_id,
             version
           ) do
      activate(binding_set, opts)
    end
  end

  def activate_binding_set(mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Cadence.Governance.fetch_binding_set(mission_id, binding_set_id, version) do
      activate(binding_set, opts)
    end
  end

  defp activate(%BindingSet{organization_id: nil} = binding_set, opts) do
    content_sha256 = MissionRuntimeSpec.content_sha256(binding_set)

    with {:ok, compilation} <- compile_model(binding_set),
         metadata <-
           opts
           |> Keyword.get(:metadata, %{})
           |> Map.put(
             "mission_model",
             MissionModelPromotion.manifest(compilation.revision, compilation.plans)
           ),
         {:ok, activation} <-
           Cadence.Activations.record_binding_set_activation(
             binding_set.mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             opts
             |> Keyword.put(:binding_set_content_sha256, content_sha256)
             |> Keyword.put(:metadata, metadata)
           ),
         {:ok, runtime_spec} <-
           MissionRuntimeSpec.new(%{
             activation_id: activation.activation_id,
             mission_id: binding_set.mission_id,
             generation: activation.generation,
             binding_set_id: binding_set.binding_set_id,
             binding_set_version: binding_set.version,
             binding_set_content_sha256: content_sha256,
             binding_set: binding_set,
             mission_model_revision_id: compilation.revision.revision_id,
             mission_model_content_sha256: compilation.revision.content_sha256,
             runtime_plans: compilation.plans,
             activated_at: activation.activated_at,
             metadata: metadata
           }),
         {:ok, _generation_applied} <- RuntimeMissions.apply(runtime_spec) do
      {:ok, activation}
    end
  end

  defp activate(%BindingSet{} = binding_set, opts) do
    content_sha256 = MissionRuntimeSpec.content_sha256(binding_set)

    with {:ok, revision, plans} <- compile_and_approve_model(binding_set),
         metadata <-
           opts
           |> Keyword.get(:metadata, %{})
           |> Map.put("mission_model", MissionModelPromotion.manifest(revision, plans)),
         {:ok, activation} <-
           Cadence.Activations.record_binding_set_activation(
             binding_set.organization_id,
             binding_set.mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             opts
             |> Keyword.put(:binding_set_content_sha256, content_sha256)
             |> Keyword.put(:metadata, metadata)
           ),
         {:ok, runtime_spec} <-
           MissionRuntimeSpec.new(%{
             activation_id: activation.activation_id,
             mission_id: binding_set.mission_id,
             generation: activation.generation,
             binding_set_id: binding_set.binding_set_id,
             binding_set_version: binding_set.version,
             binding_set_content_sha256: content_sha256,
             binding_set: binding_set,
             mission_model_revision_id: revision.revision_id,
             mission_model_content_sha256: revision.content_sha256,
             runtime_plans: plans,
             activated_at: activation.activated_at,
             metadata: metadata
           }),
         {:ok, _generation_applied} <-
           RuntimeMissions.apply(runtime_spec) do
      {:ok, activation}
    end
  end

  defp compile_and_approve_model(binding_set) do
    with {:ok, compilation} <- MissionModels.compile_layers([model_layer(binding_set)]),
         {:ok, revision} <-
           MissionModels.approve_revision(
             binding_set.organization_id,
             binding_set.mission_id,
             compilation.revision.revision_id,
             %{"kind" => "test_fixture", "id" => "activation-fixture"}
           ) do
      {:ok, revision, compilation.plans}
    end
  end

  defp compile_model(binding_set), do: Compiler.compile([model_layer(binding_set)])

  defp model_layer(binding_set) do
    Layer.new(%{
      organization_id: binding_set.organization_id,
      mission_id: binding_set.mission_id,
      name:
        "Activation fixture model #{binding_set.binding_set_id}:#{binding_set.version}:#{System.unique_integer([:positive])}",
      declarations: [
        %{kind: :space_system, qualified_name: "/"}
        | telemetry_declarations(binding_set)
      ]
    })
  end

  defp telemetry_declarations(binding_set) do
    binding_set.rules
    |> Enum.map(&BindingRule.configuration/1)
    |> Enum.filter(&match?(%PacketDefinition{}, &1))
    |> Enum.uniq_by(& &1.packet_definition_id)
    |> Enum.flat_map(&packet_declarations/1)
  end

  defp packet_declarations(packet) do
    field_declarations =
      Enum.flat_map(packet.fields, fn field ->
        type_name = "/fixture_types/#{packet.packet_name}/#{field.name}"
        parameter_name = "/fixture_parameters/#{packet.packet_name}/#{field.name}"
        {base_type, encoding} = field_type(field)

        type =
          Declaration.new(%{
            kind: :parameter_type,
            qualified_name: type_name,
            definition: %{base_type: base_type, encoding: encoding}
          })

        parameter_attrs = %{
          kind: :parameter,
          qualified_name: parameter_name,
          references: [
            Reference.new(%{
              expected_kind: :parameter_type,
              source_ref: type_name,
              role: :type
            })
          ]
        }

        parameter =
          parameter_attrs
          |> maybe_put(:semantic_id, field.parameter_id)
          |> Declaration.new()

        [type, parameter]
      end)

    parameter_by_name =
      field_declarations
      |> Enum.filter(&(&1.kind == :parameter))
      |> Map.new(&{&1.name, &1})

    entries =
      Enum.map(packet.fields, fn field ->
        parameter = Map.fetch!(parameter_by_name, field.name)

        %{
          parameter_ref: parameter.qualified_name,
          bit_offset: field.offset_bits,
          size_bits: field.size_bits
        }
      end)

    container =
      Declaration.new(%{
        semantic_id: packet.packet_definition_id,
        kind: :container,
        qualified_name: "/fixture_containers/#{packet.packet_name}",
        definition: %{apid: packet.apid, version: packet.version, entries: entries},
        references:
          Enum.map(entries, fn entry ->
            Reference.new(%{
              expected_kind: :parameter,
              source_ref: entry.parameter_ref,
              role: :entry
            })
          end)
      })

    field_declarations ++ [container]
  end

  defp field_type(field) do
    case field.data_type do
      :uint ->
        {:integer, %{size_bits: field.size_bits, signed: false, byte_order: field.byte_order}}

      :int ->
        {:integer, %{size_bits: field.size_bits, signed: true, byte_order: field.byte_order}}

      :float ->
        {:float, %{size_bits: field.size_bits, byte_order: field.byte_order}}

      :bool ->
        {:boolean, %{size_bits: field.size_bits, byte_order: field.byte_order}}

      :binary ->
        {:binary, %{size_bits: field.size_bits, byte_order: field.byte_order}}

      :string ->
        {:string, %{size_bits: field.size_bits, byte_order: field.byte_order}}
    end
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)
end
