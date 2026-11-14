defmodule Cadence.Governance.FieldIdentityTest do
  @moduledoc """
  DECISIONS #73: a telemetry field's semantic identity (`parameter_id`, `qualified_name`) is
  stored with the governed binding set, and the binding-set hash leaves it out, so a stored
  generation verifies whether or not its rows carry it.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Governance
  alias Cadence.Governance.PacketDefinitionFieldRow
  alias Cadence.Ops.PointCatalog
  alias Cadence.Platform.ContentHash
  alias Cadence.Telemetry.PacketDefinition

  @org "org-field-identity"
  @mission "mission-field-identity"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "the identity round-trips, and the hash is the same with or without it" do
    binding_set = binding_set("hk-v1", 1, identity("ctrl.mode", "HK.sc_mode"))
    assert {:ok, _} = Governance.persist_binding_set(@org, binding_set)
    {:ok, read_back} = Governance.fetch_binding_set(@org, @mission, "hk-v1", 1)

    assert [%{parameter_id: "ctrl.mode", qualified_name: "HK.sc_mode"}] = fields(read_back)
    # The identity doesn't move the hash (so an in-memory set carrying it hashes like a read-back
    # without it); anything else about the field does.
    renamed = put_fields(read_back, &%{&1 | parameter_id: "other", qualified_name: nil})
    assert BindingSet.content_sha256(renamed) == BindingSet.content_sha256(read_back)
    resized = put_fields(read_back, &%{&1 | size_bits: 16})
    refute BindingSet.content_sha256(resized) == BindingSet.content_sha256(read_back)
  end

  test "a generation stored before the columns existed still verifies once its rows fill in" do
    binding_set = binding_set("hk-v1", 1, identity("ctrl.mode", "HK.sc_mode"))
    assert {:ok, _} = Governance.persist_binding_set(@org, binding_set)

    # Rows as written before #73: no identity. Its stored hash was the read-back's term hash.
    {1, _} = Repo.update_all(identity_rows(), set: [parameter_id: nil, qualified_name: nil])
    {:ok, before} = Governance.fetch_binding_set(@org, @mission, "hk-v1", 1)
    assert [%{parameter_id: nil}] = fields(before)
    stored_hash = ContentHash.term_sha256(before)

    # A later binding set re-persists the same packet definition: the rows fill in, once.
    later = binding_set("hk-v2", 1, identity("ctrl.mode", "HK.sc_mode"))
    assert {:ok, _} = Governance.persist_binding_set(@org, later)
    conflicting = binding_set("hk-v3", 1, identity("someone.else", "X.y"))
    assert {:ok, _} = Governance.persist_binding_set(@org, conflicting)

    {:ok, filled} = Governance.fetch_binding_set(@org, @mission, "hk-v1", 1)
    assert [%{parameter_id: "ctrl.mode", qualified_name: "HK.sc_mode"}] = fields(filled)
    assert BindingSet.content_sha256(filled) == stored_hash
  end

  test "the point catalog's points carry the identity" do
    point = %{parameter_id: "ctrl.mode", qualified_name: "HK.sc_mode", point_id: "HK.sc_mode"}
    binding_set = binding_set("hk-v1", 1, identity(point.parameter_id, point.qualified_name))
    assert {:ok, _} = Governance.persist_binding_set(@org, binding_set)
    {:ok, read_back} = Governance.fetch_binding_set(@org, @mission, "hk-v1", 1)

    assert [^point] =
             read_back
             |> PointCatalog.points()
             |> Enum.map(&Map.take(&1, [:parameter_id, :qualified_name, :point_id]))
  end

  defp identity(parameter_id, qualified_name),
    do: %{parameter_id: parameter_id, qualified_name: qualified_name}

  defp identity_rows do
    from(f in PacketDefinitionFieldRow, where: not is_nil(f.parameter_id))
  end

  defp fields(%BindingSet{capability_instances: instances}) do
    for %CapabilityInstance{runtime_configuration: %PacketDefinition{fields: fields}} <- instances,
        field <- fields,
        do: field
  end

  defp put_fields(%BindingSet{} = binding_set, fun) do
    instances =
      Enum.map(binding_set.capability_instances, fn
        %CapabilityInstance{runtime_configuration: %PacketDefinition{} = packet} = instance ->
          %{instance | runtime_configuration: %{packet | fields: Enum.map(packet.fields, fun)}}

        instance ->
          instance
      end)

    %{binding_set | capability_instances: instances}
  end

  defp binding_set(binding_set_id, version, field_identity) do
    packet =
      PacketDefinition.new(%{
        mission_id: @mission,
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 100,
        version: 1,
        fields: [
          Map.merge(
            %{
              field_id: "sc_mode",
              name: "sc_mode",
              offset_bits: 0,
              size_bits: 8,
              data_type: :uint
            },
            field_identity
          )
        ]
      })

    BindingSet.new(%{
      mission_id: @mission,
      organization_id: @org,
      binding_set_id: binding_set_id,
      version: version,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "hk-instance",
          family_key: :definition_bound_telemetry,
          target_scope: :mission,
          runtime_configuration: packet
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "hk-rule",
          capability_instance_id: "hk-instance",
          packet_kind: :space_packet,
          apid: 100
        })
      ]
    })
  end
end
