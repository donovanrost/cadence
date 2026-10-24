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

  test "partition input is independent of unrelated fleet metadata and preserves semantic identity" do
    bindings = BindingSet.new(%{mission_id: "mission", rules: []})

    configurations =
      Map.new(1..500, fn id ->
        {"craft-#{id}",
         %{"source_endpoint_ids" => ["source-#{id}"], "document" => Enum.to_list(1..100)}}
      end)

    spec =
      struct(MissionRuntimeSpec,
        binding_set: bindings,
        metadata: %{"spacecraft_configurations" => configurations},
        activation_id: "admitted",
        generation: 3,
        runtime_basis_sha256: "unchanged"
      )

    compact = MissionRuntimeSpec.compact(spec)
    partition = %PartitionKey{affinity: :source_endpoint, value: "source-1"}
    assert {:ok, selected} = MissionRuntimeSpec.partition_input(compact, partition)
    assert map_size(selected.metadata["spacecraft_configurations"]) == 1
    assert selected.metadata["spacecraft_configurations"]["craft-1"] == configurations["craft-1"]
    assert MissionRuntimeSpec.identity(selected) == MissionRuntimeSpec.identity(spec)
    assert MissionRuntimeSpec.expand(compact) == spec
    assert :erts_debug.flat_size(selected) < div(:erts_debug.flat_size(spec), 100)
  end

  defp basis(id, fields) do
    %{
      mission_model_revision_id: id,
      mission_model_content_sha256: id,
      runtime_plans: %{telemetry: fields}
    }
  end
end
