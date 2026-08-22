defmodule Cadence.Dashboards.DashboardLifecycleStatus do
  @moduledoc """
  Interprets dashboard version pointers as a stable lifecycle status.

  Persistence stores the authoritative pointers. This module gives runtime and
  UI code one place to answer product questions like "is there a draft ahead of
  the published version?" without repeating pointer comparisons.
  """

  alias Cadence.Dashboards.{DashboardSummary, Version}

  @type publication_state ::
          :unknown | :archived | :unpublished | :published_current | :draft_ahead

  @type t :: %__MODULE__{
          publication_state: publication_state(),
          lifecycle_state: binary() | nil,
          latest_version: pos_integer() | nil,
          draft_version: pos_integer() | nil,
          published_version: pos_integer() | nil,
          publishable_version: pos_integer() | nil,
          published_current?: boolean(),
          draft_ahead?: boolean(),
          publish_available?: boolean(),
          revert_available?: boolean(),
          archive_available?: boolean(),
          restore_available?: boolean()
        }

  @type version_action :: %{
          version: pos_integer() | nil,
          restore_available?: boolean(),
          restore_reason: :available | :unknown | :archived | :already_latest,
          publish_available?: boolean(),
          publish_reason: :available | :unknown | :archived | :already_published
        }

  defstruct publication_state: :unknown,
            lifecycle_state: nil,
            latest_version: nil,
            draft_version: nil,
            published_version: nil,
            publishable_version: nil,
            published_current?: false,
            draft_ahead?: false,
            publish_available?: false,
            revert_available?: false,
            archive_available?: false,
            restore_available?: false

  @spec from_summary(DashboardSummary.t() | nil) :: t()
  def from_summary(nil), do: %__MODULE__{}

  def from_summary(%DashboardSummary{} = summary) do
    publication_state = publication_state(summary)
    active? = summary.lifecycle_state != "archived"
    publishable_version = publishable_version(summary, publication_state)

    %__MODULE__{
      publication_state: publication_state,
      lifecycle_state: summary.lifecycle_state,
      latest_version: summary.latest_version,
      draft_version: summary.draft_version,
      published_version: summary.published_version,
      publishable_version: publishable_version,
      published_current?: publication_state == :published_current,
      draft_ahead?: publication_state == :draft_ahead,
      publish_available?:
        active? and publication_state in [:unpublished, :draft_ahead] and
          is_integer(publishable_version),
      revert_available?: active? and version_after_initial?(summary.latest_version),
      archive_available?: active?,
      restore_available?: not active?
    }
  end

  @spec version_action(DashboardSummary.t() | nil, Version.t() | pos_integer()) ::
          version_action()
  def version_action(summary, %Version{version: version}) do
    version_action(summary, version)
  end

  def version_action(nil, version) when is_integer(version) and version > 0 do
    %{
      version: version,
      restore_available?: false,
      restore_reason: :unknown,
      publish_available?: false,
      publish_reason: :unknown
    }
  end

  def version_action(%DashboardSummary{lifecycle_state: "archived"}, version)
      when is_integer(version) and version > 0 do
    %{
      version: version,
      restore_available?: false,
      restore_reason: :archived,
      publish_available?: false,
      publish_reason: :archived
    }
  end

  def version_action(%DashboardSummary{} = summary, version)
      when is_integer(version) and version > 0 do
    %{
      version: version,
      restore_available?: version != summary.latest_version,
      restore_reason: restore_reason(summary, version),
      publish_available?: version != summary.published_version,
      publish_reason: publish_reason(summary, version)
    }
  end

  def version_action(_summary, _version) do
    %{
      version: nil,
      restore_available?: false,
      restore_reason: :unknown,
      publish_available?: false,
      publish_reason: :unknown
    }
  end

  defp publication_state(%DashboardSummary{lifecycle_state: "archived"}), do: :archived

  defp publication_state(%DashboardSummary{published_version: nil}), do: :unpublished

  defp publication_state(%DashboardSummary{} = summary) do
    cond do
      draft_ahead?(summary) -> :draft_ahead
      published_current?(summary) -> :published_current
      true -> :draft_ahead
    end
  end

  defp draft_ahead?(%DashboardSummary{
         latest_version: latest_version,
         draft_version: draft_version,
         published_version: published_version
       }) do
    version_after?(latest_version, published_version) or
      (is_integer(draft_version) and draft_version != published_version)
  end

  defp published_current?(%DashboardSummary{
         latest_version: latest_version,
         draft_version: draft_version,
         published_version: published_version
       }) do
    is_integer(published_version) and latest_version == published_version and
      (is_nil(draft_version) or draft_version == published_version)
  end

  defp publishable_version(_summary, :archived), do: nil
  defp publishable_version(_summary, :published_current), do: nil

  defp publishable_version(%DashboardSummary{} = summary, _publication_state) do
    summary.draft_version || summary.latest_version || summary.document_version
  end

  defp version_after?(version, previous) when is_integer(version) and is_integer(previous),
    do: version > previous

  defp version_after?(_version, _previous), do: false

  defp version_after_initial?(version) when is_integer(version), do: version > 1
  defp version_after_initial?(_version), do: false

  defp restore_reason(%DashboardSummary{} = summary, version) do
    if version == summary.latest_version, do: :already_latest, else: :available
  end

  defp publish_reason(%DashboardSummary{} = summary, version) do
    if version == summary.published_version, do: :already_published, else: :available
  end
end
