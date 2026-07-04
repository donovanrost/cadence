defmodule CadenceWeb.OpsDashboardShowLive.LifecycleEvents do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle

  def archive_dashboard(socket, opts) do
    archive_document(opts).(socket, nav_opts(opts))
  end

  def publish_dashboard(socket, opts) do
    publish_latest_draft(opts).(socket, nav_opts(opts))
  end

  def publish_dashboard_version(socket, version, opts) do
    publish_version(opts).(socket, version, nav_opts(opts))
  end

  def save_runtime_defaults(socket, opts) do
    case save_runtime_defaults_fn(opts).(socket, nav_opts(opts)) do
      {:ok, socket} ->
        {:ok, put_flash_fn(opts).(socket, :info, "Dashboard runtime defaults saved.")}

      {:error, socket} ->
        {:error, socket}
    end
  end

  def restore_version_as_draft(socket, version, opts) do
    restore_version_as_draft_fn(opts).(socket, version, nav_opts(opts))
  end

  defp nav_opts(opts) do
    [dashboard_list_path: Keyword.fetch!(opts, :dashboard_list_path)]
  end

  defp archive_document(opts) do
    Keyword.get(opts, :archive_document, &DocumentLifecycle.archive_document/2)
  end

  defp publish_latest_draft(opts) do
    Keyword.get(opts, :publish_latest_draft, &DocumentLifecycle.publish_latest_draft/2)
  end

  defp publish_version(opts) do
    Keyword.get(opts, :publish_version, &DocumentLifecycle.publish_version/3)
  end

  defp save_runtime_defaults_fn(opts) do
    Keyword.get(opts, :save_runtime_defaults, &DocumentLifecycle.save_runtime_defaults/2)
  end

  defp restore_version_as_draft_fn(opts) do
    Keyword.get(opts, :restore_version_as_draft, &DocumentLifecycle.restore_version_as_draft/3)
  end

  defp put_flash_fn(opts) do
    Keyword.get(opts, :put_flash, &put_flash/3)
  end
end
