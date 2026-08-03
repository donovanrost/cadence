defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControls do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Cadence.Dashboards.TimeRange
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.Navigation
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel

  def context_search(socket, query) do
    assign(socket, :context_query, query)
  end

  def time_quick_search(socket, query) when is_binary(query) do
    assign(socket, :dashboard_time_quick_query, query)
  end

  def load_time_recents(socket, ranges) do
    assign(socket, :dashboard_time_recent_ranges, validated_recent_ranges(ranges))
  end

  @max_recent_ranges 4

  defp validated_recent_ranges(ranges) when is_list(ranges) do
    ranges
    |> Enum.filter(&valid_recent_range?/1)
    |> Enum.map(fn %{"from" => from, "to" => to} -> %{from: from, to: to} end)
    |> Enum.take(@max_recent_ranges)
  end

  defp validated_recent_ranges(_ranges), do: []

  defp valid_recent_range?(%{"from" => from, "to" => to})
       when is_binary(from) and is_binary(to) do
    match?({:ok, {:absolute, _from, _to}}, TimeRange.resolve(from, to, DateTime.utc_now()))
  end

  defp valid_recent_range?(_range), do: false

  def set_context(socket, context, opts \\ [])

  def set_context(socket, %{"scope_kind" => scope_kind, "scope_ids" => scope_ids}, opts) do
    socket = assign(socket, :context_query, "")

    {socket, query} =
      stale_selection_checked_runtime_query(
        socket,
        context_query(scope_kind, normalized_scope_ids(scope_ids)),
        opts
      )

    Navigation.patch(socket, query, opts)
  end

  def set_context(socket, %{"scope_kind" => scope_kind, "scope_id" => scope_id}, opts) do
    socket = assign(socket, :context_query, "")

    {socket, query} =
      stale_selection_checked_runtime_query(
        socket,
        context_query(scope_kind, scope_id),
        opts
      )

    Navigation.patch(socket, query, opts)
  end

  def set_context(socket, spacecraft_id, opts) do
    set_context(socket, %{"scope_kind" => "spacecraft", "scope_id" => spacecraft_id}, opts)
  end

  def clear_context(socket, opts \\ []) do
    {socket, query} =
      stale_selection_checked_runtime_query(
        socket,
        %{"spacecraft_id" => nil, "scope_kind" => nil, "scope_id" => nil, "scope_ids" => nil},
        opts
      )

    Navigation.patch(socket, query, opts)
  end

  def set_runtime_context(socket, params, opts \\ []) when is_map(params) do
    query =
      params
      |> Map.take([
        "time_mode",
        "time_axis",
        "from",
        "to",
        "replay_run_id",
        "realm",
        "data_view",
        "compare_data_view",
        "limit_mode",
        "data_source_id",
        "source_binding_id",
        "hidden_markers",
        "markers"
      ])
      |> RuntimeQuery.normalize_runtime_query(
        socket.assigns.dashboard_data_realms,
        socket.assigns.dashboard_data_bindings,
        socket.assigns.dashboard_document
      )

    {socket, query} = stale_selection_checked_runtime_query(socket, query, opts)

    Navigation.patch(socket, query, opts)
  end

  def resume_live(socket, opts \\ []) do
    socket
    |> SelectionPanel.clear_dashboard_selection()
    |> Navigation.patch(RuntimeQuery.live_time_overrides(socket.assigns), opts)
  end

  def set_time_preset(socket, preset, opts \\ [])

  def set_time_preset(socket, "live", opts) do
    resume_live(socket, opts)
  end

  def set_time_preset(socket, preset, opts) do
    case TimeRange.quick_range(preset) do
      {:ok, range} ->
        socket
        |> SelectionPanel.clear_dashboard_selection()
        |> Navigation.patch(
          %{
            "time_mode" => nil,
            "time_axis" => nil,
            "from" => range.from,
            "to" => range.to,
            "replay_run_id" => nil
          },
          opts
        )

      :error ->
        put_flash(socket, :error, "Unknown dashboard time preset.")
    end
  end

  def set_chart_time_range(socket, params, opts \\ [])

  def set_chart_time_range(socket, %{"from" => from, "to" => to}, opts) do
    case TimeRange.resolve(from, to, Keyword.get(opts, :now, DateTime.utc_now())) do
      {:ok, {:sliding, _window_seconds}} ->
        socket
        |> SelectionPanel.clear_dashboard_selection()
        |> Navigation.patch(
          %{
            "time_mode" => nil,
            "from" => String.trim(from),
            "to" => String.trim(to),
            "replay_run_id" => nil
          },
          opts
        )

      {:ok, {:absolute, from_value, to_value}} ->
        patch_absolute_range(socket, {from_value, to_value}, opts, store_recent: true)

      {:error, :window_too_large} ->
        put_flash(
          socket,
          :error,
          "Sliding windows are capped at 24 hours. Use an absolute range instead."
        )

      {:error, _reason} ->
        put_flash(socket, :error, "Select a valid chart time range.")
    end
  end

  def set_chart_time_range(socket, _params, _opts) do
    put_flash(socket, :error, "Select a valid chart time range.")
  end

  def shift_time_range(socket, direction, opts \\ []) when direction in [:back, :forward] do
    with_current_absolute_range(socket, opts, &TimeRange.shift(&1, direction))
  end

  def zoom_out_time_range(socket, opts \\ []) do
    with_current_absolute_range(socket, opts, &TimeRange.zoom_out/1)
  end

  defp with_current_absolute_range(socket, opts, transform) do
    assigns = socket.assigns

    with true <- assigns.dashboard_time_mode in ["live", "archive"],
         now = Keyword.get(opts, :now, DateTime.utc_now()),
         {:ok, range} <- current_absolute_range(assigns, now) do
      patch_absolute_range(socket, transform.(range), opts)
    else
      _unbounded_or_replay -> socket
    end
  end

  defp current_absolute_range(assigns, now) do
    case TimeRange.resolve(assigns.dashboard_time_from, assigns.dashboard_time_to, now) do
      {:ok, {:sliding, window_seconds}} ->
        to_value = DateTime.truncate(now, :second)
        {:ok, {DateTime.add(to_value, -window_seconds, :second), to_value}}

      {:ok, {:absolute, from_value, to_value}} ->
        {:ok, {from_value, to_value}}

      {:error, _reason} ->
        :error
    end
  end

  defp patch_absolute_range(socket, {from_value, to_value}, opts, range_opts \\ []) do
    from_iso = DateTime.to_iso8601(from_value)
    to_iso = DateTime.to_iso8601(to_value)

    socket
    |> SelectionPanel.clear_dashboard_selection()
    |> maybe_store_recent(from_iso, to_iso, Keyword.get(range_opts, :store_recent, false))
    |> Navigation.patch(
      %{
        "time_mode" => "archive",
        "from" => from_iso,
        "to" => to_iso,
        "replay_run_id" => nil
      },
      opts
    )
  end

  defp maybe_store_recent(socket, from_iso, to_iso, true),
    do: push_event(socket, "cadence:store-time-recent", %{from: from_iso, to: to_iso})

  defp maybe_store_recent(socket, _from_iso, _to_iso, false), do: socket

  def pause_at_selected_time(socket, opts \\ []) do
    case selected_archive_range(socket.assigns.dashboard_selected_data_ref) do
      {:ok, from_iso, to_iso} ->
        time_axis = SelectedDataRef.value(socket.assigns.dashboard_selected_data_ref, "time_axis")

        query =
          %{
            "time_mode" => "archive",
            "from" => from_iso,
            "to" => to_iso
          }
          |> maybe_put("time_axis", time_axis)

        Navigation.patch(socket, query, opts)

      :error ->
        put_flash(socket, :error, "Select a timestamped dashboard datum first.")
    end
  end

  def scrub_replay_to_selection(socket, opts \\ []) do
    replay_run_id =
      socket.assigns.dashboard_replay_run_id ||
        SelectedDataRef.value(socket.assigns.dashboard_selected_data_ref, "replay_run_id")

    case {present_text(replay_run_id),
          selected_archive_range(socket.assigns.dashboard_selected_data_ref)} do
      {replay_run_id, {:ok, from_iso, to_iso}} when is_binary(replay_run_id) ->
        time_axis = SelectedDataRef.value(socket.assigns.dashboard_selected_data_ref, "time_axis")

        query =
          %{
            "time_mode" => "replay_run",
            "replay_run_id" => replay_run_id,
            "from" => from_iso,
            "to" => to_iso
          }
          |> maybe_put("time_axis", time_axis)

        Navigation.patch(socket, query, opts)

      {nil, _range} ->
        put_flash(socket, :error, "Select a replay run before scrubbing replay time.")

      {_replay_run_id, :error} ->
        put_flash(socket, :error, "Select a timestamped replay datum first.")
    end
  end

  def clear_data_selection(socket, opts \\ []) do
    socket
    |> SelectionPanel.clear_dashboard_data_selection()
    |> SelectionPanel.close_data_link_panel()
    |> Navigation.patch(DataLinkSelection.clear_panel_query(:data_link), opts)
  end

  defp context_query("spacecraft", spacecraft_id) when is_binary(spacecraft_id) do
    %{
      "spacecraft_id" => spacecraft_id,
      "scope_kind" => nil,
      "scope_id" => nil,
      "scope_ids" => nil
    }
  end

  defp context_query(scope_kind, scope_ids) when is_binary(scope_kind) and is_list(scope_ids) do
    case normalized_scope_ids(scope_ids) do
      [scope_id] ->
        context_query(scope_kind, scope_id)

      scope_ids when scope_ids != [] ->
        %{
          "spacecraft_id" => nil,
          "scope_kind" => scope_kind,
          "scope_id" => nil,
          "scope_ids" => Enum.join(scope_ids, ",")
        }

      [] ->
        context_query(nil, nil)
    end
  end

  defp context_query(scope_kind, scope_id) when is_binary(scope_kind) and is_binary(scope_id) do
    %{
      "spacecraft_id" => nil,
      "scope_kind" => scope_kind,
      "scope_id" => scope_id,
      "scope_ids" => nil
    }
  end

  defp context_query(_scope_kind, _scope_id) do
    %{"spacecraft_id" => nil, "scope_kind" => nil, "scope_id" => nil, "scope_ids" => nil}
  end

  defp normalized_scope_ids(scope_ids) do
    scope_ids
    |> List.wrap()
    |> Enum.flat_map(fn
      scope_ids when is_binary(scope_ids) -> String.split(scope_ids, ",", trim: true)
      _value -> []
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def stale_selection_checked_runtime_query(socket, query, opts \\ []) do
    runtime_context =
      socket
      |> Navigation.current_query()
      |> RouteQuery.merge(query)
      |> RuntimeQuery.runtime_context_from_params(
        socket.assigns.current_scope,
        socket.assigns.current_mission,
        socket.assigns.spacecraft,
        socket.assigns.dashboard_data_realms,
        socket.assigns.dashboard_data_bindings,
        socket.assigns.dashboard_document,
        valid_contact?: valid_contact_callback(opts),
        valid_operational_resource_scope?: valid_operational_resource_scope_callback(opts)
      )

    SelectionPanel.stale_selection_checked_runtime_query(socket, query, runtime_context)
  end

  def selected_archive_range(selected_ref) do
    SelectedDataRef.archive_range(selected_ref)
  end

  defp present_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp present_text(_value), do: nil

  defp maybe_put(query, _key, nil), do: query
  defp maybe_put(query, _key, ""), do: query
  defp maybe_put(query, key, value), do: Map.put(query, key, value)

  defp valid_contact_callback(opts) do
    Keyword.get(opts, :valid_contact?, fn _scope, _mission, _contact_id -> false end)
  end

  defp valid_operational_resource_scope_callback(opts) do
    Keyword.get(opts, :valid_operational_resource_scope?, fn
      _scope, _mission, _scope_kind, _scope_id -> true
    end)
  end
end
