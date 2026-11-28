defmodule Cadence.Configuration.ProfileRolloutPreviewTest do
  @moduledoc """
  A profile move's preview at fleet scale (director 11-14: step 4's preview, a catalog move on a
  profile with 'Also move the 499', ran past the 20 s checkout and returned 422 on a quiet DB).
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations.GenerationReceipts
  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.CompositionPins
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.CompositionFixtures
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @fleet String.to_integer(System.get_env("ROLLOUT_FLEET", "500"))

  defp setup_mission(label, revision_options, apids) do
    org = "org-rollout-#{label}"
    mid = "mission-rollout-#{label}"
    {first, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid, revision_options)

    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{
      org: org,
      mission: mission,
      scope: scope,
      first: first,
      revision: revision,
      revision_options: revision_options,
      apids: apids
    }
  end

  @tag timeout: 600_000
  test "a profile catalog move previewed for the whole fleet" do
    c = setup_mission("preview", [yaml: Fixtures.dev_sized_yaml()], Fixtures.dev_sized_apids())
    ops = fleet_move!(c, @fleet)

    {result, ms, queries, by_query, _receipt_writes} =
      measure(fn -> Configuration.preview(c.scope, c.mission.mission_id, {:ops, ops}) end)

    # Every spacecraft moves, and the HOLDs speak for all 500.
    assert {:ok, %{verdict: :hold} = preview} = result
    assert [%{changes: @fleet}] = preview.effects
    items = Enum.find(preview.checks, &(&1.key == "compatibility")).items

    assert Enum.any?(
             items,
             &(&1[:reason] == :framing_unverified and &1[:spacecraft_count] == @fleet)
           )

    assert Enum.any?(items, &(&1[:reason] == :catalog_change))

    # Not per spacecraft: before 11-14 it was about 14 per spacecraft (7,110 queries for 500), the
    # same profile version and each spacecraft's routes read again and again.
    assert queries <= 200, "#{queries} queries for #{@fleet} spacecraft: #{top(by_query)}"

    # Dev's target is 5 s for the whole preview; a loaded CI host gets twice that.
    assert ms < 10_000, "#{ms} ms for #{@fleet} spacecraft"
  end

  @tag timeout: 180_000
  test "a fleet catalog move uses a constant number of statements from 100 to 1,000 spacecraft" do
    small = count_apply(100)
    large = count_apply(1_000)

    assert small.queries == large.queries,
           "100 craft: #{small.queries}, 1,000 craft: #{large.queries}; #{top(large.by_query)}"

    assert {small.receipt_writes, large.receipt_writes} == {1, 1}

    assert small.projection_queries == large.projection_queries,
           "100 craft: #{small.projection_queries}, 1,000 craft: #{large.projection_queries}"
  end

  # ADR-020 P3 M2 (#451): a monitoring apply over the whole fleet (every craft moves to its
  # composition's head revision) is one compile per composition and no per-craft statement.
  @tag timeout: 240_000
  test "a monitoring apply over the fleet uses a constant number of statements from 100 to 1,000" do
    small = count_monitoring(100)
    large = count_monitoring(1_000)

    assert small.queries == large.queries,
           "100 craft: #{small.queries}, 1,000 craft: #{large.queries}; #{top(large.by_query)}"
  end

  defp count_monitoring(size) do
    c = setup_mission("monitoring-#{size}", [], [42])
    ops = fleet_move!(c, size, enable_telemetry: true)
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Move"}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
        reason: "Move the whole fleet to rev 2",
        expected_version: staged.version,
        acknowledged_holds: true
      })

    {:ok, monitoring} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Limits"}, [
        %{
          kind: "monitoring_policy",
          action: "create",
          document: %{
            "name" => "Fleet limit",
            "parameter_id" => parameter_id!(c),
            "policy_kind" => "limit",
            "default_rules" => [%{"kind" => "range", "upper" => 40, "severity" => "warning"}]
          }
        }
      ])

    {result, _ms, queries, by_query, _receipts} =
      measure(c.mission.mission_id, fn ->
        Configuration.submit(c.scope, c.mission.mission_id, monitoring.change_set_id, %{
          reason: "A fleet-wide temperature limit",
          expected_version: monitoring.version
        })
      end)

    assert {:ok, %{state: :applied}} = result
    %{queries: queries, by_query: by_query}
  end

  defp parameter_id!(c) do
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mission.mission_id)
    {:ok, %{entries: entries}} = Cadence.Applications.SpacecraftConfiguration.Active.load(mission)
    revision = entries |> Map.values() |> hd() |> get_in(["mission_model", "revision_id"])
    {:ok, model} = Cadence.MissionModels.fetch_revision(c.org, c.mission.mission_id, revision)

    model.declarations
    |> Map.values()
    |> Enum.find(&(&1.kind == :parameter))
    |> Map.fetch!(:semantic_id)
  end

  defp count_apply(size) do
    c = setup_mission("apply-#{size}", [], [42])
    ops = fleet_move!(c, size, enable_telemetry: true)
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Move"}, ops)

    {result, _ms, queries, by_query, receipt_writes} =
      measure(c.mission.mission_id, fn ->
        Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
          reason: "Move the whole fleet to rev 2",
          expected_version: staged.version,
          acknowledged_holds: true
        })
      end)

    assert {:ok, %{state: :applied, runtime: :applied}} = result

    [%{changes: [%{value: composition}]}] = ops
    rev2 = CompositionPins.catalog_revision_for(c.org, c.mission.mission_id, composition)

    projection_queries = count_projection(c, rev2, size)

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM spacecraft_configuration_artifacts WHERE organization_id = $1 AND mission_id = $2",
               [c.org, c.mission.mission_id]
             )

    assert %{rows: [[^size]]} =
             Repo.query!(
               "SELECT count(*) FROM spacecraft_configuration_heads WHERE organization_id = $1 AND mission_id = $2",
               [c.org, c.mission.mission_id]
             )

    assert %{rows: [["membership", ^size]]} =
             Repo.query!(
               """
               SELECT storage_form, member_count FROM governed_binding_sets
               WHERE organization_id = $1 AND mission_id = $2 ORDER BY version DESC LIMIT 1
               """,
               [c.org, c.mission.mission_id]
             )

    assignments = 2 * size

    assert %{rows: [[^assignments]]} =
             Repo.query!(
               "SELECT count(*) FROM spacecraft_configuration_assignments WHERE organization_id = $1 AND mission_id = $2",
               [c.org, c.mission.mission_id]
             )

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM mission_generation_receipts WHERE organization_id = $1 AND mission_id = $2",
               [c.org, c.mission.mission_id]
             )

    %{
      queries: queries,
      by_query: by_query,
      receipt_writes: receipt_writes,
      projection_queries: projection_queries
    }
  end

  defp count_projection(c, revision, size) do
    {activation, applied_at} = GenerationReceipts.latest(c.org, c.mission.mission_id)

    {configs, _ms, queries, _by_query, _receipt_writes} =
      measure(fn -> TelemetryDecom.list_configs(c.org, c.mission.mission_id) end)

    assert length(configs) == size

    assert Enum.all?(configs, fn config ->
             config.catalog_revision_id == revision and config.enabled and
               config.applied_generation == activation.generation and
               config.applied_at == applied_at
           end)

    queries
  end

  # The whole fleet on one profile pinned to v1, and the ops that move its catalog to rev 2.
  defp fleet_move!(c, size, opts \\ []) do
    fleet = [
      c.first
      | Enum.map(2..size, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, fn craft -> {craft.spacecraft_id, save(c, craft, opts)} end)
    {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, tokens)
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    profile = profile!(c)

    # Pinned to version 1, as the dev fleet is, so the move needs 'all_versions'.
    for craft <- fleet do
      {:ok, stored} =
        SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, craft.spacecraft_id)

      {:ok, _} =
        SpacecraftStore.update_spacecraft(c.org, %{
          stored
          | spacecraft_type_id: profile,
            spacecraft_type_version: 1
        })
    end

    rev2 =
      Fixtures.persist_imported_revision!(
        c.org,
        c.mission.mission_id,
        Keyword.put(c.revision_options, :revision_label, "Rev 2")
      )

    [
      %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: profile,
        changes: [
          %{
            path: "composition_id",
            value: CompositionFixtures.pin!(c.org, c.mission.mission_id, rev2.catalog_revision_id)
          }
        ],
        options: %{rollout: "all_versions"}
      }
    ]
  end

  defp top(by_query) do
    by_query
    |> Enum.sort_by(fn {_sql, n} -> -n end)
    |> Enum.take(5)
    |> Enum.map_join("; ", fn {sql, n} -> "#{n} × #{sql}" end)
  end

  defp profile!(c) do
    id = "profile-rollout-#{System.unique_integer([:positive])}"

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Profile"}, [
        %{
          kind: "spacecraft_profile",
          action: :create,
          entity_id: id,
          document: %{
            "display_name" => "Fleet profile",
            "downlink_protocol" => "tm",
            "uplink_protocol" => "tc",
            "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
          }
        }
      ])

    {:ok, %{state: :applied}} =
      Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
        reason: "Create the fleet profile for the rollout preview",
        expected_version: staged.version,
        acknowledged_holds: true
      })

    id
  end

  # The calling process's queries during `fun`, counted by SQL and the Cadence functions that ran
  # them (so a failure names the per-spacecraft reader).
  defp measure(mission_id \\ nil, fun) do
    test_pid = self()
    handler = "rollout-preview-#{System.unique_integer([:positive])}"
    table = :ets.new(:queries, [:public, :set])
    receipts = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        if self() == test_pid, do: count_query(table, metadata)
        count_receipt(metadata, mission_id, receipts)
      end,
      nil
    )

    started = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      ms = System.monotonic_time(:millisecond) - started
      by_query = :ets.tab2list(table)

      {result, ms, by_query |> Enum.map(&elem(&1, 1)) |> Enum.sum(), by_query,
       :counters.get(receipts, 1)}
    after
      :telemetry.detach(handler)
    end
  end

  # The reconciler writes from its own process. Scope this count to the selected mission.
  defp count_receipt(
         %{source: "mission_generation_receipts", params: [_org, mission | _]},
         mission,
         receipts
       )
       when is_binary(mission),
       do: :counters.add(receipts, 1, 1)

  defp count_receipt(_metadata, _mission, _receipts), do: :ok

  defp count_query(table, metadata) do
    sql = metadata[:query] |> to_string() |> String.slice(0, 60)
    {:current_stacktrace, stack} = Process.info(self(), :current_stacktrace)
    key = sql <> " | " <> caller(stack)
    :ets.update_counter(table, key, 1, {key, 0})
  end

  defp caller(stack) do
    stack
    |> Enum.filter(fn {mod, _f, _a, _loc} -> cadence_caller?(inspect(mod)) end)
    |> Enum.take(2)
    |> Enum.map_join(" < ", fn {mod, f, a, _loc} -> "#{inspect(mod)}.#{f}/#{arity(a)}" end)
  end

  defp cadence_caller?(name) do
    String.starts_with?(name, "Cadence.") and not String.starts_with?(name, "Cadence.Repo") and
      not String.contains?(name, "Store") and not String.contains?(name, "Row")
  end

  defp arity(args) when is_list(args), do: length(args)
  defp arity(arity), do: arity

  defp save(c, craft, opts) do
    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => c.apids
      })

    if opts[:enable_telemetry] do
      :ok =
        Fixtures.change_set_switches!(c.org, c.mission.mission_id, craft.spacecraft_id, document)
    end

    current = Drafts.snapshot(c.mission, craft)

    {:ok, _} =
      Drafts.save(c.scope, c.mission.mission_id, craft.spacecraft_id, current.token, document)

    Drafts.snapshot(c.mission, craft).token
  end
end
