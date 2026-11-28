defmodule Cadence.Control.MissionRuntimeReconcilerTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Activations
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Control.{MissionModelPromotion, MissionRuntimeReconciler, MissionRuntimeStatus}
  alias Cadence.MissionModels
  alias Cadence.Platform.{ContentHash, ScopedReadUpdates}
  alias Cadence.Runtime
  alias Cadence.Runtime.{MissionRuntimeSpec, Missions}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime.RegisteredRegistry
  alias Cadence.TestSupport.BindingFleet

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

  # #447: the reconciler reads a membership version through `fetch_binding_set`, hashes the
  # expansion against the activation's recorded hash, and applies it; what the runtime holds must
  # be the set the rows form would have given.
  test "a populated membership version reconciles and the applied set is the old expansion (#447)" do
    %{mission: mission, bindings: bindings} = fixture(populated: 3)

    assert "membership" ==
             Repo.one!(
               from(row in "governed_binding_sets",
                 where: row.mission_id == ^mission,
                 select: row.storage_form
               )
             )

    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission)
    assert {:ok, spec} = Missions.applied_spec(mission)
    assert spec.binding_set_content_sha256 == MissionRuntimeSpec.content_sha256(bindings)

    # The old expansion of the set as it was written, not of the stored read-back.
    written = BindingFleet.build(bindings.organization_id, mission, "basis", 1, 3)
    {:ok, reference} = Cadence.Governance.rows_expansion(written)
    applied = MissionRuntimeSpec.expand(spec).binding_set
    assert applied == reference
    assert length(applied.capability_instances) == 9
  end

  # #450: the runtime admits a membership version only if its members are the version's. A member
  # added after the fact is not applied; the generation reads not_applied with the reason.
  test "a membership version with a member added after it was written is not admitted (#450)" do
    %{mission: mission, bindings: bindings} = fixture(populated: 3)

    row =
      Repo.one!(
        from(row in "governed_binding_sets",
          where: row.mission_id == ^mission,
          select: %{id: row.id, organization_id: row.organization_id}
        )
      )

    %{rows: [[sha]]} =
      Repo.query!("SELECT artifact_sha256 FROM governed_binding_set_members LIMIT 1")

    Repo.insert_all("governed_binding_set_members", [
      %{
        binding_set_row_id: row.id,
        organization_id: row.organization_id,
        mission_id: mission,
        artifact_sha256: sha,
        source_endpoint_ref: "spacecraft_runtime:sc-extra",
        inserted_at: DateTime.utc_now()
      }
    ])

    assert {:error, :binding_set_members_mismatch} = MissionRuntimeReconciler.reconcile(mission)

    assert %{last_error: :binding_set_members_mismatch} =
             MissionRuntimeReconciler.snapshot(mission)

    refute match?({:ok, _}, Missions.applied_spec(mission))
    assert bindings.mission_id == mission
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

  # #451 T3b: a generation whose monitoring plan no longer has a policy retires it, once, when it
  # is applied: the policy's open episode clears with `rule_retired` and its state goes.
  test "a generation that drops a policy retires its open alarm episode" do
    %{mission: mission, bindings: bindings} = fixture()
    org = bindings.organization_id

    :ok =
      SemanticObservations.persist_many([
        transition(
          org,
          mission,
          "sc-1",
          "P1",
          {:normal, :critical},
          ~U[2026-11-28 12:00:00.000000Z],
          "open-retired"
        )
      ])

    assert [%{state: "active"}] = Repo.all(from(e in EpisodeRow, where: e.mission_id == ^mission))

    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission)

    assert [%{state: "cleared"}] =
             Repo.all(from(e in EpisodeRow, where: e.mission_id == ^mission))

    assert [%{payload: %{"cause" => "rule_retired"}}] =
             Repo.all(from(e in EpisodeEventRow, where: e.kind == "cleared"))

    assert Repo.all(from(s in LatestAlarmStateRow, where: s.mission_id == ^mission)) == []

    # An unchanged poll does not run it again.
    assert {:ok, %{generation: 1}} = MissionRuntimeReconciler.reconcile(mission)
    assert Repo.aggregate(from(e in EpisodeEventRow, where: e.kind == "cleared"), :count) == 1
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

  # 2026-11-12: an active generation the runtime can't apply is visible (MissionRuntimeStatus),
  # after a debounce, and clears when the runtime applies it.
  test "a generation the runtime can't apply reads not_applied after the debounce, then applied" do
    %{mission: mission, bindings: bindings} = fixture()
    good = MissionRuntimeSpec.content_sha256(bindings)
    set_hash!(mission, "wrong")

    assert {:error, {:mission_runtime_spec_mismatch, :binding_set_content_sha256}} =
             MissionRuntimeReconciler.reconcile(mission)

    snapshot = MissionRuntimeReconciler.snapshot(mission)
    assert %DateTime{} = snapshot.failing_since
    later = DateTime.add(snapshot.failing_since, 61, :second)

    assert MissionRuntimeStatus.status(mission, snapshot.failing_since) == nil

    assert %{state: "not_applied", reason: "spec_mismatch", desired_generation: 1} =
             status = MissionRuntimeStatus.status(mission, later)

    assert status.since == snapshot.failing_since
    assert %DateTime{} = status.activated_at
    assert "spec_mismatch" in MissionRuntimeStatus.reasons()

    set_hash!(mission, good)
    assert {:ok, _observation} = MissionRuntimeReconciler.reconcile(mission)

    assert %{state: "applied", applied_generation: 1, applied_at: %DateTime{}} =
             MissionRuntimeStatus.status(mission, later)
  end

  test "a generation step publishes attention_changed, so /counts' CONVERGING clears (lead)" do
    suffix = System.unique_integer([:positive])
    {org, mission} = {"org-runtime-step-#{suffix}", "mission-runtime-step-#{suffix}"}
    persist_mission_scope(org, mission)
    :ok = ScopedReadUpdates.subscribe(:attention_changed, org, mission)

    state = fn desired, applied ->
      %{
        mission_id: mission,
        desired_generation: desired,
        applied_generation: applied,
        last_error: nil,
        failing_since: nil,
        applied_at: ~U[2026-11-13 00:00:00Z]
      }
    end

    assert :ok = MissionRuntimeStatus.record(state.(2, 1), nil)
    assert_receive {:attention_changed, ^org, ^mission}

    # Catching up: visibly "applied" before and after, but the generations moved.
    assert :ok = MissionRuntimeStatus.record(state.(2, 2), nil)
    assert_receive {:attention_changed, ^org, ^mission}

    # An unchanged poll says nothing.
    assert :ok = MissionRuntimeStatus.record(state.(2, 2), nil)
    refute_receive {:attention_changed, _, _}, 50
  end

  test "a reconcile that raises is recorded and the reconciler keeps running" do
    %{mission: mission, reconciler: reconciler} = fixture(registered?: true)
    Application.put_env(:cadence, :semantic_algorithm_implementations, :not_a_registry)

    assert {:error, {:reconcile_crashed, _message}} = MissionRuntimeReconciler.reconcile(mission)
    assert Process.alive?(reconciler)
    assert %{last_error: {:reconcile_crashed, _}} = MissionRuntimeReconciler.snapshot(mission)

    later = DateTime.add(DateTime.utc_now(), 61, :second)

    assert %{state: "not_applied", reason: "reconcile_crashed"} =
             MissionRuntimeStatus.status(mission, later)
  end

  defp set_hash!(mission, hash) do
    for table <- ~w(mission_binding_set_activations mission_active_binding_sets) do
      Repo.query!(
        "UPDATE #{table} SET binding_set_content_sha256 = $1 WHERE mission_id = $2",
        [hash, mission]
      )
    end
  end

  defp fixture(opts \\ []) do
    suffix = System.unique_integer([:positive])
    org = "org-reconcile-#{suffix}"
    mission = "mission-reconcile-#{suffix}"
    persist_mission_scope(org, mission)

    # `populated: n`: n spacecraft with real endpoints, so the version is membership with real
    # artifacts (an empty set expands nothing and pins no expansion path).
    bindings =
      case opts[:populated] do
        nil ->
          BindingSet.new(%{
            organization_id: org,
            mission_id: mission,
            binding_set_id: "basis",
            version: 1
          })

        craft ->
          BindingFleet.persist_endpoints!(org, mission, craft)
          BindingFleet.build(org, mission, "basis", 1, craft)
      end

    assert {:ok, ^bindings} = Cadence.Governance.persist_binding_set(org, bindings)

    # The activation records the hash of the stored set (what admission hashes), not of the
    # builder's struct, whose lists are not in the stored order.
    {:ok, bindings} = Cadence.Governance.fetch_binding_set(org, mission, "basis", 1)

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
