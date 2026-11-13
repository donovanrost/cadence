defmodule Cadence.Activations.FleetConfigurationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.SpacecraftModelBindings
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead
  alias Cadence.Runtime.SourceRuntimeBases

  setup do
    org = "org-fleet-activation"
    mid = "mission-fleet-activation"
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{org: org, mission: mission, scope: scope, first: first, revision: revision}
  end

  # About 20 s on CI. Before 2026-11-13 the decom apply reloaded the mission's bindings once per
  # spacecraft inside its configuration lock; under load it held the connection past the 15 s
  # transaction timeout and failed with DBConnection "tcp recv: closed". The query and row bounds
  # below keep that from coming back quietly.
  @tag timeout: 180_000
  test "500 spacecraft activate together and retain usable command and telemetry bases", c do
    fleet = [
      c.first
      | Enum.map(2..500, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, fn craft -> {craft.spacecraft_id, save(c, craft)} end)
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert byte_size(Jason.encode!(request.metadata)) > 65_536
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)

    {{:ok, execution}, queries, rows} =
      count_queries(fn -> ControlActivations.execute(approved) end)

    assert execution.status == :succeeded

    # Linear in the fleet: about 19 queries and 26 rows per spacecraft (2026-11-13). Reloading the
    # mission's bindings per spacecraft made rows quadratic and held the configuration lock past
    # its timeout ('tcp recv: closed'); a per-spacecraft lookup added inside the lock shows here.
    assert queries <= 20 * 500 + 200, "#{queries} queries for 500 spacecraft"
    assert rows <= 30 * 500 + 500, "#{rows} rows for 500 spacecraft"

    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 500

    for craft <- fleet do
      entry = active.entries[craft.spacecraft_id]
      assert entry["commanding_enabled"]
      assert entry["document"]["telemetry_enabled"]

      assert {:ok, config} =
               TelemetryDecom.fetch_config(c.org, c.mission.mission_id, craft.spacecraft_id)

      assert config.applied_binding_set_version == active.binding_set.version
      assert config.applied_at

      assert Activations.latest_spacecraft_request(
               c.org,
               c.mission.mission_id,
               craft.spacecraft_id
             ).activation_request_id == request.activation_request_id
    end

    last = List.last(fleet)
    source = hd(active.entries[last.spacecraft_id]["source_endpoint_ids"])

    assert {:ok, basis} =
             Cadence.Activations.with_locked_command_basis(
               c.org,
               c.mission.mission_id,
               fn activation ->
                 SpacecraftModelBindings.command_basis(activation, source)
               end
             )

    assert basis.mission_model_revision_id == c.revision.mission_model_revision_id
    assert {:ok, spec} = Cadence.Runtime.Missions.applied_spec(c.mission.mission_id)
    assert SourceRuntimeBases.count(spec.source_runtime_bases) >= 500

    assert {:ok, %{review: %{state: "active"}}} =
             ConfigurationRead.load(c.scope, c.mission, last.spacecraft_id, "changes")
  end

  @tag timeout: 300_000
  test "a 550-spacecraft fleet activates in two review batches", c do
    fleet = [
      c.first
      | Enum.map(2..550, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    {block1, block2} = Enum.split(fleet, 500)

    for batch <- [block1, block2] do
      tokens = Map.new(batch, fn craft -> {craft.spacecraft_id, save(c, craft)} end)
      assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
      assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
      assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
    end

    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 550

    last = List.last(block2)
    source = hd(active.entries[last.spacecraft_id]["source_endpoint_ids"])

    assert {:ok, _basis} =
             Cadence.Activations.with_locked_command_basis(
               c.org,
               c.mission.mission_id,
               &SpacecraftModelBindings.command_basis(&1, source)
             )
  end

  test "a database failure mid-apply records the execution failed, and a retry completes it", c do
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet 2")
    tokens = Map.new([c.first, second], fn craft -> {craft.spacecraft_id, save(c, craft)} end)
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)

    # The decom apply's stamp is the first write to application bindings after admission.
    Repo.query!("""
    CREATE FUNCTION pg_temp.interrupt_apply() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'connection lost (injected)'; END $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER interrupt_apply BEFORE UPDATE ON spacecraft_application_bindings
    FOR EACH ROW EXECUTE FUNCTION pg_temp.interrupt_apply()
    """)

    assert {:error, :activation_execution_interrupted} = ControlActivations.execute(approved)

    assert {:ok, %{status: :failed, error_document: %{"code" => code, "reason" => reason}}} =
             ControlActivations.fetch_execution(request.activation_request_id)

    assert code == "activation_execution_interrupted"
    assert reason =~ "injected"

    Repo.query!("DROP TRIGGER interrupt_apply ON spacecraft_application_bindings")

    # Every step is idempotent, so the same approved request completes on a retry.
    assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 2
  end

  test "fleet review retains independent approval and rejects self approval", c do
    policy = ActivationPolicy.load(c.org, c.mission.mission_id)

    {:ok, _} =
      ActivationPolicy.save(c.scope, c.mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")
    tokens = Map.new([c.first, second], &{&1.spacecraft_id, save(c, &1)})
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert request.state == :approval_pending

    assert {:error, :activation_request_not_approved} =
             Activations.fetch_approved(request.activation_request_id)

    assert {:error, :activation_self_approval_forbidden} =
             Activations.approve(c.scope, request.activation_request_id, "Reviewed fleet")

    assert {:ok, execution} =
             ControlActivations.approve_and_execute(
               Fixtures.user_scope(c.org, "reviewer"),
               request.activation_request_id,
               "Reviewed both spacecraft"
             )

    assert execution.status == :succeeded
  end

  test "a stale spacecraft rejects the whole fleet activation", c do
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")
    tokens = Map.new([c.first, second], &{&1.spacecraft_id, save(c, &1)})
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    save(c, second, false)
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:error, :spacecraft_configuration_changed} = ControlActivations.execute(approved)

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, first} =
      Cadence.SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, c.first.spacecraft_id)

    refute first.metadata["spacecraft_configuration_revision_id"]
  end

  test "an empty or oversized review is rejected", c do
    assert {:error, :spacecraft_configuration_review_unavailable} =
             Review.request_many(c.scope, c.mission.mission_id, %{})

    tokens = Map.new(1..501, &{"spacecraft-#{&1}", "token"})

    assert {:error, :spacecraft_configuration_review_unavailable} =
             Review.request_many(c.scope, c.mission.mission_id, tokens)
  end

  # Queries the calling process runs inside `fun`, and the rows they return.
  defp count_queries(fun) do
    test_pid = self()
    handler = "fleet-activation-queries-#{System.unique_integer([:positive])}"
    counter = :counters.new(2, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        if self() == test_pid, do: count_query(counter, metadata[:result])
      end,
      nil
    )

    try do
      result = fun.()
      {result, :counters.get(counter, 1), :counters.get(counter, 2)}
    after
      :telemetry.detach(handler)
    end
  end

  defp count_query(counter, result) do
    :counters.add(counter, 1, 1)

    case result do
      {:ok, %{num_rows: rows}} when is_integer(rows) -> :counters.add(counter, 2, rows)
      _other -> :ok
    end
  end

  defp save(c, craft, commanding \\ true) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => commanding,
        "handled_apids" => [42]
      })

    assert {:ok, _} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               craft.spacecraft_id,
               current.token,
               document
             )

    Drafts.snapshot(c.mission, craft).token
  end
end
