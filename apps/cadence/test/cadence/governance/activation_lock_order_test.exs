defmodule Cadence.Governance.ActivationLockOrderTest do
  @moduledoc """
  Every activation path takes its locks in ONE order: the policy lock, the mission's generation
  lock, then its configuration lock (`Cadence.Governance.ActivationLocks`, director 11-17). Paths
  that take two of them in opposite orders can deadlock; one order can't. Each test records the
  advisory locks an operation asks for, in order, and checks that the first time it takes each, it
  never goes back to an earlier one. Recording the order is deterministic; a race would only show
  the interleavings that happened to run.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Platform.ScopedSettings

  @rank %{policy: 1, generation: 2, configuration: 3}

  setup do
    org = "org-lock-order-#{System.unique_integer([:positive])}"
    mid = "mission-lock-order-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    catalog = revision.catalog_revision_id
    %{org: org, mission: mission, scope: scope, craft: craft, catalog: catalog}
  end

  test "a change-set apply takes the policy and generation locks before the configuration lock",
       c do
    set_policy(c.scope, c.mission.mission_id, "direct")
    save(c.scope, c.mission, c.craft, c.catalog, [42])
    {:ok, request} = review(c.scope, c.mission, c.craft)
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    op = %{
      kind: "spacecraft",
      action: :update,
      entity_id: c.craft.spacecraft_id,
      changes: [%{path: "commanding_enabled", value: false}]
    }

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Lock order"}, [op])

    {result, locks} =
      locks_taken(c, fn ->
        Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
          reason: "Lock order test",
          expected_version: staged.version,
          acknowledged_holds: true
        })
      end)

    assert {:ok, %{state: :applied, generation: generation}} = result
    assert is_integer(generation)
    assert_one_order(locks, [:policy, :generation, :configuration])
  end

  test "an approval and the execute after it take the locks in the same order", c do
    set_policy(c.scope, c.mission.mission_id, "independent")
    save(c.scope, c.mission, c.craft, c.catalog, [42])
    {:ok, pending} = review(c.scope, c.mission, c.craft)
    assert pending.state == :approval_pending
    approver = Fixtures.user_scope(c.org, "approver")

    {result, locks} =
      locks_taken(c, fn ->
        ControlActivations.approve(approver, pending.activation_request_id, "Lock order test")
      end)

    assert {:ok, _request, _decision, _approved} = result
    assert_one_order(locks, [:policy, :configuration])

    {:ok, approved} = Activations.fetch_approved(pending.activation_request_id)

    {result, locks} = locks_taken(c, fn -> ControlActivations.execute(approved) end)

    assert {:ok, %{status: :succeeded}} = result
    assert_one_order(locks, [:policy, :generation, :configuration])
  end

  # Each lock's first acquisition, in order; a later one may re-enter (same transaction).
  defp assert_one_order(locks, expected_present) do
    first = Enum.uniq(locks)

    for lock <- expected_present,
        do: assert(lock in first, "expected the #{lock} lock among #{inspect(first)}")

    ranks = Enum.map(first, &Map.fetch!(@rank, &1))
    assert ranks == Enum.sort(ranks), "locks first taken out of order: #{inspect(first)}"
  end

  defp locks_taken(c, operation) do
    handler = "activation-lock-order-#{System.unique_integer([:positive])}"

    keys = %{
      key(ScopedSettings, c.org, ActivationPolicy.section_id()) => :policy,
      key(ConfigurationLock, c.org, c.mission.mission_id) => :configuration
    }

    config = %{pid: self(), keys: keys, mission_id: c.mission.mission_id}

    :ok =
      :telemetry.attach(handler, [:cadence, :repo, :query], &__MODULE__.capture_lock/4, config)

    try do
      result = operation.()
      {result, drain([])}
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def capture_lock(_event, _measurements, %{query: query, params: params}, config) do
    if self() == config.pid and query =~ "pg_advisory_xact_lock" do
      case lock_kind(query, params, config) do
        nil -> :ok
        kind -> send(config.pid, {:activation_lock, kind})
      end
    end
  end

  def capture_lock(_event, _measurements, _metadata, _config), do: :ok

  defp lock_kind(query, [mission_id], %{mission_id: mission_id}) when is_binary(mission_id) do
    if query =~ "hashtext", do: :generation
  end

  defp lock_kind(_query, [key], %{keys: keys}) when is_integer(key), do: Map.get(keys, key)
  defp lock_kind(_query, _params, _config), do: nil

  defp drain(acc) do
    receive do
      {:activation_lock, kind} -> drain([kind | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp key(module, organization_id, id) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({module, organization_id, id}))

    key
  end

  defp set_policy(scope, mission_id, requirement) do
    policy = ActivationPolicy.load(scope.organization_id, mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, mission_id, policy.token, %{
        "value" => %{"approval_requirement" => requirement}
      })
  end

  defp save(scope, mission, craft, catalog, apids) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => apids
      })

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)
  end

  defp review(scope, mission, craft) do
    token = Drafts.snapshot(mission, craft).token
    Review.request_many(scope, mission.mission_id, %{craft.spacecraft_id => token})
  end
end
