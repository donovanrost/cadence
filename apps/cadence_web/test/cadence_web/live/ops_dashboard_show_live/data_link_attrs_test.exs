defmodule CadenceWeb.OpsDashboardShowLive.DataLinkAttrsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs

  test "open carries link identity and nested source and time context" do
    assert %{
             "phx-value-link-id" => "link-1",
             "phx-value-target" => "telemetry_sample",
             "phx-value-target-id" => "sample-1",
             "phx-value-placement-id" => "placement-1",
             "phx-value-realm" => "flight",
             "phx-value-data-view" => "canonical",
             "phx-value-data-source-id" => "questdb-flight",
             "phx-value-source-binding-id" => "binding-flight",
             "phx-value-time-mode" => "archive",
             "phx-value-time-axis" => "receipt_time",
             "phx-value-replay-run-id" => "replay-run-1"
           } =
             DataLinkAttrs.open(link(), placement_id: "placement-1")
  end

  test "open uses fallback context only when the link omits the value" do
    attrs =
      DataLinkAttrs.open(
        %{
          link_id: "link-1",
          target_text: "telemetry_sample",
          target_id: "sample-1",
          context: %{
            data: %{realm: :simulation, view: "all_revisions"},
            time: %{mode: :replay_run}
          }
        },
        context_fallback: %{
          realm: "flight",
          data_view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          time_mode: "wall_clock",
          time_axis: "receipt_time",
          replay_run_id: "replay-run-1"
        }
      )

    assert attrs["phx-value-realm"] == "simulation"
    assert attrs["phx-value-data-view"] == "all_revisions"
    assert attrs["phx-value-time-mode"] == "replay_run"
    assert attrs["phx-value-data-source-id"] == "questdb-flight"
    assert attrs["phx-value-source-binding-id"] == "binding-flight"
    assert attrs["phx-value-time-axis"] == "receipt_time"
    assert attrs["phx-value-replay-run-id"] == "replay-run-1"
  end

  test "open lets explicit attrs override source identity while preserving source context" do
    attrs =
      DataLinkAttrs.open(
        link(),
        link_id: "comparison-decision:decision-1",
        target: "telemetry_revision_decision_event",
        target_id: "decision-1",
        data_view: "all_revisions",
        primary_data_management: "recomputed_analysis",
        compare_data_management: "degraded"
      )

    assert attrs["phx-value-link-id"] == "comparison-decision:decision-1"
    assert attrs["phx-value-target"] == "telemetry_revision_decision_event"
    assert attrs["phx-value-target-id"] == "decision-1"
    assert attrs["phx-value-data-view"] == "all_revisions"
    assert attrs["phx-value-primary-data-management"] == "recomputed_analysis"
    assert attrs["phx-value-compare-data-management"] == "degraded"
    assert attrs["phx-value-realm"] == "flight"
    assert attrs["phx-value-data-source-id"] == "questdb-flight"
    assert attrs["phx-value-time-axis"] == "receipt_time"
  end

  test "open derives event scope attrs from primary scope context" do
    attrs =
      DataLinkAttrs.open(%{
        link_id: "transport:transport-beta",
        target: :transport,
        target_id: "transport-beta",
        context: %{
          scope: %{
            contact_ids: ["contact-alpha", "contact-beta"],
            primary: %{
              kind: "transport",
              mode: "many",
              ids: ["transport-alpha", "transport-beta"]
            }
          }
        }
      })

    assert attrs["phx-value-scope-kind"] == "transport"
    assert attrs["phx-value-scope-id"] == "transport-alpha"
    assert attrs["phx-value-scope-ids"] == "transport-alpha,transport-beta"
    assert attrs["phx-value-contact-ids"] == "contact-alpha,contact-beta"
  end

  test "open derives contact ids from primary contact scope context" do
    attrs =
      DataLinkAttrs.open(%{
        link_id: "contact:contact-beta",
        target: :contact,
        target_id: "contact-beta",
        context: %{
          scope: %{
            primary: %{
              kind: "contact",
              mode: "many",
              ids: ["contact-alpha", "contact-beta"]
            }
          }
        }
      })

    assert attrs["phx-value-scope-kind"] == "contact"
    assert attrs["phx-value-scope-id"] == "contact-alpha"
    assert attrs["phx-value-scope-ids"] == "contact-alpha,contact-beta"
    assert attrs["phx-value-contact-ids"] == "contact-alpha,contact-beta"
  end

  test "open carries navigation breadcrumb attrs" do
    attrs =
      DataLinkAttrs.open(
        link(),
        nav_from_link_id: "source-link-1",
        nav_from_target: :telemetry_backfill_lifecycle_event,
        nav_from_target_id: "source-event-1",
        nav_from_label: "Source event",
        nav_from_relationship_kind: :retry_event,
        nav_from_relationship_label: "Retry event HK.counter",
        nav_trail:
          Jason.encode!([
            %{"target" => "telemetry_backfill_lifecycle_event", "target_id" => "source-event-1"}
          ])
      )

    assert attrs["phx-value-nav-from-link-id"] == "source-link-1"
    assert attrs["phx-value-nav-from-target"] == "telemetry_backfill_lifecycle_event"
    assert attrs["phx-value-nav-from-target-id"] == "source-event-1"
    assert attrs["phx-value-nav-from-label"] == "Source event"
    assert attrs["phx-value-nav-from-relationship-kind"] == "retry_event"
    assert attrs["phx-value-nav-from-relationship-label"] == "Retry event HK.counter"

    assert [%{"target_id" => "source-event-1"}] =
             Jason.decode!(attrs["phx-value-nav-trail"])
  end

  defp link do
    %{
      link_id: "link-1",
      target: :telemetry_sample,
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          replay_run_id: "replay-run-1"
        },
        time: %{mode: "archive", axis: "receipt_time"}
      }
    }
  end
end
