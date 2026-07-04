defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionContext

  @review_schema "dashboard_comparison_review_request.v1"
  @resolution_schema "dashboard_comparison_review_resolution.v1"
  @open_findings_schema "dashboard_comparison_open_findings.v1"

  def request_open_findings_review(socket, params, opts \\ []) when is_map(params) do
    # authz pending: Gate dashboard comparison review requests once RBAC exists.
    with {:ok, open_findings} <- open_findings_payload(params),
         {:ok, payload} <- review_payload(open_findings),
         {:ok, event} <- record_review_request(socket, payload, opts) do
      socket
      |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
      |> DashboardActionContext.target_activity(:comparison_reviews, event, opts)
      |> flash(:info, "Open comparison findings review requested.", opts)
    else
      {:error, :missing_open_findings} ->
        flash(socket, :error, "Open comparison findings are no longer available.", opts)

      {:error, :no_open_findings} ->
        flash(socket, :error, "No open comparison findings to request review for.", opts)

      {:error, :dashboard_not_found} ->
        flash(socket, :error, "Dashboard no longer exists.", opts)

      {:error, :dashboard_archived} ->
        flash(socket, :error, "Archived dashboards cannot request comparison review.", opts)

      {:error, {:comparison_review_already_requested, event}} ->
        socket
        |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
        |> DashboardActionContext.target_activity(:comparison_reviews, event, opts)
        |> flash(:info, "Comparison review is already requested.", opts)

      {:error, _reason} ->
        flash(socket, :error, "Failed to request comparison review.", opts)
    end
  end

  def resolve_open_findings_review(socket, params, opts \\ []) when is_map(params) do
    # authz pending: Gate dashboard comparison review resolution once RBAC exists.
    with {:ok, payload} <- resolution_payload(params),
         {:ok, event} <- record_review_resolution(socket, payload, opts) do
      socket
      |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
      |> DashboardActionContext.target_activity(:comparison_reviews, event, opts)
      |> flash(:info, "Comparison review marked resolved.", opts)
    else
      {:error, :missing_review_request} ->
        flash(socket, :error, "Comparison review request is no longer available.", opts)

      {:error, :comparison_review_request_not_found} ->
        flash(socket, :error, "Comparison review request no longer exists.", opts)

      {:error, :comparison_review_already_resolved} ->
        socket
        |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
        |> flash(:info, "Comparison review is already resolved.", opts)

      {:error, :comparison_review_resolution_context_mismatch} ->
        socket
        |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
        |> flash(
          :error,
          "Comparison review context changed. Review the request and try again.",
          opts
        )

      {:error, :dashboard_not_found} ->
        flash(socket, :error, "Dashboard no longer exists.", opts)

      {:error, :dashboard_archived} ->
        flash(socket, :error, "Archived dashboards cannot resolve comparison review.", opts)

      {:error, _reason} ->
        flash(socket, :error, "Failed to resolve comparison review.", opts)
    end
  end

  def apply_bulk_revision_decision(socket, params, opts \\ []) when is_map(params) do
    # authz pending: Gate dashboard bulk correction decisions once RBAC exists.
    with {:ok, params} <- bulk_decision_params(params),
         :ok <- confirm_bulk_decision(params),
         {:ok, request_event} <- review_request_event(socket, params["source_request_event_id"]),
         :ok <- ensure_review_open(request_event, socket),
         {:ok, source_context} <- bulk_decision_source_context(request_event),
         {:ok, items} <- bulk_decision_items(request_event),
         attrs <- bulk_decision_attrs(socket, request_event, source_context, params),
         {:ok, summary} <-
           bulk_decision_fn(opts).(items, params["decision"], attrs, bulk_decision_opts(opts)) do
      socket
      |> assign(
        :dashboard_comparison_review_action_outcome,
        bulk_decision_outcome(params, request_event, summary, items)
      )
      |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
      |> DashboardActionContext.target_activity(:open_comparison_reviews, request_event, opts)
      |> flash(:info, bulk_decision_message(summary), opts)
    else
      {:error, :missing_review_request} ->
        flash(socket, :error, "Comparison review request is no longer available.", opts)

      {:error, :comparison_review_request_not_found} ->
        flash(socket, :error, "Comparison review request no longer exists.", opts)

      {:error, :comparison_review_already_resolved} ->
        socket
        |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(opts)
        |> flash(:info, "Comparison review is already resolved.", opts)

      {:error, :bulk_decision_not_confirmed} ->
        flash(socket, :error, "Confirm the bulk comparison decision before applying it.", opts)

      {:error, :missing_bulk_decision_source_context} ->
        flash(socket, :error, "Comparison review is missing telemetry source context.", opts)

      {:error, :no_bulk_decision_items} ->
        flash(socket, :error, "No actionable comparison findings are available.", opts)

      {:error, {:missing_field, field}} ->
        flash(socket, :error, "Comparison review is missing #{field}.", opts)

      {:error, _reason} ->
        flash(socket, :error, "Failed to apply comparison review decisions.", opts)
    end
  end

  defp open_findings_payload(params) do
    params
    |> review_params()
    |> Map.get("open_findings")
    |> decode_open_findings()
  end

  defp decode_open_findings(value) when is_binary(value) and value != "" do
    with {:ok, payload} <- Jason.decode(value),
         true <- Map.get(payload, "schema") == @open_findings_schema,
         findings when is_list(findings) and findings != [] <- Map.get(payload, "findings") do
      {:ok, payload}
    else
      [] -> {:error, :no_open_findings}
      _invalid -> {:error, :invalid_open_findings}
    end
  end

  defp decode_open_findings(_value), do: {:error, :missing_open_findings}

  defp review_payload(open_findings) do
    findings = Map.fetch!(open_findings, "findings")

    if findings == [] do
      {:error, :no_open_findings}
    else
      {:ok,
       %{
         "schema" => @review_schema,
         "request_kind" => "comparison_open_findings_review",
         "source" => "dashboard_comparison_rollup",
         "open_findings" => open_findings,
         "workflow_intent" => Map.get(open_findings, "workflow_intent"),
         "open_count" => open_count(open_findings, findings),
         "open_placement_ids" => open_placement_ids(open_findings, findings)
       }}
      |> compact_payload()
    end
  end

  defp record_review_request(socket, payload, opts) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)

    record_review_request_fn(opts).(
      organization_id,
      mission_id,
      dashboard_id,
      payload,
      DashboardActionContext.actor_opts(socket)
    )
  end

  defp record_review_resolution(socket, payload, opts) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)

    record_review_resolution_fn(opts).(
      organization_id,
      mission_id,
      dashboard_id,
      payload,
      DashboardActionContext.actor_opts(socket)
    )
  end

  defp review_params(%{"review" => params}) when is_map(params), do: params
  defp review_params(params) when is_map(params), do: params

  defp bulk_decision_params(params) do
    params = review_params(params)

    with decision when is_binary(decision) <- present_text(Map.get(params, "decision")),
         request_event_id when is_binary(request_event_id) <-
           present_text(Map.get(params, "source_request_event_id")) do
      {:ok,
       %{
         "decision" => decision,
         "source_request_event_id" => request_event_id,
         "confirmed" => present_text(Map.get(params, "confirmed")),
         "decision_reason" => present_text(Map.get(params, "decision_reason"))
       }}
    else
      nil -> {:error, :missing_review_request}
      _value -> {:error, :missing_review_request}
    end
  end

  defp confirm_bulk_decision(%{"confirmed" => confirmed})
       when confirmed in ["confirmed", "true", "on"],
       do: :ok

  defp confirm_bulk_decision(_params), do: {:error, :bulk_decision_not_confirmed}

  defp review_request_event(socket, request_event_id) do
    socket.assigns
    |> Map.get(:dashboard_lifecycle_events, [])
    |> Enum.find(fn event ->
      event_id(event) == request_event_id and
        event_type(event) in [
          :comparison_review_requested,
          "comparison_review_requested"
        ]
    end)
    |> case do
      nil -> {:error, :comparison_review_request_not_found}
      event -> {:ok, event}
    end
  end

  defp ensure_review_open(request_event, socket) do
    source_event_id = event_id(request_event)

    socket.assigns
    |> Map.get(:dashboard_lifecycle_events, [])
    |> Enum.any?(fn event ->
      event_type(event) in [:comparison_review_resolved, "comparison_review_resolved"] and
        event
        |> event_payload()
        |> payload_value("source_request_event_id")
        |> Kernel.==(source_event_id)
    end)
    |> case do
      true -> {:error, :comparison_review_already_resolved}
      false -> :ok
    end
  end

  defp bulk_decision_source_context(request_event) do
    request_event
    |> event_payload()
    |> source_context_candidates()
    |> Enum.find(&source_context_complete?/1)
    |> case do
      nil -> {:error, :missing_bulk_decision_source_context}
      context -> {:ok, context}
    end
  end

  defp source_context_candidates(payload) when is_map(payload) do
    open_findings = payload_value(payload, "open_findings")
    findings = payload_value(open_findings, "findings") || []

    [
      payload_value(open_findings, "runtime_query"),
      payload_value(payload, "runtime_query")
    ] ++ Enum.flat_map(findings, &finding_source_contexts/1)
  end

  defp source_context_candidates(_payload), do: []

  defp finding_source_contexts(finding) when is_map(finding) do
    [
      payload_value(finding, "primary_data_link"),
      payload_value(finding, "compare_data_link")
    ]
    |> Enum.map(&link_data_context/1)
  end

  defp finding_source_contexts(_finding), do: []

  defp link_data_context(link) when is_map(link) do
    link
    |> payload_value("context")
    |> payload_value("data")
  end

  defp link_data_context(_link), do: nil

  defp source_context_complete?(context) when is_map(context) do
    Enum.all?(
      ["realm", "data_source_id", "source_binding_id"],
      &(context |> payload_value(&1) |> present_text())
    )
  end

  defp source_context_complete?(_context), do: false

  defp bulk_decision_items(request_event) do
    items =
      request_event
      |> event_payload()
      |> payload_value("open_findings")
      |> payload_value("findings")
      |> case do
        findings when is_list(findings) -> findings
        _findings -> []
      end
      |> Enum.map(&bulk_decision_item/1)
      |> Enum.reject(&is_nil/1)

    if items == [], do: {:error, :no_bulk_decision_items}, else: {:ok, items}
  end

  defp bulk_decision_item(finding) when is_map(finding) do
    observation_identity_id =
      payload_value(finding, "observation_identity_id") ||
        payload_value(finding, "primary_observation_identity_id") ||
        payload_value(finding, "compare_observation_identity_id")

    cond do
      is_nil(present_text(observation_identity_id)) ->
        nil

      payload_value(finding, "decision_status") == "applied" ->
        nil

      true ->
        %{
          observation_identity_id: observation_identity_id,
          evidence_ref: %{
            "kind" => "dashboard_comparison_review_finding",
            "placement_id" => payload_value(finding, "placement_id"),
            "comparison_finding" => comparison_finding_evidence(finding)
          }
        }
    end
  end

  defp bulk_decision_item(_finding), do: nil

  defp comparison_finding_evidence(finding) do
    finding
    |> Map.take([
      "placement_id",
      "widget_id",
      "title",
      "state",
      "decision_status",
      "observation_identity_id",
      "primary_observation_identity_id",
      "compare_observation_identity_id",
      "primary_sample_id",
      "compare_sample_id",
      "primary_observation_id",
      "compare_observation_id",
      "primary_revision",
      "compare_revision",
      "primary_data_view",
      "compare_data_view"
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp bulk_decision_attrs(socket, request_event, source_context, params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.current_mission
    user_id = user_id(scope)
    request_event_id = event_id(request_event)

    %{
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      realm: payload_value(source_context, "realm"),
      data_source_id: payload_value(source_context, "data_source_id"),
      binding_id: payload_value(source_context, "source_binding_id"),
      correction_workflow_id: request_event_id,
      decision_reason: params["decision_reason"] || "dashboard_comparison_review_mark_conflict",
      authority: "dashboard_operator",
      requested_by: "dashboard_comparison_review",
      selection_kind: "open_comparison_findings",
      operator_id: user_id,
      actor_id: user_id,
      actor_kind: "operator",
      evidence_ref: %{
        "kind" => "dashboard_comparison_review",
        "id" => request_event_id,
        "source_panel" => "review_activity",
        "request_kind" => request_event |> event_payload() |> payload_value("request_kind")
      }
    }
  end

  defp user_id(%{user: %{id: id}}) when is_binary(id), do: id
  defp user_id(%{user: %{user_id: id}}) when is_binary(id), do: id
  defp user_id(_scope), do: nil

  defp bulk_decision_message(%{applied: applied, failed: 0}) do
    "Comparison review decisions applied to #{applied} findings."
  end

  defp bulk_decision_message(%{applied: applied, failed: failed}) do
    "Comparison review decisions applied to #{applied} findings; #{failed} failed."
  end

  defp bulk_decision_outcome(params, request_event, summary, items) do
    failed = summary_count(summary, :failed)

    ComparisonReviewActionOutcome.new(
      status: if(failed == 0, do: :ok, else: :degraded),
      kind: if(failed == 0, do: :info, else: :warning),
      reason:
        if(failed == 0,
          do: "comparison_review_bulk_decision_applied",
          else: "comparison_review_bulk_decision_partially_applied"
        ),
      decision: params["decision"],
      decision_reason: params["decision_reason"],
      source_request_event_id: event_id(request_event),
      workflow_id: summary_value(summary, :workflow_id) || event_id(request_event),
      requested: length(items),
      applied: summary_count(summary, :applied),
      failed: failed,
      result_event_ids: summary_event_ids(summary),
      target_event_id: event_id(request_event),
      message: bulk_decision_message(summary)
    )
  end

  defp summary_count(summary, key) when is_map(summary) do
    case summary_value(summary, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _value -> 0
    end
  rescue
    ArgumentError -> 0
  end

  defp summary_value(summary, key) when is_map(summary) do
    Map.get(summary, key, Map.get(summary, Atom.to_string(key)))
  end

  defp summary_event_ids(summary) when is_map(summary) do
    summary
    |> summary_value(:events)
    |> case do
      events when is_list(events) ->
        events
        |> Enum.map(&event_id/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join(",")

      _events ->
        summary_value(summary, :result_event_ids)
    end
  end

  defp resolution_payload(params) do
    params = review_params(params)

    case present_text(Map.get(params, "source_request_event_id")) do
      nil ->
        {:error, :missing_review_request}

      request_event_id ->
        {:ok,
         %{
           "schema" => @resolution_schema,
           "request_kind" => "comparison_open_findings_review",
           "source" => "dashboard_activity",
           "source_request_event_id" => request_event_id,
           "disposition" => present_text(Map.get(params, "disposition")) || "review_completed",
           "resolution_reason" => present_text(Map.get(params, "resolution_reason")),
           "selected_placement_id" => present_text(Map.get(params, "selected_placement_id")),
           "affected_placement_ids" => placement_ids(Map.get(params, "affected_placement_ids"))
         }}
        |> compact_payload()
    end
  end

  defp compact_payload({:ok, payload}) do
    {:ok,
     Enum.reduce(payload, %{}, fn
       {_key, nil}, acc -> acc
       {_key, []}, acc -> acc
       {key, value}, acc -> Map.put(acc, key, value)
     end)}
  end

  defp open_count(open_findings, findings) do
    case get_in(open_findings, ["comparison", "open_count"]) do
      count when is_integer(count) and count >= 0 -> count
      _value -> length(findings)
    end
  end

  defp open_placement_ids(open_findings, findings) do
    case get_in(open_findings, ["comparison", "open_placement_ids"]) do
      ids when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      _value -> findings |> Enum.map(&Map.get(&1, "placement_id")) |> Enum.filter(&is_binary/1)
    end
  end

  defp placement_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_value), do: []

  defp record_review_request_fn(opts) do
    Keyword.get(
      opts,
      :record_dashboard_comparison_review_request,
      &Dashboards.record_dashboard_comparison_review_request/5
    )
  end

  defp record_review_resolution_fn(opts) do
    Keyword.get(
      opts,
      :record_dashboard_comparison_review_resolution,
      &Dashboards.record_dashboard_comparison_review_resolution/5
    )
  end

  defp bulk_decision_fn(opts) do
    Keyword.get(
      opts,
      :apply_comparison_review_bulk_decision,
      &Cadence.apply_telemetry_observation_identity_decisions/4
    )
  end

  defp bulk_decision_opts(opts) do
    Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache, :decision_opts])
  end

  defp event_id(event), do: event_value(event, :dashboard_lifecycle_event_id)
  defp event_type(event), do: event_value(event, :event_type)
  defp event_payload(event), do: event_value(event, :payload) || %{}

  defp event_value(event, key) when is_map(event) and is_atom(key) do
    Map.get(event, key) || Map.get(event, Atom.to_string(key))
  end

  defp event_value(_event, _key), do: nil

  defp payload_value(payload, key) when is_map(payload) and is_binary(key) do
    Map.get(payload, key) || Map.get(payload, atom_key(key))
  end

  defp payload_value(_payload, _key), do: nil

  defp atom_key("open_findings"), do: :open_findings
  defp atom_key("findings"), do: :findings
  defp atom_key("runtime_query"), do: :runtime_query
  defp atom_key("source_request_event_id"), do: :source_request_event_id
  defp atom_key("request_kind"), do: :request_kind
  defp atom_key("primary_data_link"), do: :primary_data_link
  defp atom_key("compare_data_link"), do: :compare_data_link
  defp atom_key("context"), do: :context
  defp atom_key("data"), do: :data
  defp atom_key("realm"), do: :realm
  defp atom_key("data_source_id"), do: :data_source_id
  defp atom_key("source_binding_id"), do: :source_binding_id
  defp atom_key("observation_identity_id"), do: :observation_identity_id
  defp atom_key("primary_observation_identity_id"), do: :primary_observation_identity_id
  defp atom_key("compare_observation_identity_id"), do: :compare_observation_identity_id
  defp atom_key("decision_status"), do: :decision_status
  defp atom_key("placement_id"), do: :placement_id
  defp atom_key(_key), do: nil

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil

  defp flash(socket, kind, message, opts) do
    DashboardActionContext.flash(socket, kind, message, opts)
  end
end
