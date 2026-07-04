defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls

  def context_search(socket, query, opts \\ []) do
    context_search_fn(opts).(socket, query)
  end

  def set_context(socket, context, opts \\ []) do
    set_context_fn(opts).(socket, context, opts)
  end

  def clear_context(socket, opts \\ []) do
    clear_context_fn(opts).(socket, opts)
  end

  def set_runtime_context(socket, params, opts \\ []) when is_map(params) do
    set_runtime_context_fn(opts).(socket, params, opts)
  end

  def resume_live(socket, opts \\ []) do
    resume_live_fn(opts).(socket, opts)
  end

  def set_time_preset(socket, preset, opts \\ []) do
    set_time_preset_fn(opts).(socket, preset, opts)
  end

  def pause_at_selected_time(socket, opts \\ []) do
    pause_at_selected_time_fn(opts).(socket, opts)
  end

  def scrub_replay_to_selection(socket, opts \\ []) do
    scrub_replay_to_selection_fn(opts).(socket, opts)
  end

  def clear_data_selection(socket, opts \\ []) do
    clear_data_selection_fn(opts).(socket, opts)
  end

  defp context_search_fn(opts),
    do: Keyword.get(opts, :context_search_event, &RuntimeControls.context_search/2)

  defp set_context_fn(opts),
    do: Keyword.get(opts, :set_context_event, &RuntimeControls.set_context/3)

  defp clear_context_fn(opts),
    do: Keyword.get(opts, :clear_context_event, &RuntimeControls.clear_context/2)

  defp set_runtime_context_fn(opts),
    do: Keyword.get(opts, :set_runtime_context_event, &RuntimeControls.set_runtime_context/3)

  defp resume_live_fn(opts),
    do: Keyword.get(opts, :resume_live_event, &RuntimeControls.resume_live/2)

  defp set_time_preset_fn(opts),
    do: Keyword.get(opts, :set_time_preset_event, &RuntimeControls.set_time_preset/3)

  defp pause_at_selected_time_fn(opts),
    do:
      Keyword.get(opts, :pause_at_selected_time_event, &RuntimeControls.pause_at_selected_time/2)

  defp scrub_replay_to_selection_fn(opts),
    do:
      Keyword.get(
        opts,
        :scrub_replay_to_selection_event,
        &RuntimeControls.scrub_replay_to_selection/2
      )

  defp clear_data_selection_fn(opts),
    do: Keyword.get(opts, :clear_data_selection_event, &RuntimeControls.clear_data_selection/2)
end
