defmodule Cadence.Runtime.MissionRuntimeSpecTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.MissionRuntimeSpec

  test "identical fleet models share memory after message serialization without changing the basis" do
    model = %{runtime_plans: %{telemetry: Enum.map(1..100, &%{field: &1, offset: &1 * 8})}}

    spec =
      struct(MissionRuntimeSpec)
      |> Map.put(:source_runtime_bases, Map.new(1..20, &{to_string(&1), model}))
      |> :erlang.term_to_binary()
      |> :erlang.binary_to_term()

    shared = MissionRuntimeSpec.share_source_models(spec)

    assert shared == spec
    assert :erts_debug.size(shared) < div(:erts_debug.size(spec), 5)
  end
end
