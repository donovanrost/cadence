defmodule Cadence.Control.MissionRuntimeReconcilerTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.{MissionModelPromotion, MissionRuntimeReconciler}
  alias Cadence.MissionModels
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime
  alias Cadence.Runtime.{MissionRuntimeSpec, Missions}
  alias Cadence.SemanticRuntime.RegisteredRegistry

  setup do
    previous = Application.get_env(:cadence, :semantic_algorithm_implementations, %{})
    registry = %{{"test.triple", "1"} => Cadence.Test.RegisteredSemanticAlgorithm}
    Application.put_env(:cadence, :semantic_algorithm_implementations, registry)

    on_exit(fn ->
      Application.put_env(:cadence, :semantic_algorithm_implementations, previous)
    end)

    :ok
  end

  test "unchanged polls only read identity columns and preserve the application observation" do
    %{mission: mission, reconciler: reconciler} = fixture()
    assert {:ok, observation} = MissionRuntimeReconciler.reconcile(mission)
    observe_queries(reconciler)

    for _ <- 1..3 do
      assert {:ok, ^observation} = MissionRuntimeReconciler.reconcile(mission)
      assert_receive {:query, "mission_active_binding_sets", sql}
      refute sql =~ "metadata"
      refute_receive {:query, _, _}
    end
  end

  test "a missing runtime is rebuilt even when the durable generation is unchanged" do
    %{mission: mission, reconciler: reconciler} = fixture()
    assert {:ok, before} = MissionRuntimeReconciler.reconcile(mission)
    assert :ok = Runtime.stop_mission(mission)
    observe_queries(reconciler)
    assert {:ok, recovered} = MissionRuntimeReconciler.reconcile(mission)
    assert recovered.activation_id == before.activation_id
    assert recovered.applied_at != before.applied_at
    assert_receive {:query, "mission_active_binding_sets", _}
    assert_receive {:query, "mission_active_binding_sets", full_sql}
    assert full_sql =~ "metadata"
    assert {:ok, %{generation: 1}} = Missions.applied_spec(mission)
  end

  test "a new durable generation materializes and applies before it can be reused" do
    %{mission: mission, activation: first, bindings: bindings} = fixture()
    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission)
    next = record_activation(bindings, first.metadata)
    assert next.generation == 2
    assert {:ok, %{generation: 2} = observation} = MissionRuntimeReconciler.reconcile(mission)
    assert observation.activation_id == next.activation_id
    assert {:ok, ^observation} = MissionRuntimeReconciler.reconcile(mission)
  end

  test "a different live runtime basis cannot be acknowledged from the cached observation" do
    %{mission: mission} = fixture()
    assert {:ok, _} = MissionRuntimeReconciler.reconcile(mission)
    assert {:ok, spec} = Missions.applied_spec(mission)
    assert :ok = Runtime.stop_mission(mission)
    assert {:ok, _} = Missions.apply(%{spec | runtime_basis_sha256: "different"})
    assert {:error, {:generation_conflict, 1}} = MissionRuntimeReconciler.reconcile(mission)
  end

  test "removing the active basis invalidates reuse instead of reporting convergence" do
    %{mission: mission} = fixture()
    assert {:ok, _} = MissionRuntimeReconciler.reconcile(mission)

    Repo.delete_all(from(row in ActiveBindingSetRow, where: row.mission_id == ^mission))

    assert {:error, :no_active_binding_set} = MissionRuntimeReconciler.reconcile(mission)
  end

  test "failed application invalidates reuse and a later poll retries the durable basis" do
    %{mission: mission, activation: activation, bindings: bindings, reconciler: reconciler} =
      fixture()

    assert {:ok, observation} = MissionRuntimeReconciler.reconcile(mission)
    invalid = %{activation | binding_set_content_sha256: "wrong"}
    assert {:error, _} = MissionRuntimeReconciler.apply_generation(mission, invalid, bindings)
    observe_queries(reconciler)
    assert {:ok, ^observation} = MissionRuntimeReconciler.reconcile(mission)
    assert_receive {:query, "mission_active_binding_sets", _}
    assert_receive {:query, "mission_active_binding_sets", full_sql}
    assert full_sql =~ "metadata"
    assert MissionRuntimeReconciler.snapshot(mission).last_error == nil
  end

  test "registered authorization changes are detected and can recover without a new generation" do
    %{mission: mission} = fixture(registered?: true)
    assert {:ok, observation} = MissionRuntimeReconciler.reconcile(mission)
    Application.put_env(:cadence, :semantic_algorithm_implementations, %{})
    assert {:error, _} = MissionRuntimeReconciler.reconcile(mission)
    assert {:error, _} = MissionRuntimeReconciler.reconcile(mission)

    Application.put_env(:cadence, :semantic_algorithm_implementations, %{
      {"test.triple", "1"} => Cadence.Test.RegisteredSemanticAlgorithm
    })

    assert {:ok, ^observation} = MissionRuntimeReconciler.reconcile(mission)
  end

  test "registered executable changes cannot reuse the previous generation" do
    %{mission: mission} = fixture(registered?: true)
    assert {:ok, _} = MissionRuntimeReconciler.reconcile(mission)

    Application.put_env(:cadence, :semantic_algorithm_implementations, %{
      {"test.triple", "1"} => Cadence.Test.AlternateRegisteredSemanticAlgorithm
    })

    assert {:error, {:generation_conflict, 1}} = MissionRuntimeReconciler.reconcile(mission)
  end

  test "the fleet guard covers every distinct source model without changing runtime hashes" do
    %{mission: mission} = fixture(registered?: true)
    assert {:ok, _} = MissionRuntimeReconciler.reconcile(mission)
    assert {:ok, spec} = Missions.applied_spec(mission)

    first = %{
      mission_model_revision_id: spec.mission_model_revision_id,
      mission_model_content_sha256: spec.mission_model_content_sha256,
      runtime_plans:
        Map.update!(spec.runtime_plans, :algorithm, &%{&1 | plan: %{"algorithms" => []}})
    }

    second = %{first | runtime_plans: spec.runtime_plans}
    attrs = spec |> Map.from_struct() |> Map.delete(:runtime_basis_sha256)

    assert {:ok, fleet} =
             MissionRuntimeSpec.new(
               Map.put(attrs, :source_runtime_bases, %{"a" => first, "b" => second})
             )

    hashes =
      Enum.map([{"a", first}, {"b", second}], fn {source, model} ->
        {source,
         MissionRuntimeSpec.runtime_basis_sha256(spec.binding_set_content_sha256, %{
           revision_id: model.mission_model_revision_id,
           content_sha256: model.mission_model_content_sha256,
           plans: model.runtime_plans
         })}
      end)

    assert fleet.runtime_basis_sha256 ==
             ContentHash.term_sha256(
               {:spacecraft_models_v1, spec.binding_set_content_sha256, hashes}
             )

    guard = MissionRuntimeSpec.reconciliation_guard(fleet)
    assert MissionRuntimeSpec.reconciliation_guard_current?(guard)
    Application.put_env(:cadence, :semantic_algorithm_implementations, %{})
    refute MissionRuntimeSpec.reconciliation_guard_current?(guard)
  end

  defp fixture(opts \\ []) do
    suffix = System.unique_integer([:positive])
    org = "org-reconcile-#{suffix}"
    mission = "mission-reconcile-#{suffix}"
    persist_mission_scope(org, mission)

    bindings =
      BindingSet.new(%{
        organization_id: org,
        mission_id: mission,
        binding_set_id: "basis",
        version: 1
      })

    assert {:ok, ^bindings} = Cadence.Governance.persist_binding_set(org, bindings)

    declarations = [%{kind: :space_system, qualified_name: "/"}]

    declarations =
      if opts[:registered?], do: declarations ++ [registered_algorithm()], else: declarations

    layer =
      Layer.new(%{
        organization_id: org,
        mission_id: mission,
        name: "reconciliation",
        declarations: declarations
      })

    assert {:ok, compilation} = MissionModels.compile_layers([layer])

    metadata = %{
      "mission_model" => MissionModelPromotion.manifest(compilation.revision, compilation.plans)
    }

    activation = record_activation(bindings, metadata)

    reconciler =
      start_supervised!(
        {MissionRuntimeReconciler,
         mission_id: mission, reconcile_on_start?: false, safety_poll?: false}
      )

    %{mission: mission, activation: activation, bindings: bindings, reconciler: reconciler}
  end

  defp registered_algorithm do
    implementation =
      RegisteredRegistry.bind(%{kind: :registered, key: "test.triple", version: "1"})

    %{
      kind: :algorithm,
      qualified_name: "/algorithms/registered",
      definition: %{
        implementation: Map.drop(implementation, [:module, :authorized?]),
        outputs: []
      }
    }
  end

  defp record_activation(bindings, metadata) do
    assert {:ok, activation} =
             Activations.record_binding_set_activation(
               bindings.organization_id,
               bindings.mission_id,
               bindings.binding_set_id,
               bindings.version,
               binding_set_content_sha256: MissionRuntimeSpec.content_sha256(bindings),
               metadata: metadata
             )

    activation
  end

  defp observe_queries(reconciler) do
    handler = {__MODULE__, self()}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        &__MODULE__.capture_query/4,
        {self(), reconciler}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  def capture_query(_event, _measurements, metadata, {test, reconciler}) do
    if self() == reconciler, do: send(test, {:query, metadata.source, metadata.query})
  end
end
