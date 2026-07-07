defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanel do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Cadence.Dashboards.{DataLink, DataLinkResolver}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkIndex
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelection
  alias CadenceWeb.OpsDashboardShowLive.Navigation
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAssigns
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  def find_data_link(socket, link_id) when is_binary(link_id) and link_id != "" do
    socket
    |> data_link_index()
    |> DataLinkIndex.all_links()
    |> DataLinkIndex.find_link(link_id)
  end

  def find_data_link(_socket, _link_id), do: nil

  def resolve_data_link_selection(socket, link_id, params) do
    link =
      find_data_link(socket, link_id) ||
        DataLinkSelection.synthetic_link_from_event_params(params)

    case link do
      %DataLink{} = link ->
        link =
          link
          |> DataLinkSelection.with_selection_context(params)
          |> DataLinkSelection.with_runtime_context(data_link_runtime_context(socket))

        {resolve_data_link(socket, link), DataLinkSelection.selected_ref(link, params)}

      nil ->
        {DataLinkResolver.missing(link_id), nil}
    end
  end

  def resolve_data_link(socket, %DataLink{} = link) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case DataLinkResolver.resolve(link,
           organization_id: scope.organization_id,
           mission_id: mission.mission_id
         ) do
      {:ok, inspector} -> inspector
      {:error, inspector} -> inspector
    end
  end

  def open_evidence(socket, params, opts) do
    evidence_query = DataLinkSelection.evidence_query_from_event_params(params)
    inspector = evidence_inspector_or_missing(socket, params, evidence_query)

    socket
    |> clear_dashboard_selection()
    |> assign(:dashboard_evidence_query, evidence_query)
    |> assign(:panel, {:evidence, inspector})
    |> Navigation.patch(DataLinkSelection.panel_query(:evidence, evidence_query), opts)
  end

  def open_data_link(socket, link_id, params, opts) do
    {inspector, selected_ref} = resolve_data_link_selection(socket, link_id, params)

    socket =
      socket
      |> clear_data_link_action_outcome(opts)
      |> assign(:panel, {:data_link, inspector})
      |> assign(:dashboard_selected_data_ref, selected_ref)
      |> assign(:dashboard_selection_state, if(selected_ref, do: "active", else: "query_only"))
      |> assign(:dashboard_evidence_query, nil)
      |> maybe_push_selected_ref(selected_ref)

    if selected_ref do
      selection_query = DataLinkSelection.selection_query_from_ref(selected_ref)

      socket
      |> assign(:dashboard_selection_query, selection_query)
      |> Navigation.patch(DataLinkSelection.panel_query(:data_link, selection_query), opts)
    else
      socket
    end
  end

  def put_historical_workflow_link_selection(socket, query, %DataLink{} = link, opts) do
    inspector = resolve_data_link(socket, link)
    selection_query = SelectionQuery.new(query)

    socket
    |> clear_data_link_action_outcome(opts)
    |> scope_data_link_action_outcome(selection_query, opts)
    |> assign(:panel, {:data_link, inspector})
    |> assign(:dashboard_selection_query, selection_query)
    |> assign(:dashboard_selected_data_ref, nil)
    |> assign(:dashboard_selection_state, "query_only")
    |> assign(:dashboard_evidence_query, nil)
    |> Navigation.patch(DataLinkSelection.panel_query(:data_link, selection_query), opts)
  end

  def refresh_current_historical_workflow_group_selection(socket) do
    query = socket.assigns[:dashboard_selection_query]

    case text_param(SelectionQuery.value(query, "selected_id")) do
      event_id when is_binary(event_id) ->
        inspector = resolve_data_link(socket, HistoricalWorkflowSelection.event_link(event_id))

        socket
        |> clear_data_link_action_outcome()
        |> assign(:panel, {:data_link, inspector})
        |> assign(:dashboard_selected_data_ref, nil)
        |> assign(:dashboard_selection_state, "query_only")
        |> assign(:dashboard_evidence_query, nil)

      nil ->
        socket
    end
  end

  def selected_data_ref_observable_id(socket) do
    SelectedDataRef.observable_id(socket.assigns[:dashboard_selected_data_ref])
  end

  def data_link_index(socket) do
    engine_result = socket.assigns.dashboard_engine_result
    frames_by_placement = Map.get(socket.assigns, :dashboard_engine_frames_by_placement)

    %{
      panel: socket.assigns.panel,
      engine_result: engine_result,
      frames_by_placement:
        if(is_map(frames_by_placement),
          do: frames_by_placement,
          else: RuntimeResult.frames_by_placement(engine_result)
        )
    }
  end

  def hydrate_selection_from_query(socket, opts) do
    case socket.assigns[:dashboard_selection_query] do
      nil -> hydrate_evidence_from_query(socket)
      query -> hydrate_selection_from_query(socket, query, opts)
    end
  end

  def hydrate_evidence_from_query(%{assigns: %{dashboard_evidence_query: nil}} = socket),
    do: socket

  def hydrate_evidence_from_query(socket) do
    params =
      DataLinkSelection.event_params_from_evidence_query(socket.assigns.dashboard_evidence_query)

    inspector =
      evidence_inspector_or_missing(socket, params, socket.assigns.dashboard_evidence_query)

    assign(socket, :panel, {:evidence, inspector})
  end

  def evidence_inspector_or_missing(socket, params, evidence_query) do
    EvidencePresentation.evidence_inspector(socket.assigns.dashboard_engine_result, params) ||
      DataLinkSelection.missing_evidence_inspector(evidence_query)
  end

  def data_link_runtime_context(socket) do
    RuntimeAssigns.data_link_runtime_context(socket)
  end

  def clear_dashboard_selection(socket) do
    socket
    |> clear_data_link_action_outcome()
    |> assign(:dashboard_selected_data_ref, nil)
    |> assign(:dashboard_selection_query, nil)
    |> assign(:dashboard_selection_state, "none")
    |> assign(:dashboard_evidence_query, nil)
    |> push_event("tlm:select", %{"selection" => nil})
  end

  def clear_dashboard_data_selection(socket) do
    socket
    |> clear_data_link_action_outcome()
    |> assign(:dashboard_selected_data_ref, nil)
    |> assign(:dashboard_selection_query, nil)
    |> assign(:dashboard_selection_state, "none")
    |> push_event("tlm:select", %{"selection" => nil})
  end

  def close_data_link_panel(%{assigns: %{panel: {:data_link, _inspector}}} = socket) do
    socket
    |> clear_data_link_action_outcome()
    |> assign(:panel, nil)
  end

  def close_data_link_panel(socket), do: socket

  def stale_selection_checked_runtime_query(socket, query, runtime_context) do
    decision =
      DataLinkSelection.stale_selection_decision(
        query,
        socket.assigns[:dashboard_selected_data_ref],
        socket.assigns[:dashboard_selection_query],
        runtime_context
      )

    {apply_stale_selection_decision(socket, decision.action), decision.query}
  end

  defp hydrate_selection_from_query(socket, query, opts) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case find_data_link_from_query(socket, query) do
      %DataLink{} = link ->
        hydrate_data_link_selection(socket, link, query, scope, mission, opts)

      nil ->
        case DataLinkSelection.missing_selected_link_id(query) do
          nil ->
            hydrate_evidence_from_query(socket)

          link_id ->
            socket
            |> clear_data_link_action_outcome(selection_query: query)
            |> assign(:panel, {:data_link, DataLinkResolver.missing(link_id)})
            |> assign(:dashboard_selected_data_ref, nil)
            |> assign(:dashboard_selection_state, "query_only")
        end
    end
  end

  defp hydrate_data_link_selection(socket, %DataLink{} = link, query, scope, mission, opts) do
    link =
      link
      |> DataLinkSelection.with_selection_context(
        DataLinkSelection.event_params_from_selection_query(query)
      )
      |> DataLinkSelection.with_runtime_context(data_link_runtime_context(socket))

    inspector =
      case DataLinkResolver.resolve(link,
             organization_id: scope.organization_id,
             mission_id: mission.mission_id
           ) do
        {:ok, inspector} -> inspector
        {:error, inspector} -> inspector
      end

    selected_ref =
      DataLinkSelection.selected_ref(
        link,
        DataLinkSelection.event_params_from_selection_query(query)
      )

    runtime_context = runtime_context_from_assigns(socket)

    cond do
      data_link_panel_query_only?(inspector) ->
        socket
        |> clear_data_link_action_outcome(selection_query: query)
        |> assign(:panel, {:data_link, inspector})
        |> assign(:dashboard_selected_data_ref, nil)
        |> assign(:dashboard_selection_state, "query_only")

      data_link_query_only_target?(link) ->
        socket
        |> clear_data_link_action_outcome(selection_query: query)
        |> assign(:panel, {:data_link, inspector})
        |> assign(:dashboard_selected_data_ref, nil)
        |> assign(:dashboard_selection_state, "query_only")

      DataLinkSelection.selected_ref_matches_query_runtime_context?(selected_ref, runtime_context) ->
        selected_ref =
          DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context)

        socket
        |> clear_data_link_action_outcome(selection_query: query)
        |> assign(:panel, {:data_link, inspector})
        |> assign(:dashboard_selected_data_ref, selected_ref)
        |> assign(:dashboard_selection_state, "active")
        |> maybe_push_selected_ref(selected_ref)

      true ->
        socket
        |> clear_data_link_action_outcome()
        |> assign(:dashboard_selected_data_ref, nil)
        |> assign(:dashboard_selection_query, nil)
        |> assign(:dashboard_selection_state, "stale_context")
        |> push_event("tlm:select", %{"selection" => nil})
        |> hydrate_evidence_from_query()
        |> Navigation.patch(DataLinkSelection.clear_panel_query(:data_link), opts)
    end
  end

  defp find_data_link_from_query(socket, query) do
    socket
    |> data_link_index()
    |> DataLinkIndex.find_link_from_query(query)
  end

  defp maybe_push_selected_ref(socket, nil), do: socket

  defp maybe_push_selected_ref(socket, selected_ref),
    do: push_event(socket, "tlm:select", %{"selection" => SelectedDataRef.new(selected_ref)})

  defp clear_data_link_action_outcome(socket, opts \\ []) do
    cond do
      Keyword.get(opts, :preserve_data_link_action_outcome?, false) ->
        socket

      data_link_action_outcome_query_matches?(socket, Keyword.get(opts, :selection_query)) ->
        socket

      true ->
        socket
        |> assign(:data_link_action_outcome, nil)
        |> assign(:data_link_action_outcome_query, nil)
    end
  end

  defp scope_data_link_action_outcome(socket, selection_query, opts) do
    if Keyword.get(opts, :preserve_data_link_action_outcome?, false) and
         socket.assigns[:data_link_action_outcome] do
      assign(socket, :data_link_action_outcome_query, SelectionQuery.to_params(selection_query))
    else
      socket
    end
  end

  defp data_link_action_outcome_query_matches?(socket, selection_query) do
    stored_query = socket.assigns[:data_link_action_outcome_query]

    is_map(stored_query) and
      stored_query != %{} and
      stored_query == SelectionQuery.to_params(selection_query)
  end

  defp data_link_panel_query_only?(inspector) when is_map(inspector) do
    Map.get(inspector, :status) in [:missing, :unsupported]
  end

  defp data_link_query_only_target?(%DataLink{target: target})
       when target in [
              :raw_evidence,
              :limit_definition,
              :source_health_event,
              :source_watermark_event,
              :comparison_finding,
              :telemetry_revision_decision_event,
              :telemetry_backfill_lifecycle_event,
              :dashboard_lifecycle_event
            ],
       do: true

  defp data_link_query_only_target?(_link), do: false

  defp apply_stale_selection_decision(socket, :clear_stale) do
    socket
    |> clear_dashboard_data_selection()
    |> close_data_link_panel()
    |> assign(:dashboard_selection_state, "stale_context")
  end

  defp apply_stale_selection_decision(socket, _action), do: socket

  defp runtime_context_from_assigns(socket) do
    RuntimeAssigns.runtime_context(socket)
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
