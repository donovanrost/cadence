defmodule CadenceWeb.OpsDashboardShowLive.DataLinkPresentationNavigationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation

  test "navigation event attrs append the current inspector to the bounded trail" do
    inspector = %{
      title: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "source-event-1",
      link_id: "source-link-1",
      source_context: %{
        realm: "flight",
        data_view: "canonical",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        time_mode: "archive",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      },
      navigation: %{
        trail: [
          %{
            target: "telemetry_backfill_lifecycle_event",
            target_id: "root-event-1",
            relationship_kind: "source_event",
            realm: "flight",
            data_view: "canonical",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            time_mode: "archive",
            time_axis: "receipt_time",
            replay_run_id: "replay-1"
          }
        ]
      }
    }

    related_link =
      link(
        :telemetry_backfill_lifecycle_event,
        "retry-event-1",
        "Retry event HK.counter",
        :retry_event
      )

    attrs = DataLinkPresentation.navigation_event_attrs(inspector, related_link)

    assert attrs.nav_from_link_id == "source-link-1"
    assert attrs.nav_from_target == "telemetry_backfill_lifecycle_event"
    assert attrs.nav_from_target_id == "source-event-1"
    assert attrs.nav_from_relationship_kind == "retry_event"

    assert [
             %{"target_id" => "root-event-1"},
             %{
               "target_id" => "source-event-1",
               "relationship_kind" => "retry_event",
               "relationship_label" => "Retry event HK.counter",
               "realm" => "flight",
               "data_view" => "canonical",
               "data_source_id" => "questdb-flight",
               "source_binding_id" => "binding-flight",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1"
             }
           ] = Jason.decode!(attrs.nav_trail)
  end

  test "navigation event attrs fall back to related link context for trail entries" do
    inspector = %{
      title: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "source-event-1",
      link_id: "source-link-1"
    }

    related_link = %DataLink{
      link_id: "telemetry_backfill_lifecycle_event:retry-event-1:request-1",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "retry-event-1",
      label: "Retry event HK.counter",
      relationship_kind: :retry_event,
      context: %{
        data: %{
          realm: "backfill",
          view: "canonical",
          data_source_id: "managed_questdb_backfill",
          source_binding_id: "backfill_telemetry"
        },
        time: %{mode: "live", axis: "generation_time"}
      }
    }

    attrs = DataLinkPresentation.navigation_event_attrs(inspector, related_link)

    assert [
             %{
               "target_id" => "source-event-1",
               "realm" => "backfill",
               "data_view" => "canonical",
               "data_source_id" => "managed_questdb_backfill",
               "source_binding_id" => "backfill_telemetry",
               "time_mode" => "live",
               "time_axis" => "generation_time"
             }
           ] = Jason.decode!(attrs.nav_trail)
  end

  defp link(target, target_id, label, relationship_kind) do
    %DataLink{
      link_id: "#{target}:#{target_id}:request-1",
      target: target,
      target_id: target_id,
      label: label,
      relationship_kind: relationship_kind
    }
  end
end
