defmodule Cadence.Limits.ReviewedDefinitionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Limits
  alias Cadence.Limits.{Definition, DefinitionLifecycle, Facts}
  alias Cadence.Platform.EventBus
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @org "org-reviewed-limits"
  @mission "mission-reviewed-limits"
  @empty_review %{definition_id: nil, version: 0, activation_event_id: nil}

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "a reviewed append atomically creates and activates a version with durable evidence" do
    event_bus = event_bus()
    assert :ok = Facts.subscribe(event_bus, self())
    assert review() == @empty_review

    assert {:ok, first} =
             Limits.append_limit_definition(@org, @mission, attrs(), review(),
               event_bus: event_bus
             )

    assert first.version == 1
    assert_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, first_event}}
    assert first_event.limit_definition_id == first.limit_definition_id
    assert first_event.limit_definition_version == 1

    current = review()
    assert current.definition_id == first.limit_definition_id
    assert current.version == 1
    assert current.activation_event_id == first_event.limit_definition_lifecycle_event_id

    assert {:ok, second} =
             Limits.append_limit_definition(@org, @mission, attrs(25), current,
               event_bus: event_bus
             )

    assert second.version == 2
    assert second.limit_definition_id == first.limit_definition_id
    assert_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, second_event}}
    assert second_event.previous_limit_definition_version == 1
    assert second_event.limit_definition_version == 2

    assert [active] = DefinitionLifecycle.list_active_statuses(@org, @mission)
    assert active.limit_definition_version == 2
    assert active.transition_count == 2
    assert active.limit_definition_lifecycle_event_id == review().activation_event_id

    assert [operational] =
             Cadence.OperationalEvents.list_events(@org, @mission,
               source_record_kind: :limit_definition_lifecycle_event,
               source_record_id: second_event.limit_definition_lifecycle_event_id
             )

    assert operational.current["limit_definition_version"] == 2

    assert %{total_count: 2, items: [^second, ^first]} =
             Limits.limit_definition_history(@org, @mission, first.limit_definition_id, 1)
  end

  test "missing, stale and cross-organization reviews cannot append or activate" do
    assert {:error, :limit_definition_review_required} =
             Limits.append_limit_definition(@org, @mission, attrs(), %{})

    assert {:ok, first} =
             Limits.append_limit_definition(@org, @mission, attrs(), review(),
               publish_facts?: false
             )

    current = review()

    for invalid <- [
          @empty_review,
          %{current | definition_id: "another-definition"},
          %{current | activation_event_id: "another-activation"}
        ] do
      assert {:error, :limit_definition_review_conflict} =
               Limits.append_limit_definition(@org, @mission, attrs(99), invalid,
                 publish_facts?: false
               )
    end

    assert {:error, :mission_not_found} =
             Limits.append_limit_definition("another-organization", @mission, attrs(), current)

    assert {:error, :mission_not_found} =
             Limits.append_limit_definition(@org, "missing-mission", attrs(), @empty_review)

    assert %{total_count: 0, items: []} =
             Limits.limit_definitions_page("another-organization", @mission)

    assert %{total_count: 0, items: []} =
             Limits.limit_definition_history(
               "another-organization",
               @mission,
               first.limit_definition_id,
               1
             )

    assert %{total_count: 1, items: [^first]} = Limits.limit_definitions_page(@org, @mission)
    assert review() == current
  end

  test "reactivating an older version invalidates review even though the newest version is unchanged" do
    assert {:ok, first} =
             Limits.append_limit_definition(@org, @mission, attrs(), review(),
               publish_facts?: false
             )

    assert {:ok, second} =
             Limits.append_limit_definition(@org, @mission, attrs(25), review(),
               publish_facts?: false
             )

    reviewed = review()
    assert {:ok, ^first} = Limits.persist_limit_definition(first, publish_facts?: false)
    assert review().version == reviewed.version
    assert review().definition_id == reviewed.definition_id
    refute review().activation_event_id == reviewed.activation_event_id

    assert {:error, :limit_definition_review_conflict} =
             Limits.append_limit_definition(@org, @mission, attrs(30), reviewed,
               publish_facts?: false
             )

    assert %{total_count: 2, items: [^second, ^first]} =
             Limits.limit_definition_history(@org, @mission, first.limit_definition_id, 1)

    assert [active] = DefinitionLifecycle.list_active_statuses(@org, @mission)
    assert active.limit_definition_version == 1
    assert active.transition_count == 3
  end

  test "conflicting immutable bytes never alter an active pointer or publish an invented definition" do
    event_bus = event_bus()
    assert :ok = Facts.subscribe(event_bus, self())

    proposed =
      Definition.new(Map.merge(attrs(), %{mission_id: @mission, metadata: %{origin: "operator"}}))

    assert {:ok, stored} = Limits.persist_limit_definition(proposed, event_bus: event_bus)
    assert stored.metadata == %{"origin" => "operator"}
    assert_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}
    evidence = review()
    assert {:ok, ^stored} = Limits.persist_limit_definition(proposed, event_bus: event_bus)

    assert {:error, :limit_definition_version_conflict} =
             Limits.persist_limit_definition(%{proposed | thresholds: %{"yellow_high" => 999}},
               event_bus: event_bus
             )

    assert {:error, :limit_definition_version_conflict} =
             Limits.persist_limit_definition(%{proposed | point_id: "HK.other"},
               event_bus: event_bus
             )

    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}
    assert review() == evidence
    assert %{total_count: 1, items: [^stored]} = Limits.limit_definitions_page(@org, @mission)
    assert [_] = DefinitionLifecycle.list_definition_lifecycle_events(@org, @mission)
  end

  test "activation validation failure rolls back definition, lifecycle, projection and publication" do
    event_bus = event_bus()
    assert :ok = Facts.subscribe(event_bus, self())

    assert {:error, %Ecto.Changeset{}} =
             Limits.append_limit_definition(@org, @mission, attrs(), review(),
               observed_at: nil,
               event_bus: event_bus
             )

    assert review() == @empty_review
    assert %{total_count: 0, items: []} = Limits.limit_definitions_page(@org, @mission)
    assert DefinitionLifecycle.list_definition_lifecycle_events(@org, @mission) == []
    assert DefinitionLifecycle.list_active_statuses(@org, @mission) == []
    assert Cadence.OperationalEvents.list_events(@org, @mission, category: :limits) == []
    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}

    proposed = Definition.new(Map.put(attrs(), :mission_id, @mission))

    assert {:error, %Ecto.Changeset{}} =
             Limits.persist_limit_definition(proposed, observed_at: nil, event_bus: event_bus)

    assert %{total_count: 0, items: []} = Limits.limit_definitions_page(@org, @mission)
    assert DefinitionLifecycle.list_active_statuses(@org, @mission) == []
    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}

    assert {:ok, first} =
             Limits.append_limit_definition(@org, @mission, attrs(), review(),
               event_bus: event_bus
             )

    assert first.version == 1
    assert_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}
    evidence = review()

    assert {:error, %Ecto.Changeset{}} =
             Limits.append_limit_definition(@org, @mission, attrs(25), evidence,
               observed_at: nil,
               event_bus: event_bus
             )

    assert review() == evidence

    assert %{total_count: 1, items: [^first]} =
             Limits.limit_definition_history(@org, @mission, first.limit_definition_id, 1)

    assert [_] = DefinitionLifecycle.list_definition_lifecycle_events(@org, @mission)
    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _}}
  end

  test "definition and version pages retain full counts and exact immutable history" do
    for index <- 1..27 do
      definition =
        Definition.new(
          Map.merge(attrs(), %{
            mission_id: @mission,
            point_id: "HK.#{String.pad_leading(to_string(index), 2, "0")}",
            limit_definition_id: "limits-#{index}"
          })
        )

      assert {:ok, _} = Limits.persist_limit_definition(definition, publish_facts?: false)
    end

    assert %{total_count: 27, page: 1, items: first_page} =
             Limits.limit_definitions_page(@org, @mission)

    assert length(first_page) == 25

    assert %{total_count: 27, page: 2, items: [a, b]} =
             Limits.limit_definitions_page(@org, @mission, page: 999)

    assert [a.point_id, b.point_id] == ["HK.26", "HK.27"]

    assert %{total_count: 1, items: [^a]} =
             Limits.limit_definitions_page(@org, @mission, search: "hk.26")

    for version <- 2..27 do
      assert {:ok, _} =
               Limits.persist_limit_definition(%{a | version: version}, publish_facts?: false)
    end

    assert %{total_count: 27, items: versions} =
             Limits.limit_definition_history(@org, @mission, a.limit_definition_id, 1)

    assert Enum.map(versions, & &1.version) == Enum.to_list(27..3//-1)

    assert %{total_count: 27, page: 2, items: [v2, ^a]} =
             Limits.limit_definition_history(@org, @mission, a.limit_definition_id, 2)

    assert v2.version == 2

    assert %{total_count: 1, items: [latest]} =
             Limits.limit_definitions_page(@org, @mission, search: "HK.26")

    assert latest.version == 27
  end

  test "independent first saves serialize and only the winner creates activation evidence" do
    suffix = System.unique_integer([:positive])
    org = "limits-race-org-#{suffix}"
    mission = "limits-race-mission-#{suffix}"

    independent(fn ->
      persist_mission_scope(org, mission)

      try do
        race(org, mission)
      after
        for table <- [
              "active_limit_definitions",
              "operational_events",
              "limit_definition_lifecycle_events",
              "governed_limit_definitions"
            ] do
          SQL.query!(
            Repo,
            "DELETE FROM #{table} WHERE organization_id = $1 AND mission_id = $2",
            [org, mission]
          )
        end

        SQL.query!(Repo, "DELETE FROM missions WHERE organization_id = $1 AND mission_id = $2", [
          org,
          mission
        ])

        SQL.query!(Repo, "DELETE FROM organizations WHERE organization_id = $1", [org])
      end
    end)
    |> Task.await(15_000)
  end

  defp race(org, mission) do
    parent = self()

    first =
      independent(fn ->
        Repo.transaction(fn ->
          result =
            Limits.append_limit_definition(org, mission, attrs(), @empty_review,
              publish_facts?: false
            )

          send(parent, {:first_saved, self(), result})

          receive do
            :release -> result
          after
            5_000 -> raise "first save was not released"
          end
        end)
      end)

    assert_receive {:first_saved, owner, {:ok, winner}}, 2_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:second_backend, pid})

        Limits.append_limit_definition(org, mission, attrs(99), @empty_review,
          publish_facts?: false
        )
      end)

    try do
      assert_receive {:second_backend, pid}, 2_000
      assert wait_for_lock(pid, 100)
      send(owner, :release)
      assert {:ok, {:ok, ^winner}} = Task.await(first)
      assert {:error, :limit_definition_review_conflict} = Task.await(second)
      assert %{total_count: 1, items: [^winner]} = Limits.limit_definitions_page(org, mission)
      assert [active] = DefinitionLifecycle.list_active_statuses(org, mission)
      assert active.transition_count == 1
      assert active.limit_definition_id == winner.limit_definition_id
      assert [event] = DefinitionLifecycle.list_definition_lifecycle_events(org, mission)

      assert event.limit_definition_lifecycle_event_id ==
               active.limit_definition_lifecycle_event_id

      assert [operational] =
               Cadence.OperationalEvents.list_events(org, mission, category: :limits)

      assert operational.causality.source_record_id == event.limit_definition_lifecycle_event_id
    after
      send(owner, :release)
      Task.shutdown(first)
      Task.shutdown(second)
    end
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_for_lock(_pid, 0), do: false

  defp wait_for_lock(pid, attempts) do
    %{rows: [[waiting]]} =
      SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)",
        [pid]
      )

    if waiting do
      true
    else
      Process.sleep(10)
      wait_for_lock(pid, attempts - 1)
    end
  end

  defp attrs(threshold \\ 20),
    do: %{
      point_id: "HK.bus_voltage",
      limit_set_name: "FLIGHT",
      thresholds: %{"yellow_high" => threshold}
    }

  defp review, do: Limits.limit_definition_review(@org, @mission, "HK.bus_voltage", "FLIGHT")

  defp event_bus do
    start_supervised!(%{
      id: {:limit_fact_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end
end
