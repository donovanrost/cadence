defmodule CadenceWeb.OpsDashboardShowLive.InvestigationPresetEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards
  alias CadenceWeb.OpsDashboardShowLive.ComparisonInvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionContext
  alias CadenceWeb.OpsDashboardShowLive.Navigation
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery
  alias CadenceWeb.OpsDashboardShowLive.WidgetComparisonSummary

  def save_comparison_preset(socket, params, opts \\ []) when is_map(params) do
    name = params |> preset_params() |> Map.get("name") |> present_text()

    cond do
      is_nil(name) ->
        flash(socket, :error, "Name the comparison preset before saving.", opts)

      is_nil(active_comparison_preset(socket)) ->
        flash(socket, :error, "Enable a dashboard comparison before saving.", opts)

      true ->
        save_active_preset(socket, name, opts)
    end
  end

  def apply_comparison_preset(socket, params, opts \\ []) when is_map(params) do
    with {:ok, preset_id} <- fetch_param(params, "preset-id"),
         {:ok, preset} <- fetch_investigation_preset(socket, preset_id, opts) do
      # Only restore runtime context. Selection/panel state belongs to the current operator session.
      socket
      |> flash(:info, "Comparison preset loaded.", opts)
      |> Navigation.patch(RouteQuery.runtime_restore_overrides(preset.runtime_query), opts)
    else
      :error ->
        flash(socket, :error, "Invalid comparison preset.", opts)

      {:error, :investigation_preset_not_found} ->
        socket
        |> refresh_presets(opts)
        |> flash(:error, "Comparison preset no longer exists.", opts)
    end
  end

  def delete_comparison_preset(socket, params, opts \\ []) when is_map(params) do
    with {:ok, preset_id} <- fetch_param(params, "preset-id"),
         :ok <- delete_investigation_preset(socket, preset_id, opts) do
      socket
      |> refresh_presets(opts)
      |> flash(:info, "Comparison preset deleted.", opts)
    else
      :error ->
        flash(socket, :error, "Invalid comparison preset.", opts)

      {:error, :investigation_preset_not_found} ->
        socket
        |> refresh_presets(opts)
        |> flash(:error, "Comparison preset no longer exists.", opts)
    end
  end

  def refresh_presets(socket, opts \\ []) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)

    assign(
      socket,
      :dashboard_investigation_presets,
      list_investigation_presets(opts).(
        organization_id,
        mission_id,
        dashboard_id,
        preset_kind: :comparison
      )
    )
  end

  defp save_active_preset(socket, name, opts) do
    preset = active_comparison_preset(socket)
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)

    # authz pending: Gate dashboard investigation preset mutations once RBAC exists.
    case save_investigation_preset(opts).(
           organization_id,
           mission_id,
           dashboard_id,
           %{name: name, payload: preset},
           DashboardActionContext.actor_opts(socket)
         ) do
      {:ok, _preset} ->
        socket
        |> refresh_presets(opts)
        |> flash(:info, "Comparison preset saved.", opts)

      {:error, changeset} ->
        flash(socket, :error, save_error_message(changeset), opts)
    end
  end

  defp active_comparison_preset(socket) do
    widget_items = RenderWidgetModel.widget_items(socket.assigns)
    rollup = WidgetComparisonSummary.rollup(widget_items)

    ComparisonInvestigationPreset.build(
      socket.assigns,
      Navigation.show_path(socket, %{}),
      rollup
    )
  end

  defp fetch_investigation_preset(socket, preset_id, opts) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)
    fetch_investigation_preset_fn(opts).(organization_id, mission_id, dashboard_id, preset_id)
  end

  defp delete_investigation_preset(socket, preset_id, opts) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)
    delete_investigation_preset_fn(opts).(organization_id, mission_id, dashboard_id, preset_id)
  end

  defp preset_params(%{"preset" => params}) when is_map(params), do: params
  defp preset_params(params) when is_map(params), do: params

  defp fetch_param(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> :error
    end
  end

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil

  defp save_error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :name) do
      "A comparison preset with that name already exists."
    else
      "Failed to save comparison preset."
    end
  end

  defp save_error_message(:dashboard_not_found), do: "Dashboard no longer exists."
  defp save_error_message(:dashboard_archived), do: "Dashboard is archived."
  defp save_error_message(_reason), do: "Failed to save comparison preset."

  defp save_investigation_preset(opts) do
    Keyword.get(
      opts,
      :save_dashboard_investigation_preset,
      &Dashboards.save_dashboard_investigation_preset/5
    )
  end

  defp list_investigation_presets(opts) do
    Keyword.get(
      opts,
      :list_dashboard_investigation_presets,
      &Dashboards.list_dashboard_investigation_presets/4
    )
  end

  defp fetch_investigation_preset_fn(opts) do
    Keyword.get(
      opts,
      :fetch_dashboard_investigation_preset,
      &Dashboards.fetch_dashboard_investigation_preset/4
    )
  end

  defp delete_investigation_preset_fn(opts) do
    Keyword.get(
      opts,
      :delete_dashboard_investigation_preset,
      &Dashboards.delete_dashboard_investigation_preset/4
    )
  end

  defp flash(socket, kind, message, opts) do
    DashboardActionContext.flash(socket, kind, message, opts)
  end
end
