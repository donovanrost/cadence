defmodule CadenceWeb.OpsDashboardShowLive.DocumentLifecycleTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardLifecycleStatus, Document, Version}
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle

  test "formats lifecycle status for dashboard DOM attributes" do
    status = %DashboardLifecycleStatus{
      publication_state: :draft_ahead,
      publishable_version: 3,
      published_current?: false,
      draft_ahead?: true,
      publish_available?: true
    }

    assert DocumentLifecycle.publication_state(status) == "draft_ahead"
    assert DocumentLifecycle.publishable_version(status) == "3"
    assert DocumentLifecycle.lifecycle_flag(status, :published_current?) == "false"
    assert DocumentLifecycle.lifecycle_flag(status, :draft_ahead?) == "true"
    assert DocumentLifecycle.lifecycle_flag(status, :publish_available?) == "true"

    assert DocumentLifecycle.publication_state(nil) == "unknown"
    assert DocumentLifecycle.publishable_version(nil) == nil
    assert DocumentLifecycle.lifecycle_flag(nil, :publish_available?) == "false"
  end

  test "detects runtime default differences between published and draft versions" do
    published_document =
      document(1, %{
        "data" => %{
          "realm" => "flight",
          "source_contexts" => %{}
        }
      })

    draft_document =
      document(2, %{
        "data" => %{
          "realm" => "rehearsal",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "rehearsal-binding"}
          }
        }
      })

    versions = [
      version(1, published_document),
      version(2, draft_document)
    ]

    assert DocumentLifecycle.draft_runtime_defaults_differ?(
             %{published_version: 1, draft_version: 2},
             versions
           )
  end

  test "does not report runtime default differences without distinct published and draft versions" do
    versions = [
      version(1, document(1, %{"data" => %{"realm" => "flight"}}))
    ]

    refute DocumentLifecycle.draft_runtime_defaults_differ?(
             %{published_version: 1, draft_version: 1},
             versions
           )

    refute DocumentLifecycle.draft_runtime_defaults_differ?(
             %{published_version: 1, draft_version: 2},
             versions
           )

    refute DocumentLifecycle.draft_runtime_defaults_differ?(nil, versions)
  end

  test "returns stable lifecycle action messages" do
    assert DocumentLifecycle.version_publish_unavailable_message(:already_published) ==
             "Dashboard version is already published."

    assert DocumentLifecycle.version_publish_unavailable_message(:archived) ==
             "Archived dashboards cannot publish versions."

    assert DocumentLifecycle.version_publish_unavailable_message(:unknown) ==
             "Dashboard version cannot be published."

    assert DocumentLifecycle.version_restore_unavailable_message(:already_latest) ==
             "Dashboard version is already the latest draft."

    assert DocumentLifecycle.version_restore_unavailable_message(:archived) ==
             "Archived dashboards cannot restore versions."

    assert DocumentLifecycle.version_restore_unavailable_message(:unknown) ==
             "Dashboard version cannot be restored."
  end

  defp version(version, %Document{} = document) do
    %Version{version: version, document: document}
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
end
