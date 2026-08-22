defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardSummary, Document, Version}
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPresentation

  test "build presents pointer metrics and ordered version rows" do
    summary = summary(latest_version: 3, draft_version: 3, published_version: 2)

    presentation =
      VersionHistoryPresentation.build(summary, [
        version(1, snapshot_kind: :migration, inserted_at: nil),
        version(3, snapshot_kind: :draft_save, inserted_at: ~U[2026-06-26 12:13:14Z]),
        version(2, snapshot_kind: :publish, created_by: "operator")
      ])

    assert presentation.pointers == [
             %{label: "latest", value: "v3"},
             %{label: "draft", value: "v3"},
             %{label: "published", value: "v2"}
           ]

    assert presentation.count == 3
    refute presentation.empty

    assert [
             %{version: 3, saved_at: "2026-06-26 12:13:14 UTC"},
             %{version: 2, snapshot_label: "publish", created_by: "operator"},
             %{version: 1, snapshot_label: "migration", saved_at: "-"}
           ] = presentation.versions
  end

  test "build explains version lineage from snapshot metadata" do
    summary = summary(latest_version: 4, draft_version: 4, published_version: 2)

    presentation =
      VersionHistoryPresentation.build(summary, [
        version(4, snapshot_kind: :revert, based_on_version: 2),
        version(3, snapshot_kind: :draft_save, based_on_version: 2),
        version(2, snapshot_kind: :publish),
        version(1, snapshot_kind: :migration, based_on_version: 1)
      ])

    assert [
             %{
               version: 4,
               lineage: %{
                 kind: "revert",
                 label: "Restored from v2",
                 source_version: 2,
                 source_version_text: "2"
               }
             },
             %{
               version: 3,
               lineage: %{
                 kind: "draft_save",
                 label: "Draft saved from v2",
                 source_version: 2,
                 source_version_text: "2"
               }
             },
             %{
               version: 2,
               lineage: %{
                 kind: "publish",
                 label: "Published for operators",
                 source_version: nil,
                 source_version_text: nil
               }
             },
             %{
               version: 1,
               lineage: %{
                 kind: "migration",
                 label: "Migrated from v1",
                 source_version: 1,
                 source_version_text: "1"
               }
             }
           ] = presentation.versions
  end

  test "build presents published and draft runtime defaults" do
    summary = summary(latest_version: 2, draft_version: 2, published_version: 1)

    presentation =
      VersionHistoryPresentation.build(summary, [
        version(1,
          document:
            document(1, %{
              "data" => %{
                "realm" => "flight",
                "view" => "canonical",
                "source_contexts" => %{
                  "telemetry" => %{
                    "data_source_id" => "questdb-flight",
                    "source_binding_id" => "flight-binding"
                  }
                }
              }
            })
        ),
        version(2,
          document:
            document(2, %{
              data: %{
                realm: "rehearsal",
                view: "as_recorded",
                source_contexts: %{
                  telemetry: %{
                    data_source_id: "questdb-rehearsal",
                    source_binding_id: "rehearsal-binding"
                  }
                }
              }
            })
        )
      ])

    assert presentation.runtime_defaults.present?
    assert presentation.runtime_defaults.differ?
    assert presentation.runtime_defaults.differ_text == "true"
    assert presentation.runtime_defaults.status_label == "draft differs"

    assert presentation.runtime_defaults.published == %{
             present?: true,
             version: 1,
             version_text: "v1",
             realm: "flight",
             source_binding_id: "flight-binding",
             source_binding_text: "flight-binding",
             source_binding_attr: "flight-binding",
             data_source_id: "questdb-flight",
             data_source_text: "questdb-flight",
             data_source_attr: "questdb-flight",
             data_view: "canonical"
           }

    assert presentation.runtime_defaults.draft == %{
             present?: true,
             version: 2,
             version_text: "v2",
             realm: "rehearsal",
             source_binding_id: "rehearsal-binding",
             source_binding_text: "rehearsal-binding",
             source_binding_attr: "rehearsal-binding",
             data_source_id: "questdb-rehearsal",
             data_source_text: "questdb-rehearsal",
             data_source_attr: "questdb-rehearsal",
             data_view: "as_recorded"
           }

    assert presentation.runtime_defaults.publish_impact.state == "runtime_context_change"
    assert presentation.runtime_defaults.publish_impact.severity == "warning"
    assert presentation.runtime_defaults.publish_impact.label == "runtime defaults change"

    assert presentation.runtime_defaults.publish_impact.message ==
             "Publishing will move operators from flight / flight-binding / canonical to rehearsal / rehearsal-binding / as_recorded."
  end

  test "build presents publish impact for aligned and initial runtime defaults" do
    aligned_summary = summary(latest_version: 2, draft_version: 2, published_version: 1)
    defaults = runtime_defaults("flight", "canonical", "questdb-flight", "flight-binding")

    aligned =
      VersionHistoryPresentation.build(aligned_summary, [
        version(1, document: document(1, defaults)),
        version(2, document: document(2, defaults))
      ])

    assert aligned.runtime_defaults.publish_impact == %{
             present?: true,
             state: "no_runtime_context_change",
             severity: "success",
             label: "runtime defaults unchanged",
             message: "Publishing keeps operators on flight / flight-binding / canonical.",
             from: aligned.runtime_defaults.published,
             to: aligned.runtime_defaults.draft
           }

    initial_summary = summary(latest_version: 1, draft_version: 1, published_version: nil)

    initial =
      VersionHistoryPresentation.build(initial_summary, [
        version(1, document: document(1, defaults))
      ])

    assert initial.runtime_defaults.publish_impact.state == "initial_publish"
    assert initial.runtime_defaults.publish_impact.severity == "info"

    assert initial.runtime_defaults.publish_impact.message ==
             "Publishing will make flight / flight-binding / canonical operator-facing."
  end

  test "build presents pointer labels and action states per version" do
    summary = summary(latest_version: 3, draft_version: 3, published_version: 2)

    assert [row] = VersionHistoryPresentation.build(summary, [version(2)]).versions

    assert row.pointer_labels == [
             %{label: "published", badge_class: "badge-primary"}
           ]

    assert row.publish_button_id == "publish-version-2"
    assert row.restore_button_id == "restore-version-2"
    assert row.publish_confirm == "Publish version 2 for operators?"
    assert row.restore_confirm == "Restore version 2 as the latest draft?"

    assert row.publish_action == %{
             available: false,
             available_text: "false",
             reason_text: "already_published"
           }

    assert row.restore_action == %{
             available: true,
             available_text: "true",
             reason_text: "available"
           }
  end

  test "build marks latest draft version as latest and draft" do
    summary = summary(latest_version: 3, draft_version: 3, published_version: 2)

    assert [row] = VersionHistoryPresentation.build(summary, [version(3)]).versions

    assert row.pointer_labels == [
             %{label: "latest", badge_class: "badge-ghost"},
             %{label: "draft", badge_class: "badge-warning"}
           ]

    assert row.restore_action == %{
             available: false,
             available_text: "false",
             reason_text: "already_latest"
           }
  end

  test "build handles empty or missing versions" do
    presentation = VersionHistoryPresentation.build(nil, nil)

    assert presentation.pointers == [
             %{label: "latest", value: "-"},
             %{label: "draft", value: "-"},
             %{label: "published", value: "-"}
           ]

    assert presentation.count == 0
    assert presentation.empty
    assert presentation.versions == []
  end

  defp summary(attrs) do
    struct!(
      DashboardSummary,
      Keyword.merge(
        [
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Ops",
          latest_version: 1,
          draft_version: 1,
          published_version: nil,
          lifecycle_state: "active"
        ],
        attrs
      )
    )
  end

  defp version(number, attrs \\ []) do
    struct!(
      Version,
      Keyword.merge(
        [
          dashboard_version_id: "version-#{number}",
          organization_id: "org-1",
          mission_id: "mission-1",
          dashboard_id: "dashboard-1",
          version: number,
          created_by: nil,
          parent_version: nil,
          based_on_version: nil,
          change_summary: nil,
          inserted_at: nil
        ],
        attrs
      )
    )
  end

  defp document(version, defaults) do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard",
      defaults: defaults,
      metadata: %{version: version}
    }
  end

  defp runtime_defaults(realm, data_view, data_source_id, source_binding_id) do
    %{
      "data" => %{
        "realm" => realm,
        "view" => data_view,
        "source_contexts" => %{
          "telemetry" => %{
            "data_source_id" => data_source_id,
            "source_binding_id" => source_binding_id
          }
        }
      }
    }
  end
end
