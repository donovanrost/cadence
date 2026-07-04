defmodule CadenceWeb.OpsDashboardShowLive.MountState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards
  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.EngineResolution
  alias CadenceWeb.OpsDashboardShowLive.InitialState
  alias CadenceWeb.OpsDashboardShowLive.LiveRefresh
  alias CadenceWeb.OpsDashboardShowLive.MountResources

  @tick_ms 1_000

  def assign_loaded_dashboard(
        socket,
        scope,
        mission,
        %Document{} = document,
        document_mode,
        opts \\ []
      ) do
    resources =
      opts
      |> resource_loader()
      |> apply([scope, mission])
      |> Map.merge(%{document: document, document_mode: document_mode})

    default_live_refresh_ms = default_live_refresh_ms(opts)

    socket =
      socket
      |> InitialState.assign_loaded_dashboard(resources,
        default_live_refresh_ms: default_live_refresh_ms
      )
      |> assign_versions(opts)
      |> assign_publish_validation(opts)
      |> assign_investigation_presets(scope, mission, document, opts)

    assign(
      socket,
      :dashboard_live_refresh_ms,
      engine_refresh_ms(opts).(socket, default_live_refresh_ms)
    )
  end

  def default_live_refresh_ms(opts \\ []) do
    Keyword.get_lazy(opts, :default_live_refresh_ms, fn ->
      LiveRefresh.default_refresh_ms(@tick_ms)
    end)
  end

  defp resource_loader(opts) do
    Keyword.get(opts, :resource_loader, &MountResources.load/2)
  end

  defp assign_versions(socket, opts) do
    Keyword.get(opts, :assign_versions, &DocumentLifecycle.assign_versions/1).(socket)
  end

  defp assign_publish_validation(socket, opts) do
    Keyword.get(opts, :assign_publish_validation, &DocumentLifecycle.assign_publish_validation/1).(
      socket
    )
  end

  defp assign_investigation_presets(socket, scope, mission, %Document{} = document, opts) do
    assign(
      socket,
      :dashboard_investigation_presets,
      list_investigation_presets(opts).(
        scope.organization_id,
        mission.mission_id,
        document.dashboard_id,
        preset_kind: :comparison
      )
    )
  end

  defp list_investigation_presets(opts) do
    Keyword.get(
      opts,
      :list_dashboard_investigation_presets,
      &Dashboards.list_dashboard_investigation_presets/4
    )
  end

  defp engine_refresh_ms(opts) do
    Keyword.get(opts, :engine_refresh_ms, &EngineResolution.refresh_ms/2)
  end
end
