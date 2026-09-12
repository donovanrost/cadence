defmodule Cadence.Reads.OpsWorkspace.TimelineTest do
  use Cadence.DataCase, async: false
  alias Cadence.Auth.Scope
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.{Event, EventRow}
  alias Cadence.Projections.MissionEvents, as: Projection
  alias Cadence.Reads.MissionTimeline
  alias Cadence.Reads.OpsWorkspace.Timeline
  @org "org-workspace-timeline"
  @mission "mission-workspace-timeline"
  @probe Path.expand(
           "../../../../../../frontend/apps/host/src/ops-workspace/features/timeline/producer-consumer-probe.mjs",
           __DIR__
         )

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      user: %{user_id: "timeline-operator"},
      organization_id: @org,
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope}
  end

  test "time and category filters apply to persisted facts while selected evidence is independently scoped",
       c do
    persist("older", ~U[2026-09-01 00:00:00Z])
    persist("selected", ~U[2026-09-02 00:00:00Z])
    persist("newer", ~U[2026-09-03 00:00:00Z])
    {:ok, selected} = MissionTimeline.fetch_for_mission(@org, @mission, "mission_event:selected")

    assert {:ok, 1} =
             Projection.persist_entries(Repo, [
               %{
                 selected
                 | title: "Canonical source evidence",
                   metadata: %{"secret" => "not a UI field"}
               }
             ])

    params = %{
      "category" => "health",
      "from" => "2026-09-03T00:00:00Z",
      "to" => "2026-09-04T00:00:00Z",
      "event_id" => selected.mission_event_id
    }

    assert {:ok, doc} = Timeline.load(c.scope, @mission, params)
    assert Enum.map(doc["events"], & &1["id"]) == ["mission_event:newer"]
    assert doc["selected_status"] == "ready"
    assert doc["selected"]["id"] == selected.mission_event_id
    assert doc["selected"]["title"] == "Canonical source evidence"
    assert doc["selected"]["source"] == %{"kind" => "operational_event", "id" => "selected"}
    refute Map.has_key?(doc["selected"], "metadata")
    refute Map.has_key?(doc["selected"], "actor")
    assert {:ok, exclusive} = Timeline.load(c.scope, @mission, %{"to" => "2026-09-02T00:00:00Z"})
    assert Enum.map(exclusive["events"], & &1["id"]) == ["mission_event:older"]
    {output, status} = System.cmd("node", [@probe, Jason.encode!(doc)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "TIMELINE_CONSUMER_OK"
  end

  test "bounded recent rows have deterministic ordering and selected evidence can be older than the window",
       c do
    at = ~U[2026-09-01 00:00:00.000000Z]

    rows =
      for i <- 1..105 do
        event("bounded-#{String.pad_leading(to_string(i), 3, "0")}", DateTime.add(at, i))
        |> EventRow.insert_attrs(at)
      end

    assert {105, nil} = Repo.insert_all(EventRow, rows)

    assert {:ok, doc} =
             Timeline.load(c.scope, @mission, %{"event_id" => "mission_event:bounded-001"})

    assert length(doc["events"]) == 100
    assert hd(doc["events"])["id"] == "mission_event:bounded-105"
    assert List.last(doc["events"])["id"] == "mission_event:bounded-006"
    assert doc["selected"]["id"] == "mission_event:bounded-001"
    assert doc["limit"] == 100
    refute Map.has_key?(doc, "total_count")

    assert {:ok, older} =
             Timeline.load(c.scope, @mission, %{
               "before_at" => doc["next_cursor"]["at"],
               "before_id" => doc["next_cursor"]["id"]
             })

    assert Enum.map(older["events"], & &1["id"]) ==
             Enum.map(
               5..1//-1,
               &"mission_event:bounded-#{String.pad_leading(to_string(&1), 3, "0")}"
             )

    assert older["next_cursor"] == nil
  end

  test "invalid filters remain editable and never silently become unfiltered reads", c do
    persist("visible", ~U[2026-09-01 00:00:00Z])

    for query <- [
          %{"from" => "invalid"},
          %{"from" => "2026-09-02T00:00:00Z", "to" => "2026-09-01T00:00:00Z"},
          %{"category" => "invalid"},
          %{"severity" => "invalid"},
          %{"kind" => "<script>"}
        ] do
      assert {:ok, doc} = Timeline.load(c.scope, @mission, query)
      assert doc["errors"] != []
      assert doc["events"] == []
      for {key, value} <- query, do: assert(doc["query"][key] == value)
    end

    for query <- [
          %{"from" => %{}},
          %{"unknown" => "value"},
          %{"kind" => String.duplicate("a", 513)}
        ] do
      assert {:error, _} = Timeline.load(c.scope, @mission, query)
    end
  end

  test "foreign identities and unauthorized refresh scopes cannot disclose events", c do
    persist_mission_scope("foreign-timeline-org", "foreign-timeline-mission")

    assert {:ok, _} =
             OperationalEvents.persist_event(%{
               event("foreign", ~U[2026-09-01 00:00:00Z])
               | organization_id: "foreign-timeline-org",
                 mission_id: "foreign-timeline-mission"
             })

    assert {:ok, doc} = Timeline.load(c.scope, @mission, %{"event_id" => "mission_event:foreign"})
    assert doc["events"] == []
    assert doc["selected_status"] == "unavailable"
    assert doc["selected"] == nil

    for scope <- [
          nil,
          %Scope{},
          %{c.scope | user: nil},
          %{c.scope | actor_kind: :service},
          %{c.scope | mission_id: "foreign-timeline-mission"},
          %{c.scope | organization_membership: %{lifecycle_state: :revoked}}
        ] do
      assert {:error, _} = Timeline.load(scope, @mission, %{})
    end

    assert {:error, _} = Timeline.load(c.scope, "foreign-timeline-mission", %{})
  end

  defp persist(id, at) do
    assert {:ok, _} = OperationalEvents.persist_event(event(id, at))
  end

  defp event(id, at) do
    Event.new(%{
      event_id: id,
      organization_id: @org,
      mission_id: @mission,
      occurred_at: at,
      category: :data_source,
      kind: :source_health_degraded,
      severity: :warning,
      subject: %{kind: :data_source, id: "flight-telemetry"},
      scope: %{spacecraft_id: "craft-1", data_source_id: "flight-telemetry"},
      current: %{status: "degraded"}
    })
  end
end
