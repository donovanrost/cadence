defmodule CadenceWeb.OpsDashboardShowLive.RenderSelectionAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec selection_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def selection_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    %{
      state: selection_state(assigns),
      target: selection_target(assigns),
      source_binding: selection_source_binding(assigns),
      data_view: selection_data_view(assigns),
      series_role: selection_series_role(assigns),
      compare_of: selection_compare_of(assigns)
    }
  end

  @spec evidence_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def evidence_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    %{
      state: evidence_state(assigns),
      kind: evidence_kind(assigns),
      source_request: evidence_source_request(assigns),
      logical_source: evidence_logical_source(assigns),
      realm: evidence_realm(assigns),
      data_source_id: evidence_data_source_id(assigns),
      source_binding_id: evidence_source_binding_id(assigns),
      time_mode: evidence_time_mode(assigns),
      time_axis: evidence_time_axis(assigns),
      replay_run_id: evidence_replay_run_id(assigns),
      scope_kind: evidence_scope_kind(assigns),
      scope_id: evidence_scope_id(assigns),
      scope_ids: evidence_scope_ids(assigns),
      contact_id: evidence_contact_id(assigns),
      source_endpoint_id: evidence_source_endpoint_id(assigns),
      source_empty_reason: evidence_source_empty_reason(assigns),
      requested_realm: evidence_requested_realm(assigns),
      requested_data_view: evidence_requested_data_view(assigns),
      requested_data_source_id: evidence_requested_data_source_id(assigns),
      requested_source_binding_id: evidence_requested_source_binding_id(assigns),
      requested_dataset: evidence_requested_dataset(assigns),
      requested_validity_state: evidence_requested_validity_state(assigns)
    }
  end

  def selection_state(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    cond do
      SelectedDataRef.present?(Map.get(assigns, :dashboard_selected_data_ref)) ->
        "active"

      data_link_panel_status(Map.get(assigns, :panel)) == :missing ->
        "missing_target"

      selection_query?(assigns) ->
        "query_only"

      Map.get(assigns, :dashboard_selection_state) == "stale_context" ->
        "stale_context"

      true ->
        "none"
    end
  end

  def selection_target(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    selected_ref_value(assigns, "target") ||
      selection_query_value(assigns, "selected_target")
  end

  def selection_source_binding(socket_or_assigns) do
    socket_or_assigns
    |> normalize()
    |> selected_ref_value("source_binding_id")
  end

  def selection_data_view(socket_or_assigns) do
    socket_or_assigns
    |> normalize()
    |> selected_ref_value("data_view")
  end

  def selection_series_role(socket_or_assigns) do
    socket_or_assigns
    |> normalize()
    |> selected_ref_value("series_role")
  end

  def selection_compare_of(socket_or_assigns) do
    socket_or_assigns
    |> normalize()
    |> selected_ref_value("compare_of")
  end

  def evidence_state(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_state(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_kind(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_kind(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_source_request(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_source_request(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_logical_source(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_logical_source(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_realm(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_realm(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_data_source_id(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_data_source_id(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_source_binding_id(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    DataLinkSelection.evidence_source_binding_id(
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    )
  end

  def evidence_time_mode(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_time_mode)
  end

  def evidence_time_axis(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_time_axis)
  end

  def evidence_replay_run_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_replay_run_id)
  end

  def evidence_scope_kind(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_scope_kind)
  end

  def evidence_scope_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_scope_id)
  end

  def evidence_scope_ids(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_scope_ids)
  end

  def evidence_contact_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_contact_id)
  end

  def evidence_source_endpoint_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_source_endpoint_id)
  end

  def evidence_source_empty_reason(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_source_empty_reason)
  end

  def evidence_requested_realm(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_realm)
  end

  def evidence_requested_data_view(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_data_view)
  end

  def evidence_requested_data_source_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_data_source_id)
  end

  def evidence_requested_source_binding_id(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_source_binding_id)
  end

  def evidence_requested_dataset(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_dataset)
  end

  def evidence_requested_validity_state(socket_or_assigns) do
    evidence_context_value(socket_or_assigns, :evidence_requested_validity_state)
  end

  defp evidence_context_value(socket_or_assigns, function_name) do
    assigns = normalize(socket_or_assigns)

    apply(DataLinkSelection, function_name, [
      Map.get(assigns, :panel),
      Map.get(assigns, :dashboard_evidence_query)
    ])
  end

  defp selected_ref_value(assigns, key) do
    assigns
    |> Map.get(:dashboard_selected_data_ref)
    |> SelectedDataRef.value(key)
  end

  defp selection_query_value(assigns, key) do
    assigns
    |> Map.get(:dashboard_selection_query)
    |> SelectionQuery.value(key)
  end

  defp selection_query?(assigns) do
    assigns
    |> Map.get(:dashboard_selection_query)
    |> SelectionQuery.query?()
  end

  defp data_link_panel_status({:data_link, %{status: status}}), do: status
  defp data_link_panel_status({:data_link, %{"status" => status}}), do: status
  defp data_link_panel_status(_panel), do: nil
end
