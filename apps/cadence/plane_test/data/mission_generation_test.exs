defmodule Cadence.Runtime.MissionGenerationTest do
  use ExUnit.Case, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.MissionModelFixtures
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions

  test "applies exact generations idempotently without management, control, or Repo" do
    previous_scheduler_config = Application.get_env(:cadence, :contact_scheduler)
    Application.put_env(:cadence, :contact_scheduler, enabled: true)

    on_exit(fn ->
      Application.put_env(:cadence, :contact_scheduler, previous_scheduler_config)
    end)

    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    start_supervised!(Cadence.Runtime.Supervisor)

    mission_id = "isolated-generation-#{System.unique_integer([:positive])}"
    spec_v1 = runtime_spec(mission_id, "basis", 1, 1, "activation-1")

    assert {:ok, %GenerationApplied{generation: 1} = first_observation} =
             Missions.apply(spec_v1)

    assert {:ok, ^first_observation} = Missions.apply(spec_v1)
    assert {:ok, ^spec_v1} = Missions.applied_spec(mission_id)

    conflicting_spec = runtime_spec(mission_id, "other-basis", 1, 1, "activation-conflict")
    assert {:error, {:generation_conflict, 1}} = Missions.apply(conflicting_spec)

    spec_v2 = runtime_spec(mission_id, "basis", 2, 2, "activation-2")
    assert {:ok, %GenerationApplied{generation: 2}} = Missions.apply(spec_v2)
    assert {:error, {:stale_generation, 2}} = Missions.apply(spec_v1)
    assert {:ok, ^spec_v2} = Missions.applied_spec(mission_id)

    assert {:ok, mission_runtime} = Cadence.Runtime.ensure_mission_started(mission_id)

    refute Enum.any?(Supervisor.which_children(mission_runtime), fn
             {_id, _pid, _type, modules} -> Cadence.Contacts.Scheduler in modules
           end)

    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Registry) == nil
    assert Process.whereis(Cadence.Repo) == nil
  end

  defp runtime_spec(mission_id, binding_set_id, version, generation, activation_id) do
    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: binding_set_id,
        version: version
      })

    {:ok, compilation} = MissionModelFixtures.compile_empty_model(mission_id)

    {:ok, spec} =
      MissionRuntimeSpec.new(%{
        activation_id: activation_id,
        mission_id: mission_id,
        generation: generation,
        binding_set_id: binding_set_id,
        binding_set_version: version,
        binding_set: binding_set,
        mission_model_revision_id: compilation.revision.revision_id,
        mission_model_content_sha256: compilation.revision.content_sha256,
        runtime_plans: compilation.plans,
        activated_at: ~U[2026-07-21 12:00:00Z]
      })

    spec
  end
end
