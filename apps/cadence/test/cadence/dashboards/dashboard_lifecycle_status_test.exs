defmodule Cadence.Dashboards.DashboardLifecycleStatusTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{DashboardLifecycleStatus, DashboardSummary, Version}

  test "reports an unknown state when no summary is available" do
    assert %DashboardLifecycleStatus{
             publication_state: :unknown,
             publish_available?: false,
             archive_available?: false,
             restore_available?: false
           } = Dashboards.dashboard_lifecycle_status(nil)
  end

  test "reports unpublished drafts as publishable" do
    assert %DashboardLifecycleStatus{
             publication_state: :unpublished,
             latest_version: 1,
             draft_version: 1,
             published_version: nil,
             publishable_version: 1,
             published_current?: false,
             draft_ahead?: false,
             publish_available?: true,
             revert_available?: false,
             archive_available?: true,
             restore_available?: false
           } = Dashboards.dashboard_lifecycle_status(summary(latest_version: 1, draft_version: 1))
  end

  test "reports a published dashboard with no draft as current" do
    assert %DashboardLifecycleStatus{
             publication_state: :published_current,
             latest_version: 2,
             draft_version: nil,
             published_version: 2,
             publishable_version: nil,
             published_current?: true,
             draft_ahead?: false,
             publish_available?: false,
             revert_available?: true,
             archive_available?: true,
             restore_available?: false
           } =
             Dashboards.dashboard_lifecycle_status(
               summary(latest_version: 2, draft_version: nil, published_version: 2)
             )
  end

  test "reports a draft ahead of the published version" do
    assert %DashboardLifecycleStatus{
             publication_state: :draft_ahead,
             latest_version: 3,
             draft_version: 3,
             published_version: 2,
             publishable_version: 3,
             published_current?: false,
             draft_ahead?: true,
             publish_available?: true,
             revert_available?: true,
             archive_available?: true,
             restore_available?: false
           } =
             Dashboards.dashboard_lifecycle_status(
               summary(latest_version: 3, draft_version: 3, published_version: 2)
             )
  end

  test "reports archived dashboards as restorable but not publishable" do
    assert %DashboardLifecycleStatus{
             publication_state: :archived,
             lifecycle_state: "archived",
             latest_version: 2,
             draft_version: 2,
             published_version: 1,
             publishable_version: nil,
             published_current?: false,
             draft_ahead?: false,
             publish_available?: false,
             revert_available?: false,
             archive_available?: false,
             restore_available?: true
           } =
             Dashboards.dashboard_lifecycle_status(
               summary(
                 latest_version: 2,
                 draft_version: 2,
                 published_version: 1,
                 lifecycle_state: "archived"
               )
             )
  end

  test "reports historical version actions from lifecycle pointers" do
    summary = summary(latest_version: 3, draft_version: 3, published_version: 2)

    assert %{
             restore_available?: true,
             restore_reason: :available,
             publish_available?: true,
             publish_reason: :available
           } = Dashboards.dashboard_version_action(summary, version(1))

    assert %{
             restore_available?: true,
             restore_reason: :available,
             publish_available?: false,
             publish_reason: :already_published
           } = Dashboards.dashboard_version_action(summary, 2)

    assert %{
             restore_available?: false,
             restore_reason: :already_latest,
             publish_available?: true,
             publish_reason: :available
           } = Dashboards.dashboard_version_action(summary, version(3))
  end

  test "reports archived and unknown version actions as unavailable" do
    archived_summary =
      summary(
        latest_version: 2,
        draft_version: 2,
        published_version: 1,
        lifecycle_state: "archived"
      )

    assert %{
             restore_available?: false,
             restore_reason: :archived,
             publish_available?: false,
             publish_reason: :archived
           } = Dashboards.dashboard_version_action(archived_summary, version(1))

    assert %{
             restore_available?: false,
             restore_reason: :unknown,
             publish_available?: false,
             publish_reason: :unknown
           } = Dashboards.dashboard_version_action(nil, version(1))
  end

  defp summary(attrs) do
    defaults = [
      dashboard_id: "dashboard-lifecycle",
      organization_id: "org-lifecycle",
      mission_id: "mission-lifecycle",
      name: "Lifecycle",
      document_version: Keyword.get(attrs, :latest_version, 1),
      latest_version: 1,
      draft_version: 1,
      published_version: nil,
      lifecycle_state: "active"
    ]

    struct!(DashboardSummary, Keyword.merge(defaults, attrs))
  end

  defp version(version) do
    %Version{
      dashboard_version_id: "dashboard-lifecycle-version-#{version}",
      organization_id: "org-lifecycle",
      mission_id: "mission-lifecycle",
      dashboard_id: "dashboard-lifecycle",
      version: version,
      document: nil
    }
  end
end
