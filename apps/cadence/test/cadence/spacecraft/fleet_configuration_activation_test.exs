defmodule Cadence.Activations.FleetConfigurationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.ActivationRequests
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
    # The metadata is a fleet reference and a review reference (#734), not 500 entries.
    assert byte_size(Jason.encode!(request.metadata)) < 2_000
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

  # #734 / #727: 1,000 spacecraft through one review request, from "everything that's saved" to
  # the applied fleet. The timings print so the PR can quote them.
  @tag timeout: 900_000
  test "1,000 spacecraft are reviewed and activated in one request (#734)", c do
    fleet = [
      c.first
      | Enum.map(2..1_000, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    for craft <- fleet, do: save(c, craft)

    {saved_us, {:ok, tokens}} =
      :timer.tc(fn -> Review.saved_tokens(c.scope, c.mission.mission_id) end)

    assert map_size(tokens) == 1_000

    {review_us, {:ok, request}} =
      :timer.tc(fn -> Review.request_many(c.scope, c.mission.mission_id, tokens) end)

    assert byte_size(Jason.encode!(request.metadata)) < 2_000
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {apply_us, {:ok, execution}} = :timer.tc(fn -> ControlActivations.execute(approved) end)
    assert execution.status == :succeeded

    IO.puts(
      "1,000 spacecraft: saved_tokens #{div(saved_us, 1000)} ms, review #{div(review_us, 1000)} ms, " <>
        "apply #{div(apply_us, 1000)} ms"
    )

    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 1_000

    assert {:error, :nothing_to_review} = Review.saved_tokens(c.scope, c.mission.mission_id)
  end

  test "tokens/2 equals each snapshot token: saved, unsaved, and one whose application basis moved (#885)",
       c do
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet 2")
    third = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet 3")
    save(c, c.first)
    save(c, second)
    # `third` has no saved revision: its token has no revision id.

    entries = [
      {c.first, Drafts.latest(c.org, c.mission.mission_id, c.first.spacecraft_id)},
      {second, Drafts.latest(c.org, c.mission.mission_id, second.spacecraft_id)},
      {third, nil}
    ]

    tokens = Drafts.tokens(c.mission, entries)
    assert map_size(tokens) == 3

    for {craft, _row} <- entries do
      assert tokens[craft.spacecraft_id] == Drafts.snapshot(c.mission, craft).token
    end

    assert Drafts.tokens(c.mission, []) == %{}
  end

  # #885: all_saved resolves its tokens in a number of queries that does not grow with the fleet
  # (the spacecraft rows come in batches of 100, one more query per hundred; nothing is read per
  # craft). 1,000 craft cost 3 queries per 1,000 more than 100 do, not ~10 per craft.
  @tag timeout: 600_000
  test "saved_tokens reads the fleet in a fixed number of queries, not per spacecraft (#885)",
       c do
    first_hundred = [
      c.first
      | Enum.map(2..100, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    for craft <- first_hundred, do: save(c, craft)

    {{:ok, small}, small_queries, _rows} =
      count_queries(fn -> Review.saved_tokens(c.scope, c.mission.mission_id) end)

    assert map_size(small) == 100

    more =
      Enum.map(101..1_000, fn i ->
        Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
      end)

    for craft <- more, do: save(c, craft)

    {{:ok, large}, large_queries, _rows} =
      count_queries(fn -> Review.saved_tokens(c.scope, c.mission.mission_id) end)

    assert map_size(large) == 1_000
    # One more spacecraft-row query per extra hundred (9), and nothing per craft.
    assert large_queries - small_queries <= 12,
           "#{small_queries} queries for 100 craft, #{large_queries} for 1,000"

    assert large_queries < 60, "#{large_queries} queries for 1,000 craft"
    IO.puts("saved_tokens: #{small_queries} queries for 100 craft, #{large_queries} for 1,000")
    # The same tokens a per-craft snapshot gives, for a sample.
    for craft <- Enum.take_every(first_hundred, 25) do
      assert large[craft.spacecraft_id] == Drafts.snapshot(c.mission, craft).token
    end
  end

  # #1020: approving a fleet review admits every spacecraft inside one transaction. It used to run
  # about six queries and a row lock per spacecraft there, and failed (the 15 s transaction limit)
  # somewhere between 500 and 1,000. Now the reads are in bulk, so the cost is a number of queries
  # that doesn't grow with the fleet (the spacecraft rows come in chunks, a handful per hundred).
  @tag timeout: 900_000
  test "approving a review costs a number of queries that doesn't grow per spacecraft; 1,000 pass (#1020)" do
    {small, small_pins} = approve_fleet("org-admit-100", "mission-admit-100", 100)
    {large, large_pins} = approve_fleet("org-admit-1000", "mission-admit-1000", 1_000)

    IO.puts("admit: #{small} queries for 100 craft, #{large} for 1,000")
    assert small_pins == 100 and large_pins == 1_000
    # Growth is the chunked reads, not per craft (the old loop: about 6 per craft, 5,400 more).
    assert large - small <= 25, "#{small} queries for 100 craft, #{large} for 1,000"
    assert large < 100, "#{large} queries for 1,000 craft"
  end

  test "a stale spacecraft in the middle of a large review refuses the whole review and writes nothing (#1020)" do
    c = fleet_context("org-admit-stale", "mission-admit-stale")
    {fleet, _tokens, request} = pending_review(c, 60)
    reviewer = Fixtures.user_scope(c.org, "reviewer")

    # A draft saved after the review: that spacecraft's token no longer matches.
    middle = Enum.at(Enum.sort_by(fleet, & &1.spacecraft_id), 30)
    save(c, middle, false)

    assert {:error, :spacecraft_configuration_changed} =
             ControlActivations.approve(reviewer, request.activation_request_id, "Looked")

    # Nothing was admitted: no spacecraft carries a reviewed revision, and the request is pending.
    assert [] == pinned_revisions(c) |> Enum.reject(&is_nil(elem(&1, 1)))

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(c.scope, request.activation_request_id)
  end

  test "each spacecraft's protocol decides its pin in one review: its own profile, or none (#1020)" do
    c = fleet_context("org-admit-protocol", "mission-admit-protocol")
    second = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet 2")
    third = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet 3")

    protocol = fn frame_size ->
      %{
        "downlink" => "tm",
        "uplink" => "tc",
        "frame_size" => frame_size,
        "secondary_header_length" => 0,
        "insert_zone_length" => 0,
        "ocf_length" => 0,
        "truncated_primary_header" => false
      }
    end

    tokens = %{
      c.first.spacecraft_id => save(c, c.first, true, %{"protocol" => protocol.(1024)}),
      second.spacecraft_id => save(c, second, true, %{"protocol" => protocol.(2048)}),
      third.spacecraft_id => save(c, third, true, %{"protocol" => nil})
    }

    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    reviewer = Fixtures.user_scope(c.org, "reviewer")

    assert {:ok, _, _, _} =
             ControlActivations.approve(reviewer, request.activation_request_id, "ok")

    stored =
      Map.new(
        Cadence.SpacecraftStore.list_spacecraft(c.org, c.mission.mission_id),
        &{&1.spacecraft_id, &1}
      )

    latest = Drafts.latest_many(c.org, c.mission.mission_id, Map.keys(stored))

    for {craft, frame_size} <- [{c.first, 1024}, {second, 2048}] do
      row = latest[craft.spacecraft_id]
      current = stored[craft.spacecraft_id]

      assert current.spacecraft_type_id ==
               "spacecraft_configuration_profile_#{row.configuration_revision_id}"

      assert current.spacecraft_type_version == 1
      assert {:ok, pinned} = Cadence.SpacecraftStore.fetch_pinned_profile(c.mission, current)

      assert SpacecraftConfigurationInput.from_profile(pinned) ==
               protocol.(frame_size)

      assert current.metadata["spacecraft_configuration_revision_id"] ==
               row.configuration_revision_id
    end

    assert %{spacecraft_type_id: nil, spacecraft_type_version: nil} = stored[third.spacecraft_id]
  end

  defp fleet_context(org, mission_id) do
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mission_id)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mission_id)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    %{org: org, mission: mission, scope: scope, first: first, revision: revision}
  end

  defp pending_review(c, count) do
    fleet = [
      c.first
      | Enum.map(2..count, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, &{&1.spacecraft_id, save(c, &1)})
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert request.state == :approval_pending
    {fleet, tokens, request}
  end

  # Approves a pending review of `count` spacecraft (the queries the approval ran, admission
  # included) and returns them with how many spacecraft ended up pinned to their reviewed revision.
  defp approve_fleet(org, mission_id, count) do
    c = fleet_context(org, mission_id)
    {_fleet, _tokens, request} = pending_review(c, count)
    reviewer = Fixtures.user_scope(org, "reviewer")

    {result, queries, _rows} =
      count_queries(fn ->
        ControlActivations.approve(reviewer, request.activation_request_id, "Reviewed fleet")
      end)

    assert {:ok, _request, _decision, _approved} = result

    latest = Drafts.latest_many(org, mission_id, Enum.map(pinned_revisions(c), &elem(&1, 0)))

    pinned =
      Enum.count(pinned_revisions(c), fn {id, revision} ->
        revision != nil and revision == latest[id].configuration_revision_id
      end)

    {queries, pinned}
  end

  # {spacecraft_id, the reviewed revision id its metadata carries (nil before admission)}.
  defp pinned_revisions(c) do
    c.org
    |> Cadence.SpacecraftStore.list_spacecraft(c.mission.mission_id)
    |> Enum.map(&{&1.spacecraft_id, &1.metadata["spacecraft_configuration_revision_id"]})
  end

  @tag timeout: 300_000
  test "a 550-spacecraft fleet is one review: there is no batch cap (#734)", c do
    fleet = [
      c.first
      | Enum.map(2..550, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, fn craft -> {craft.spacecraft_id, save(c, craft)} end)
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    assert {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    assert {:ok, active} = Active.load(c.mission)
    assert map_size(active.entries) == 550

    last = List.last(fleet)
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

    # A review of several spacecraft is decided from the activation, which shows every member
    # (#734, commanding's review): the activation route is the one decision path.
    assert {:error, {:activation_self_approval_forbidden, _via}} =
             ActivationRequests.approve(
               c.scope,
               c.mission.mission_id,
               request.activation_request_id,
               %{
                 "reason" => "Reviewed fleet"
               }
             )

    assert {:ok, %{outcome: "applied"}} =
             ActivationRequests.approve(
               Fixtures.user_scope(c.org, "reviewer"),
               c.mission.mission_id,
               request.activation_request_id,
               %{"reason" => "Reviewed both spacecraft"}
             )

    assert {:ok, execution} =
             ControlActivations.fetch_execution(request.activation_request_id)

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

  test "an empty review is rejected", c do
    assert {:error, :spacecraft_configuration_review_unavailable} =
             Review.request_many(c.scope, c.mission.mission_id, %{})
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

  defp save(c, craft, commanding \\ true, overrides \\ %{}) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      SpacecraftConfigurationInput.empty()
      |> Map.merge(%{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => commanding,
        "handled_apids" => [42]
      })
      |> Map.merge(overrides)

    :ok =
      Fixtures.change_set_switches!(
        c.scope.organization_id,
        c.mission.mission_id,
        craft.spacecraft_id,
        document
      )

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
