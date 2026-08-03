defmodule CadenceWeb.OpsTelemetryExploreLive do
  alias Cadence.Ops.PointCatalog, as: PointCatalog

  alias Cadence.Reads.Telemetry, as: TelemetryReads
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias CadenceWeb.OpsTelemetryExploreComponents

  @default_limit 100
  @max_limit 1_000
  @query_params [
    "point_id",
    "spacecraft_id",
    "scope_kind",
    "scope_id",
    "time_mode",
    "time_axis",
    "from",
    "to",
    "replay_run_id",
    "order",
    "limit",
    "selection_view",
    "validity_state",
    "realm",
    "logical_source",
    "data_source_id",
    "source_binding_id",
    "source_dashboard_id",
    "sample_id",
    "selected_time",
    "question",
    "limit_mode"
  ]

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    points = PointCatalog.list_points(scope.organization_id, mission.mission_id)

    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    data_sources = DataSources.list_data_sources(scope.organization_id, mission.mission_id)
    data_bindings = DataSources.list_data_bindings(scope.organization_id, mission.mission_id)

    data_realms =
      DataSources.list_data_realms(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Explore")
     |> assign(:ops_nav_item, :explore)
     |> assign(:points, points)
     |> assign(:spacecraft, spacecraft)
     |> assign(:data_sources, data_sources)
     |> assign(:data_bindings, data_bindings)
     |> assign(:data_realms, data_realms)
     |> assign(:explore_context, explore_context(%{}))
     |> assign(:filter_form, to_form(%{}, as: :explore))
     |> assign(
       :add_to_dashboard_form,
       to_form(%{"dashboard_id" => "", "widget_type" => "time_series"},
         as: :add_to_dashboard
       )
     )
     |> assign(:point, nil)
     |> assign(:samples, [])
     |> assign(:selected_sample, nil)
     |> assign(:selected_sample_state, "none")
     |> assign(:source_context, source_context(explore_context(%{}), [], []))
     |> assign(:history_diagnostics, history_diagnostics([], %{}, explore_context(%{}), false))
     |> assign(:investigation_path, telemetry_explore_path(mission.mission_id, %{}))
     |> assign(
       :investigation_fingerprint,
       investigation_fingerprint(telemetry_explore_path(mission.mission_id, %{}))
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    context = explore_context(params)
    canonical_query = investigation_query(context)

    if incoming_query(params) != canonical_query do
      {:noreply,
       push_patch(socket,
         to: telemetry_explore_path(mission.mission_id, canonical_query),
         replace: true
       )}
    else
      point = find_point(socket.assigns.points, context.point_id)
      {samples, diagnostics} = load_samples(scope.organization_id, mission.mission_id, context)
      selected_sample = selected_sample(samples, context.sample_id)
      selected_sample_state = selected_sample_state(context, selected_sample)

      source_context =
        source_context(context, socket.assigns.data_sources, socket.assigns.data_bindings)

      investigation_path = telemetry_explore_path(mission.mission_id, canonical_query)

      {:noreply,
       socket
       |> assign(:explore_context, context)
       |> assign(:filter_form, to_form(filter_params(context), as: :explore))
       |> assign(:point, point)
       |> assign(:samples, samples)
       |> assign(:selected_sample, selected_sample)
       |> assign(:selected_sample_state, selected_sample_state)
       |> assign(:source_context, source_context)
       |> assign(:history_diagnostics, diagnostics)
       |> assign(:investigation_path, investigation_path)
       |> assign(:investigation_fingerprint, investigation_fingerprint(investigation_path))}
    end
  end

  @impl true
  def handle_event("apply_filters", %{"explore" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    query = params |> normalize_filter_params() |> explore_context() |> investigation_query()

    {:noreply, push_patch(socket, to: telemetry_explore_path(mission_id, query))}
  end

  def handle_event("apply_filters", _params, socket), do: {:noreply, socket}

  def handle_event("apply_question", %{"question" => question}, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    query =
      question
      |> question_query(socket.assigns.points)
      |> maybe_preserve_source_dashboard(socket.assigns.explore_context.source_dashboard_id)

    {:noreply, push_patch(socket, to: telemetry_explore_path(mission_id, query))}
  end

  def handle_event("apply_question", _params, socket), do: {:noreply, socket}

  def handle_event(
        "add_to_dashboard",
        %{"add_to_dashboard" => params},
        %{assigns: %{dashboard_author?: true}} = socket
      ) do
    with dashboard_id when is_binary(dashboard_id) <- text_param(params["dashboard_id"]),
         true <- dashboard_target?(socket.assigns.ops_dashboards, dashboard_id),
         point_id when is_binary(point_id) <- socket.assigns.explore_context.point_id do
      mission_id = socket.assigns.current_mission.mission_id
      query = dashboard_candidate_query(socket.assigns.explore_context, params, point_id)

      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit?#{query}"
       )}
    else
      _invalid ->
        {:noreply, put_flash(socket, :error, "Choose a dashboard and telemetry point first.")}
    end
  end

  def handle_event("add_to_dashboard", _params, socket), do: {:noreply, socket}

  def handle_event("clear_selected_sample", _params, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    query =
      socket.assigns.explore_context
      |> Map.merge(%{sample_id: nil, selected_time: nil, source_dashboard_id: nil})
      |> investigation_query()

    {:noreply, push_patch(socket, to: telemetry_explore_path(mission_id, query))}
  end

  @impl true
  def render(assigns), do: OpsTelemetryExploreComponents.page(assigns)

  defp explore_context(params) do
    %{
      point_id: text_param(params["point_id"]),
      sample_id: text_param(params["sample_id"]),
      spacecraft_id: text_param(params["spacecraft_id"]),
      scope_kind: text_param(params["scope_kind"]),
      scope_id: text_param(params["scope_id"]),
      time_mode: normalize_time_mode(params["time_mode"]),
      time_axis: text_param(params["time_axis"]),
      from: effective_from(params),
      to: effective_to(params),
      from_text: text_param(params["from"]),
      to_text: text_param(params["to"]),
      realm: text_param(params["realm"]),
      logical_source: parse_logical_source(params["logical_source"]),
      logical_source_text: logical_source_text(params["logical_source"]),
      data_source_id: text_param(params["data_source_id"]),
      source_binding_id: text_param(params["source_binding_id"]),
      source_dashboard_id: text_param(params["source_dashboard_id"]),
      selected_time: text_param(params["selected_time"]),
      replay_run_id: text_param(params["replay_run_id"]),
      question: normalize_question(params["question"]),
      limit_mode: text_param(params["limit_mode"]),
      limit: parse_limit(params["limit"]),
      limit_text: limit_text(params["limit"]),
      order: parse_order(params["order"]),
      order_text: order_text(params["order"]),
      selection_view: parse_selection_view(params["selection_view"]),
      selection_view_text: selection_view_text(params["selection_view"]),
      validity_state: parse_validity_state(params["validity_state"]),
      validity_state_text: validity_state_text(params["validity_state"])
    }
  end

  defp find_point(_points, nil), do: nil
  defp find_point(points, point_id), do: Enum.find(points, &(&1.point_id == point_id))

  defp selected_sample(_samples, nil), do: nil
  defp selected_sample(samples, sample_id), do: Enum.find(samples, &(&1.sample_id == sample_id))

  defp selected_sample_state(%{sample_id: nil}, _selected_sample), do: "none"
  defp selected_sample_state(_context, nil), do: "missing"
  defp selected_sample_state(_context, _selected_sample), do: "matched"

  defp source_context(context, sources, bindings) do
    context
    |> default_source_context()
    |> resolve_source_context(sources, bindings)
  end

  defp default_source_context(context) do
    %{
      state: "none",
      data_source_id: context.data_source_id,
      source_binding_id: context.source_binding_id,
      logical_source: context.logical_source_text,
      realm: context.realm,
      matched_data_source_id: nil,
      matched_source_binding_id: nil
    }
  end

  defp resolve_source_context(source_context, sources, bindings) do
    if source_context_requested?(source_context) do
      source_context
      |> Map.put(:state, "pending")
      |> resolve_requested_source_context(sources, bindings)
    else
      source_context
    end
  end

  defp source_context_requested?(source_context) do
    Enum.any?(
      [source_context.data_source_id, source_context.source_binding_id, source_context.realm],
      &present?/1
    )
  end

  defp resolve_requested_source_context(source_context, sources, bindings) do
    sources_by_id = Map.new(sources, &{&1.data_source_id, &1})
    requested_source = requested_source(source_context, sources_by_id)
    requested_binding = requested_binding(source_context, bindings)
    context_binding = context_binding(source_context, bindings)
    matched_binding = first_present(requested_binding, context_binding)

    matched_source =
      first_present(requested_source, binding_source(matched_binding, sources_by_id))

    if source_context_matched?(
         source_context,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
      %{
        source_context
        | state: "matched",
          matched_data_source_id: matched_data_source_id(matched_source),
          matched_source_binding_id: matched_source_binding_id(matched_binding)
      }
    else
      %{source_context | state: "missing"}
    end
  end

  defp requested_source(%{data_source_id: nil}, _sources_by_id), do: nil

  defp requested_source(source_context, sources_by_id),
    do: Map.get(sources_by_id, source_context.data_source_id)

  defp requested_binding(%{source_binding_id: nil}, _bindings), do: nil

  defp requested_binding(source_context, bindings),
    do: find_binding(bindings, source_context.source_binding_id)

  defp context_binding(source_context, bindings),
    do: Enum.find(bindings, &binding_matches_source_context?(&1, source_context))

  defp binding_matches_source_context?(%DataBinding{} = binding, source_context) do
    binding_matches_logical_source?(binding, source_context) and
      binding_matches_realm?(binding, source_context) and
      binding_matches_data_source?(binding, source_context)
  end

  defp binding_matches_logical_source?(%DataBinding{} = binding, source_context),
    do: normalize_string(binding.logical_source) == source_context.logical_source

  defp binding_matches_realm?(_binding, %{realm: nil}), do: true

  defp binding_matches_realm?(%DataBinding{} = binding, source_context),
    do: normalize_string(binding.realm) == source_context.realm

  defp binding_matches_data_source?(_binding, %{data_source_id: nil}), do: true

  defp binding_matches_data_source?(%DataBinding{} = binding, source_context),
    do: binding.data_source_id == source_context.data_source_id

  defp binding_source(nil, _sources_by_id), do: nil

  defp binding_source(%DataBinding{} = binding, sources_by_id),
    do: Map.get(sources_by_id, binding.data_source_id)

  defp source_context_matched?(
         source_context,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
    source_context_requested?(source_context) and
      requested_source_found?(source_context, requested_source) and
      requested_binding_found?(source_context, requested_binding) and
      binding_source_consistent?(source_context, matched_binding) and
      source_context_consistent?(source_context, matched_binding) and
      source_or_binding_found?(matched_source, matched_binding)
  end

  defp requested_source_found?(%{data_source_id: nil}, _requested_source), do: true
  defp requested_source_found?(_source_context, %DataSource{}), do: true
  defp requested_source_found?(_source_context, _requested_source), do: false

  defp requested_binding_found?(%{source_binding_id: nil}, _requested_binding), do: true
  defp requested_binding_found?(_source_context, %DataBinding{}), do: true
  defp requested_binding_found?(_source_context, _requested_binding), do: false

  defp binding_source_consistent?(%{data_source_id: nil}, _binding), do: true
  defp binding_source_consistent?(_source_context, nil), do: true

  defp binding_source_consistent?(source_context, %DataBinding{} = binding),
    do: binding.data_source_id == source_context.data_source_id

  defp source_context_consistent?(source_context, %DataBinding{} = binding),
    do: binding_matches_source_context?(binding, source_context)

  defp source_context_consistent?(%{realm: nil, source_binding_id: nil}, nil), do: true
  defp source_context_consistent?(_source_context, nil), do: false

  defp source_or_binding_found?(nil, nil), do: false
  defp source_or_binding_found?(_source, _binding), do: true

  defp matched_data_source_id(nil), do: nil
  defp matched_data_source_id(%DataSource{} = source), do: source.data_source_id

  defp matched_source_binding_id(nil), do: nil
  defp matched_source_binding_id(%DataBinding{} = binding), do: binding.binding_id

  defp find_binding(bindings, binding_id), do: Enum.find(bindings, &(&1.binding_id == binding_id))

  defp first_present(nil, fallback), do: fallback
  defp first_present(value, _fallback), do: value

  defp load_samples(_organization_id, _mission_id, %{point_id: nil} = context) do
    {[], history_diagnostics([], %{}, context, false)}
  end

  defp load_samples(organization_id, mission_id, context) do
    opts =
      [order: context.order, limit: context.limit]
      |> maybe_put(:spacecraft_id, context.spacecraft_id)
      |> maybe_put(:from_receipt_time, context.from)
      |> maybe_put(:to_receipt_time, context.to)
      |> maybe_put(:selection_view, context.selection_view)
      |> maybe_put(:validity_state, context.validity_state)
      |> maybe_put(:realm, context.realm)
      |> maybe_put(:data_source_id, context.data_source_id)
      |> maybe_put(:binding_id, context.source_binding_id)
      |> maybe_put(:replay_run_id, context.replay_run_id)

    case TelemetryReads.sample_history_result(
           organization_id,
           mission_id,
           context.point_id,
           opts
         ) do
      {:ok, %{samples: samples, diagnostics: diagnostics}} ->
        physical_exists? =
          samples != [] || physical_samples_exist?(organization_id, mission_id, context)

        {samples, history_diagnostics(samples, diagnostics, context, physical_exists?)}

      {:error, reason} ->
        {[], history_diagnostics([], %{error: inspect(reason)}, context, false)}
    end
  end

  defp physical_samples_exist?(organization_id, mission_id, context) do
    opts =
      [
        order: context.order,
        limit: 1,
        selection_view: :all_revisions
      ]
      |> maybe_put(:spacecraft_id, context.spacecraft_id)
      |> maybe_put(:from_receipt_time, context.from)
      |> maybe_put(:to_receipt_time, context.to)
      |> maybe_put(:realm, context.realm)
      |> maybe_put(:data_source_id, context.data_source_id)
      |> maybe_put(:binding_id, context.source_binding_id)
      |> maybe_put(:replay_run_id, context.replay_run_id)

    case TelemetryReads.sample_history_result(
           organization_id,
           mission_id,
           context.point_id,
           opts
         ) do
      {:ok, %{samples: [_ | _]}} -> true
      _other -> false
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp history_diagnostics(samples, diagnostics, context, physical_exists?) do
    %{
      requested_logical_limit:
        diagnostics_value(diagnostics, :requested_logical_limit) || context.limit,
      logical_selected_count:
        diagnostics_value(diagnostics, :logical_selected_count) || length(samples),
      physical_candidate_count:
        diagnostics_value(diagnostics, :physical_candidate_count) ||
          physical_count(samples, physical_exists?),
      physical_candidate_limit: diagnostics_value(diagnostics, :physical_candidate_limit),
      effective_selection?:
        diagnostics_value(diagnostics, :effective_selection?) || effective_selection?(context),
      candidate_window_exhausted?:
        diagnostics_value(diagnostics, :candidate_window_exhausted?) || false,
      physical_samples_exist?: physical_exists?,
      selection_view: context.selection_view_text,
      validity_state: context.validity_state_text,
      error: diagnostics_value(diagnostics, :error)
    }
  end

  defp diagnostics_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp diagnostics_value(_map, _key), do: nil

  defp physical_count(samples, true), do: max(length(samples), 1)
  defp physical_count(_samples, false), do: 0

  defp effective_selection?(%{selection_view: :canonical}), do: true
  defp effective_selection?(_context), do: false

  defp filter_params(context) do
    %{
      "point_id" => blank(context.point_id),
      "spacecraft_id" => blank(context.spacecraft_id),
      "scope_kind" => blank(context.scope_kind),
      "scope_id" => blank(context.scope_id),
      "time_mode" => context.time_mode,
      "time_axis" => blank(context.time_axis),
      "from" => blank(context.from_text),
      "to" => blank(context.to_text),
      "replay_run_id" => blank(context.replay_run_id),
      "order" => context.order_text,
      "limit" => context.limit_text,
      "selection_view" => context.selection_view_text,
      "validity_state" => context.validity_state_text,
      "realm" => blank(context.realm),
      "logical_source" => context.logical_source_text,
      "data_source_id" => blank(context.data_source_id),
      "source_binding_id" => blank(context.source_binding_id),
      "source_dashboard_id" => blank(context.source_dashboard_id),
      "sample_id" => blank(context.sample_id),
      "selected_time" => blank(context.selected_time),
      "question" => blank(context.question),
      "limit_mode" => blank(context.limit_mode)
    }
  end

  defp normalize_filter_params(params) do
    time_mode = normalize_time_mode(params["time_mode"])

    params
    |> Map.take(@query_params)
    |> Map.put("time_mode", time_mode)
    |> Map.put("from", if(time_mode in ["archive", "replay_run"], do: params["from"], else: nil))
    |> Map.put("to", if(time_mode in ["archive", "replay_run"], do: params["to"], else: nil))
    |> Map.put("order", order_text(params["order"]))
    |> Map.put("limit", limit_text(params["limit"]))
    |> Map.put("selection_view", selection_view_text(params["selection_view"]))
    |> Map.put("validity_state", validity_state_text(params["validity_state"]))
    |> Map.put("logical_source", logical_source_text(params["logical_source"]))
  end

  defp investigation_query(context) do
    %{
      "point_id" => context.point_id,
      "spacecraft_id" => context.spacecraft_id,
      "scope_kind" => context.scope_kind,
      "scope_id" => context.scope_id,
      "time_mode" => non_default(context.time_mode, "latest"),
      "time_axis" => context.time_axis,
      "from" =>
        if(context.time_mode in ["archive", "replay_run"], do: context.from_text, else: nil),
      "to" => if(context.time_mode in ["archive", "replay_run"], do: context.to_text, else: nil),
      "replay_run_id" => context.replay_run_id,
      "order" => non_default(context.order_text, "desc"),
      "limit" => non_default(context.limit_text, Integer.to_string(@default_limit)),
      "selection_view" => non_default(context.selection_view_text, "canonical"),
      "validity_state" => non_default(context.validity_state_text, ""),
      "realm" => context.realm,
      "logical_source" => non_default(context.logical_source_text, "telemetry"),
      "data_source_id" => context.data_source_id,
      "source_binding_id" => context.source_binding_id,
      "source_dashboard_id" => context.source_dashboard_id,
      "sample_id" => context.sample_id,
      "selected_time" => context.selected_time,
      "question" => context.question,
      "limit_mode" => context.limit_mode
    }
    |> compact_query()
  end

  defp incoming_query(params) do
    params
    |> Map.take(@query_params)
    |> compact_query()
  end

  defp non_default(value, value), do: nil
  defp non_default(value, _default), do: value

  defp telemetry_explore_path(mission_id, query) when map_size(query) == 0 do
    ~p"/missions/#{mission_id}/ops/explore"
  end

  defp telemetry_explore_path(mission_id, query) do
    ~p"/missions/#{mission_id}/ops/explore?#{query}"
  end

  defp investigation_fingerprint(path) do
    :sha256
    |> :crypto.hash(path)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _reason} ->
        case DateTime.from_iso8601(value <> "Z") do
          {:ok, datetime, _offset} -> datetime
          {:error, _reason} -> nil
        end
    end
  end

  defp effective_from(%{"time_mode" => "last_5m"}),
    do: DateTime.utc_now() |> DateTime.add(-5 * 60, :second)

  defp effective_from(%{"time_mode" => "last_15m"}),
    do: DateTime.utc_now() |> DateTime.add(-15 * 60, :second)

  defp effective_from(%{"time_mode" => "last_1h"}),
    do: DateTime.utc_now() |> DateTime.add(-60 * 60, :second)

  defp effective_from(%{"time_mode" => "archive", "from" => from}), do: parse_datetime(from)
  defp effective_from(%{"time_mode" => "replay_run", "from" => from}), do: parse_datetime(from)
  defp effective_from(_params), do: nil

  defp effective_to(%{"time_mode" => "archive", "to" => to}), do: parse_datetime(to)
  defp effective_to(%{"time_mode" => "replay_run", "to" => to}), do: parse_datetime(to)
  defp effective_to(_params), do: nil

  defp normalize_time_mode("live"), do: "latest"

  defp normalize_time_mode(value)
       when value in ["latest", "last_5m", "last_15m", "last_1h", "archive", "replay_run"],
       do: value

  defp normalize_time_mode(_value), do: "latest"

  defp parse_order("asc"), do: :asc
  defp parse_order(_value), do: :desc

  defp order_text("asc"), do: "asc"
  defp order_text(_value), do: "desc"

  defp parse_limit(value), do: limit_text(value) |> String.to_integer()

  defp limit_text(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 -> limit |> min(@max_limit) |> Integer.to_string()
      _invalid -> Integer.to_string(@default_limit)
    end
  end

  defp limit_text(value) when is_integer(value) and value > 0 do
    value |> min(@max_limit) |> Integer.to_string()
  end

  defp limit_text(_value), do: Integer.to_string(@default_limit)

  defp parse_selection_view(value) do
    case selection_view_text(value) do
      "all_revisions" -> :all_revisions
      "as_recorded" -> :as_recorded
      "recomputed" -> :recomputed
      _canonical -> :canonical
    end
  end

  defp selection_view_text(value)
       when value in ["canonical", "all_revisions", "as_recorded", "recomputed"],
       do: value

  defp selection_view_text(_value), do: "canonical"

  defp parse_validity_state(value) do
    case validity_state_text(value) do
      "" -> nil
      "canonical" -> :canonical
      "duplicate" -> :duplicate
      "conflict" -> :conflict
      "superseded" -> :superseded
      "advisory" -> :advisory
    end
  end

  defp validity_state_text(value)
       when value in ["", "canonical", "duplicate", "conflict", "superseded", "advisory"],
       do: value

  defp validity_state_text(_value), do: ""

  defp parse_logical_source("limits"), do: :limits
  defp parse_logical_source("events"), do: :events
  defp parse_logical_source("operational_observables"), do: :operational_observables
  defp parse_logical_source(_value), do: :telemetry

  defp logical_source_text(value)
       when value in ["telemetry", "limits", "events", "operational_observables"],
       do: value

  defp logical_source_text(_value), do: "telemetry"

  defp normalize_question(value)
       when value in ["recent_anomalies", "what_changed", "missing_history", "link_degradation"],
       do: value

  defp normalize_question(_value), do: nil

  defp question_query("recent_anomalies", points) do
    %{
      "question" => "recent_anomalies",
      "point_id" => default_point_id(points),
      "time_mode" => "last_15m",
      "selection_view" => "all_revisions"
    }
    |> compact_query()
  end

  defp question_query("what_changed", points) do
    %{
      "question" => "what_changed",
      "point_id" => default_point_id(points),
      "time_mode" => "last_1h",
      "selection_view" => "all_revisions"
    }
    |> compact_query()
  end

  defp question_query("missing_history", points) do
    %{
      "question" => "missing_history",
      "point_id" => default_point_id(points),
      "time_mode" => "last_1h",
      "selection_view" => "all_revisions"
    }
    |> compact_query()
  end

  defp question_query("link_degradation", _points) do
    %{
      "question" => "link_degradation",
      "time_mode" => "last_1h",
      "logical_source" => "operational_observables"
    }
  end

  defp question_query(_question, _points), do: %{}

  defp default_point_id([point | _rest]), do: point.point_id
  defp default_point_id(_points), do: nil

  defp maybe_preserve_source_dashboard(query, nil), do: query

  defp maybe_preserve_source_dashboard(query, dashboard_id),
    do: Map.put(query, "source_dashboard_id", dashboard_id)

  defp dashboard_target?(dashboards, dashboard_id) do
    Enum.any?(dashboards, fn dashboard ->
      dashboard.dashboard_id == dashboard_id and dashboard.lifecycle_state == "active"
    end)
  end

  defp dashboard_candidate_query(context, params, point_id) do
    widget_type =
      if params["widget_type"] in ["value_tile", "time_series"],
        do: params["widget_type"],
        else: "time_series"

    %{
      "candidate_source" => "explore",
      "candidate_point_id" => point_id,
      "candidate_title" => text_param(params["title"]) || default_candidate_title(point_id),
      "candidate_widget_type" => widget_type,
      "candidate_spacecraft_id" => context.spacecraft_id,
      "candidate_realm" => context.realm,
      "candidate_data_view" => context.selection_view_text,
      "candidate_data_source_id" => context.data_source_id,
      "candidate_source_binding_id" => context.source_binding_id,
      "time_mode" => context.time_mode,
      "time_axis" => context.time_axis,
      "from" => context.from_text,
      "to" => context.to_text,
      "replay_run_id" => context.replay_run_id,
      "data_view" => context.selection_view_text,
      "realm" => context.realm,
      "data_source_id" => context.data_source_id,
      "source_binding_id" => context.source_binding_id,
      "scope_kind" => context.scope_kind,
      "scope_id" => context.scope_id,
      "limit_mode" => context.limit_mode
    }
    |> compact_query()
  end

  defp default_candidate_title(point_id) do
    point_id
    |> String.replace(["_", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp text_param(nil), do: nil
  defp text_param(""), do: nil
  defp text_param(value) when is_binary(value), do: value
  defp text_param(value), do: to_string(value)

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: to_string(value)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp blank(nil), do: ""
  defp blank(value), do: value
end
