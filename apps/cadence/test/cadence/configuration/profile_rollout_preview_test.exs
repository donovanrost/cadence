defmodule Cadence.Configuration.ProfileRolloutPreviewTest do
  @moduledoc """
  A profile move's preview at fleet scale (director 11-14: step 4's preview, a catalog move on a
  profile with 'Also move the 499', ran past the 20 s checkout and returned 422 on a quiet DB).
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.SpacecraftStore

  @fleet 500

  setup do
    org = "org-rollout-preview"
    mid = "mission-rollout-preview"
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

  @tag timeout: 600_000
  test "a profile catalog move previewed for the whole fleet", c do
    ops = fleet_move!(c)

    {result, ms, queries, by_query} =
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

  # Step 4 (11-15): the APPLY of the same move ran past its 120 s transaction timeout and rolled
  # back. Each spacecraft's compile re-read the same catalog and mission-model revisions.
  @tag timeout: 600_000
  test "a profile catalog move applied to the whole fleet", c do
    ops = fleet_move!(c)
    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Move"}, ops)

    {result, ms, queries, by_query} =
      measure(fn ->
        Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
          reason: "Move the whole fleet to rev 2",
          expected_version: staged.version,
          acknowledged_holds: true
        })
      end)

    assert {:ok, %{state: :applied}} = result

    # Each immutable revision is read once for the apply, not once per spacecraft
    # (Platform.ReadMemo): before, ~2,000 reads of large JSONB inside the transaction.
    # (A runtime plan is 4 queries, one per target; 12 for the 3 revisions involved.)
    for {reader, bound} <- [
          {"Catalog.fetch_revision", 4},
          {"MissionModels.fetch_revision", 4},
          {"MissionModels.fetch_plan", 16}
        ] do
      assert reads(by_query, reader) <= bound, "#{reader}: #{top(by_query)}"
    end

    # Still ~15 per spacecraft (each spacecraft's derived revision and binding rules are
    # written, and its sources and drafts read): 7,345 on 11-15. One more per-spacecraft query
    # adds 500, so the bound catches it.
    assert queries <= @fleet * 16, "#{queries} queries for #{@fleet} spacecraft: #{top(by_query)}"

    # The apply is one transaction with a 120 s timeout. Alone it took 4.8 s on 11-15; late in a
    # full suite run, 47 s. So the budget is half the timeout: the old behaviour (past 120 s) fails
    # it, and the query bounds above are the sharp regression check.
    assert ms < 60_000, "#{ms} ms for #{@fleet} spacecraft"
  end

  # Queries a Cadence function ran (by the caller recorded with each query).
  defp reads(by_query, function) do
    by_query
    |> Enum.filter(fn {key, _n} -> String.contains?(key, function <> "/") end)
    |> Enum.map(fn {_key, n} -> n end)
    |> Enum.sum()
  end

  # The whole fleet on one profile pinned to v1, and the ops that move its catalog to rev 2.
  defp fleet_move!(c) do
    fleet = [
      c.first
      | Enum.map(2..@fleet, fn i ->
          Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Fleet #{i}")
        end)
    ]

    tokens = Map.new(fleet, fn craft -> {craft.spacecraft_id, save(c, craft)} end)
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
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id, revision_label: "Rev 2")

    [
      %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: profile,
        changes: [%{path: "catalog_revision_id", value: rev2.catalog_revision_id}],
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
  defp measure(fun) do
    test_pid = self()
    handler = "rollout-preview-#{System.unique_integer([:positive])}"
    table = :ets.new(:queries, [:public, :set])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        if self() == test_pid, do: count_query(table, metadata)
      end,
      nil
    )

    started = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      ms = System.monotonic_time(:millisecond) - started
      by_query = :ets.tab2list(table)
      {result, ms, by_query |> Enum.map(&elem(&1, 1)) |> Enum.sum(), by_query}
    after
      :telemetry.detach(handler)
    end
  end

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

  defp save(c, craft) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    {:ok, _} =
      Drafts.save(c.scope, c.mission.mission_id, craft.spacecraft_id, current.token, document)

    Drafts.snapshot(c.mission, craft).token
  end
end
