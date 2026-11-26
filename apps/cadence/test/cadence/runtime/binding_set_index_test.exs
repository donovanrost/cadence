defmodule Cadence.Runtime.BindingSetIndexTest do
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{BindingSetIndex, PartitionKey}

  test "normalization stays small across messages and restores the exact governed value" do
    configuration = Enum.map(1..200, &%{field: &1, offset: &1 * 8, scale: {1, 2}})

    bindings =
      BindingSet.new(%{
        binding_set_id: "fleet",
        mission_id: "mission",
        version: 1,
        rules:
          for id <- 1..500 do
            BindingRule.new(%{
              binding_rule_id: "rule-#{id}",
              handler_key: :packet_counter,
              source_endpoint_ref: "source-#{id}",
              handler_configuration: configuration
            })
          end
      })

    index = BindingSetIndex.new(bindings)
    parent = self()

    receiver =
      spawn_link(fn ->
        receive do
          value -> send(parent, {:copied, value, :erts_debug.size(value)})
        end
      end)

    send(receiver, index)
    assert_receive {:copied, copied, words}, 5_000
    assert words < div(:erts_debug.flat_size(bindings), 10)
    assert :erts_debug.flat_size(copied) < div(:erts_debug.flat_size(bindings), 10)
    assert BindingSetIndex.materialize(copied) == bindings

    assert ContentHash.term_sha256(BindingSetIndex.materialize(copied)) ==
             ContentHash.term_sha256(bindings)

    assert BindingSetIndex.new(copied) == copied
  end

  test "selection preserves explicit instance configuration, rule order, defaults and distinct values" do
    instance =
      CapabilityInstance.new(%{
        capability_instance_id: "shared",
        family_key: :packet_counter,
        target_scope: :mission,
        runtime_configuration: %{counter: "instance"}
      })

    first =
      BindingRule.new(%{
        binding_rule_id: "first",
        capability_instance_id: "shared",
        source_endpoint_ref: "a",
        priority: 12,
        fanout_mode: :multi,
        handler_configuration: %{counter: "rule"}
      })

    default =
      BindingRule.new(%{
        binding_rule_id: "default",
        capability_instance_id: "shared",
        priority: 5,
        handler_configuration: nil
      })

    other =
      BindingRule.new(%{
        binding_rule_id: "other",
        source_endpoint_ref: "b",
        handler_key: :packet_counter,
        handler_configuration: %{counter: "other"}
      })

    bindings =
      BindingSet.new(%{
        mission_id: "mission",
        rules: [first, other, default],
        capability_instances: [instance]
      })

    index = BindingSetIndex.new(bindings)

    selected =
      BindingSetIndex.select(index, %PartitionKey{affinity: :source_endpoint, value: "a"})

    assert selected.rules == [first, default]
    assert selected.capability_instances == [instance]

    assert selected ==
             BindingSetIndex.select(bindings, %PartitionKey{
               affinity: :source_endpoint,
               value: "a"
             })

    assert BindingSetIndex.materialize(index) == bindings
  end
end
