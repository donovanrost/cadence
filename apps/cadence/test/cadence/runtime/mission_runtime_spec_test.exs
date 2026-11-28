defmodule Cadence.Runtime.MissionRuntimeSpecTest do
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.SourceRuntimeBases

  test "fleet models stay compact across real process messages, including replies" do
    model = basis("model", Enum.map(1..100, &%{field: &1, offset: &1 * 8}))
    sources = Map.new(1..1000, &{to_string(&1), model})
    legacy = struct(MissionRuntimeSpec, source_runtime_bases: sources)
    compact = MissionRuntimeSpec.compact_source_models(legacy)
    assert SourceRuntimeBases.count(compact.source_runtime_bases) == 1000
    assert map_size(compact.source_runtime_bases.models) == 1
    assert MissionRuntimeSpec.compact_source_models(compact) == compact

    parent = self()

    pid =
      spawn_link(fn ->
        receive do
          {:spec, spec} ->
            send(parent, {:received, spec, :erts_debug.size(spec)})
        end
      end)

    send(pid, {:spec, compact})
    assert_receive {:received, returned, received_words}, 5000
    assert returned == compact
    assert received_words < div(:erts_debug.flat_size(legacy), 100)
    assert :erts_debug.size(returned) < div(:erts_debug.flat_size(legacy), 100)
    assert :erts_debug.flat_size(compact) < div(:erts_debug.flat_size(legacy), 100)
  end

  # CB-9 (#512): the caller names the hash the binding set must have. A missing key is an error,
  # never a default to the computed hash, so no path checks computed against computed.
  describe "the expected binding-set hash is required" do
    defp identity_attrs(binding_set) do
      %{
        activation_id: "a",
        mission_id: binding_set.mission_id,
        generation: 1,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        binding_set: binding_set,
        activated_at: ~U[2026-11-28 00:00:00Z]
      }
    end

    setup do
      %{
        binding_set: BindingSet.new(%{mission_id: "m", binding_set_id: "basis", version: 1})
      }
    end

    test "a spec built without it is refused", %{binding_set: binding_set} do
      assert {:error, {:invalid_mission_runtime_spec, :binding_set_content_sha256}} =
               MissionRuntimeSpec.new(identity_attrs(binding_set))

      assert {:error, {:invalid_mission_runtime_spec, :binding_set_content_sha256}} =
               MissionRuntimeSpec.new(
                 Map.put(identity_attrs(binding_set), :binding_set_content_sha256, nil)
               )
    end

    test "one that names another hash is a mismatch", %{binding_set: binding_set} do
      assert {:error, {:mission_runtime_spec_mismatch, :binding_set_content_sha256}} =
               MissionRuntimeSpec.new(
                 Map.put(identity_attrs(binding_set), :binding_set_content_sha256, "not-its-hash")
               )
    end

    test "the right hash passes this check (the spec goes on to its mission model)", %{
      binding_set: binding_set
    } do
      attrs =
        Map.put(
          identity_attrs(binding_set),
          :binding_set_content_sha256,
          MissionRuntimeSpec.content_sha256(binding_set)
        )

      assert {:error, {:invalid_mission_runtime_spec, :mission_model_revision_id}} =
               MissionRuntimeSpec.new(attrs)
    end
  end

  test "selection keeps distinct executable plans and prunes unrelated models" do
    first = basis("first", [%{offset: 8}])
    second = basis("second", [%{offset: 16}])
    different_plan = %{first | runtime_plans: %{telemetry: [%{offset: 24}]}}

    assert {:ok, index} =
             SourceRuntimeBases.new(%{
               "a" => first,
               "b" => first,
               "c" => second,
               "d" => different_plan
             })

    assert map_size(index.models) == 3
    assert {:ok, ^first} = SourceRuntimeBases.fetch(index, "b")
    assert {:ok, ^second} = SourceRuntimeBases.fetch(index, "c")
    assert {:ok, ^different_plan} = SourceRuntimeBases.fetch(index, "d")
    assert :error = SourceRuntimeBases.fetch(index, "missing")

    selected = SourceRuntimeBases.take(index, ["b"])
    assert SourceRuntimeBases.count(selected) == 1
    assert map_size(selected.models) == 1
    assert {:ok, ^first} = SourceRuntimeBases.fetch(selected, "b")
    assert :error = SourceRuntimeBases.fetch(selected, "c")
  end

  test "invalid sources and dangling or unreferenced models fail closed" do
    assert {:error, _} = SourceRuntimeBases.new(%{"" => basis("model", [])})
    assert {:error, _} = SourceRuntimeBases.new(%{"source" => nil})
    assert {:error, _} = SourceRuntimeBases.new(%SourceRuntimeBases{sources: %{"source" => 1}})

    assert {:error, _} =
             SourceRuntimeBases.new(%SourceRuntimeBases{
               sources: %{"source" => 1},
               models: %{1 => %{}, 2 => %{}}
             })

    assert {:error, _} =
             SourceRuntimeBases.new(%SourceRuntimeBases{
               sources: %{"source" => 1},
               models: %{1 => nil}
             })
  end

  test "partition input carries the same constant-size fleet reference and preserves semantic identity" do
    bindings = BindingSet.new(%{mission_id: "mission", rules: []})

    # A fleet and its review are references (#734), so a 10,000-craft mission's metadata is the
    # same size as a 5-craft one's: nothing is projected per partition.
    metadata = %{
      "spacecraft_configuration_version" => 2,
      "fleet" => %{"mission_id" => "mission", "sha256" => "fleet-sha", "count" => 10_000},
      "configuration_review" => %{
        "review" => %{"mission_id" => "mission", "sha256" => "review-sha", "count" => 10_000},
        "base_activation_id" => "previous"
      }
    }

    spec =
      struct(MissionRuntimeSpec,
        binding_set: bindings,
        metadata: metadata,
        activation_id: "admitted",
        generation: 3,
        runtime_basis_sha256: "unchanged"
      )

    compact = MissionRuntimeSpec.compact(spec)
    partition = %PartitionKey{affinity: :source_endpoint, value: "source-1"}
    assert {:ok, selected} = MissionRuntimeSpec.partition_input(compact, partition)
    assert selected.metadata == metadata
    assert MissionRuntimeSpec.identity(selected) == MissionRuntimeSpec.identity(spec)
    assert MissionRuntimeSpec.expand(compact) == spec
  end

  defp basis(id, fields) do
    %{
      mission_model_revision_id: id,
      mission_model_content_sha256: id,
      runtime_plans: %{telemetry: fields}
    }
  end
end
