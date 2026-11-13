defmodule Cadence.Control.ActivationResumeTest do
  @moduledoc """
  Resume an approved activation whose apply failed or stalled (L10; director, 2026-11-13): a
  manual, audited retry under the execution lock, and the `activation_apply` attention item that
  surfaces it.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.{ActivationExecutionRow, ApplyAttention, ExecutionLock}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.OperationalEvents.EventRow

  @org "org-activation-resume"
  @mid "mission-activation-resume"

  setup do
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(@org, @mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(@org, @mid)
    scope = Fixtures.user_scope(@org, "operator")
    policy = ActivationPolicy.load(@org, @mid)

    {:ok, _} =
      ActivationPolicy.save(scope, @mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    c = %{mission: mission, scope: scope, revision: revision}
    second = Fixtures.persist_spacecraft!(@org, @mid, display_name: "Fleet 2")
    tokens = Map.new([first, second], &{&1.spacecraft_id, save(c, &1)})
    {:ok, request} = Review.request_many(scope, @mid, tokens)
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)

    Map.merge(c, %{request: request, approved: approved, id: request.activation_request_id})
  end

  test "a failed apply shows in Now, the approver resumes it, and it resolves as applied", c do
    interrupt_apply!()
    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(c.approved)
    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    assert [item] = ApplyAttention.items(@org, @mid)

    assert %{
             id: id,
             source: "activation_apply",
             conflict: "apply_failed",
             error_code: "activation_execution_interrupted",
             error: error,
             kind: "spacecraft_configuration",
             summary: "Spacecraft configuration for 2 spacecraft",
             spacecraft_count: 2,
             spacecraft_id: nil
           } = item

    assert id == c.id
    assert error == "Applying was cut off: Cadence lost its database connection partway."
    assert item.retryable

    assert {:ok, %{status: :succeeded}} = ControlActivations.resume(c.scope, @mid, c.id)
    assert ApplyAttention.items(@org, @mid) == []

    assert [%{action: "applied", resolved_by: %{"kind" => "system"}}] =
             ApplyAttention.resolved_since(@org, @mid, DateTime.add(DateTime.utc_now(), -30))

    # Audited, naming who resumed it.
    assert [event] =
             Repo.all(from(e in EventRow, where: e.kind == "activation_resumed"))

    assert inspect(event.actor_document) =~ c.scope.user.user_id

    # Done: nothing left to resume.
    assert {:error, {:nothing_to_resume, "succeeded"}} =
             ControlActivations.resume(c.scope, @mid, c.id)
  end

  test "an in-progress execution resumes only once it has stalled", c do
    interrupt_apply!()
    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(c.approved)
    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    # As if an executor died two minutes in, leaving it in progress.
    set_execution!(c.id, :in_progress, DateTime.add(DateTime.utc_now(), -120))

    assert {:error, {:nothing_to_resume, "in_progress"}} =
             ControlActivations.resume(c.scope, @mid, c.id)

    assert ApplyAttention.items(@org, @mid) == []

    # Eleven minutes on, nobody holds its lock: stalled.
    set_execution!(c.id, :in_progress, DateTime.add(DateTime.utc_now(), -660))
    assert [%{conflict: "apply_stalled", error_code: nil}] = ApplyAttention.items(@org, @mid)
    assert {:ok, %{status: :succeeded}} = ControlActivations.resume(c.scope, @mid, c.id)
  end

  test "a live executor's lock refuses a resume", c do
    interrupt_apply!()
    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(c.approved)
    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    # Another database session (another node's executor) holds the request's lock.
    {:ok, other} = Postgrex.start_link(Keyword.drop(Repo.config(), [:pool, :pool_size]))
    key = ExecutionLock.key(c.id)
    Postgrex.query!(other, "SELECT pg_advisory_lock($1::bigint)", [key])

    assert {:error, :activation_execution_in_progress} =
             ControlActivations.resume(c.scope, @mid, c.id)

    Postgrex.query!(other, "SELECT pg_advisory_unlock($1::bigint)", [key])
    GenServer.stop(other)
    assert {:ok, %{status: :succeeded}} = ControlActivations.resume(c.scope, @mid, c.id)
  end

  test "the lock dies with its executor, so a killed execution can be resumed", c do
    interrupt_apply!()
    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(c.approved)
    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    # An executor holding the lock, killed mid-way (a crashed node or a killed task).
    test_pid = self()

    executor =
      spawn(fn ->
        ExecutionLock.run(c.id, fn ->
          send(test_pid, :locked)
          Process.sleep(:infinity)
        end)
      end)

    assert_receive :locked, 5_000
    refute ExecutionLock.free?(c.id)

    assert {:error, :activation_execution_in_progress} =
             ControlActivations.resume(c.scope, @mid, c.id)

    Process.exit(executor, :kill)

    # Its own connection closes with it, and Postgres releases the session lock.
    assert eventually(fn -> ExecutionLock.free?(c.id) end)
    assert {:ok, %{status: :succeeded}} = ControlActivations.resume(c.scope, @mid, c.id)
  end

  test "a stale review isn't retried: it needs a new request", c do
    interrupt_apply!()
    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(c.approved)
    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    {1, _} =
      from(e in ActivationExecutionRow, where: e.activation_request_id == ^c.id)
      |> Repo.update_all(
        set: [
          error_document: %{
            "code" => "spacecraft_configuration_review_stale",
            "reason" => ":spacecraft_configuration_review_stale"
          }
        ]
      )

    assert [%{retryable: false, error: error}] = ApplyAttention.items(@org, @mid)
    assert error =~ "A spacecraft's configuration changed after it was reviewed"

    assert {:error, {:not_resumable, "spacecraft_configuration_review_stale"}} =
             ControlActivations.resume(c.scope, @mid, c.id)
  end

  test "a resume is refused outside the approver's mission and for an unknown request", c do
    other_mission = %{c.scope | mission_id: "mission-elsewhere"}

    assert {:error, :forbidden} = ControlActivations.resume(other_mission, @mid, c.id)

    assert {:error, :activation_request_not_found} =
             ControlActivations.resume(c.scope, @mid, "activation_request_missing")
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(100) && eventually(fun, attempts - 1)
    end
  end

  defp interrupt_apply! do
    Repo.query!("""
    CREATE OR REPLACE FUNCTION pg_temp.interrupt_apply() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'connection lost (injected)'; END $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER interrupt_apply BEFORE UPDATE ON spacecraft_application_bindings
    FOR EACH ROW EXECUTE FUNCTION pg_temp.interrupt_apply()
    """)
  end

  defp set_execution!(request_id, status, started_at) do
    {1, _} =
      from(e in ActivationExecutionRow, where: e.activation_request_id == ^request_id)
      |> Repo.update_all(set: [status: status, started_at: started_at, completed_at: nil])
  end

  defp save(c, craft) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    assert {:ok, _} = Drafts.save(c.scope, @mid, craft.spacecraft_id, current.token, document)
    Drafts.snapshot(c.mission, craft).token
  end
end
