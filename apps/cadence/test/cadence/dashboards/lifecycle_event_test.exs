defmodule Cadence.Dashboards.LifecycleEventTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.LifecycleEvent

  test "normalizes detail snapshots from payload and top-level columns" do
    event =
      LifecycleEvent.new(%{
        mission_id: "mission-audit",
        dashboard_id: "dashboard-audit",
        event_type: :published,
        dashboard_version: 2,
        previous_lifecycle_state: "active",
        current_lifecycle_state: "active",
        previous_published_version: nil,
        current_published_version: 2,
        payload: %{
          "dashboard_name" => "Power",
          "previous" => %{"latest_version" => 2, "draft_version" => 2},
          "current" => %{
            "latest_version" => 2,
            "draft_version" => nil,
            "published_version" => 2
          }
        }
      })

    assert %{
             event_type: :published,
             dashboard_name: "Power",
             previous: %{
               lifecycle_state: "active",
               latest_version: 2,
               draft_version: 2,
               published_version: nil
             },
             current: %{
               lifecycle_state: "active",
               latest_version: 2,
               draft_version: nil,
               published_version: 2
             },
             source_version: nil,
             reverted_version: nil
           } = LifecycleEvent.details(event)
  end

  test "normalizes revert detail versions from atom or string payload keys" do
    event =
      LifecycleEvent.new(%{
        mission_id: "mission-audit",
        dashboard_id: "dashboard-audit",
        event_type: :reverted,
        dashboard_version: 3,
        previous_lifecycle_state: "active",
        current_lifecycle_state: "active",
        previous_published_version: 2,
        current_published_version: 2,
        payload: %{
          :source_version => "1",
          "reverted_version" => 3,
          :previous => %{published_version: 2},
          "current" => %{"published_version" => 2}
        }
      })

    assert %{
             source_version: 1,
             reverted_version: 3,
             previous: %{published_version: 2},
             current: %{published_version: 2}
           } = LifecycleEvent.details(event)

    assert LifecycleEvent.source_version(event) == 1
    assert LifecycleEvent.reverted_version(event) == 3
  end

  test "falls back to top-level transition columns when payload is missing" do
    event =
      LifecycleEvent.new(%{
        mission_id: "mission-audit",
        dashboard_id: "dashboard-audit",
        event_type: :archived,
        dashboard_version: 1,
        previous_lifecycle_state: "active",
        current_lifecycle_state: "archived",
        previous_published_version: 1,
        current_published_version: 1
      })

    assert %{
             previous: %{lifecycle_state: "active", published_version: 1},
             current: %{lifecycle_state: "archived", published_version: 1}
           } = LifecycleEvent.details(event)
  end
end
