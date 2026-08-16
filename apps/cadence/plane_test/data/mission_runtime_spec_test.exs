defmodule Cadence.Runtime.MissionRuntimeSpecTest do
  use ExUnit.Case, async: true

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.MissionModelFixtures
  alias Cadence.Runtime.MissionRuntimeSpec

  test "constructs an exact specification with a deterministic content hash" do
    binding_set = binding_set("mission-a", "basis-a", 3)

    assert {:ok, spec} = runtime_spec(binding_set, 7, "activation-a")
    assert spec.generation == 7
    assert spec.binding_set == binding_set
    assert spec.binding_set_content_sha256 == MissionRuntimeSpec.content_sha256(binding_set)

    assert MissionRuntimeSpec.content_sha256(binding_set) ==
             MissionRuntimeSpec.content_sha256(binding_set)
  end

  test "rejects a mismatched artifact identity or claimed content hash" do
    binding_set = binding_set("mission-a", "basis-a", 3)

    assert {:error, {:mission_runtime_spec_mismatch, :binding_set_identity}} =
             runtime_spec(binding_set, 7, "activation-a", binding_set_version: 4)

    assert {:error, {:mission_runtime_spec_mismatch, :binding_set_content_sha256}} =
             runtime_spec(binding_set, 7, "activation-a",
               binding_set_content_sha256: String.duplicate("0", 64)
             )
  end

  defp runtime_spec(binding_set, generation, activation_id, overrides \\ []) do
    assert {:ok, compilation} = MissionModelFixtures.compile_empty_model(binding_set.mission_id)

    attrs = %{
      activation_id: activation_id,
      mission_id: binding_set.mission_id,
      generation: generation,
      binding_set_id: binding_set.binding_set_id,
      binding_set_version: binding_set.version,
      binding_set: binding_set,
      mission_model_revision_id: compilation.revision.revision_id,
      mission_model_content_sha256: compilation.revision.content_sha256,
      runtime_plans: compilation.plans,
      activated_at: ~U[2026-07-21 12:00:00Z]
    }

    attrs
    |> Map.merge(Map.new(overrides))
    |> MissionRuntimeSpec.new()
  end

  defp binding_set(mission_id, binding_set_id, version) do
    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: version
    })
  end
end
