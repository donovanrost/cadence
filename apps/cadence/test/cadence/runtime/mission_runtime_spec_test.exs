defmodule Cadence.Runtime.MissionRuntimeSpecTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.MissionRuntimeSpec
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

  defp basis(id, fields) do
    %{
      mission_model_revision_id: id,
      mission_model_content_sha256: id,
      runtime_plans: %{telemetry: fields}
    }
  end
end
