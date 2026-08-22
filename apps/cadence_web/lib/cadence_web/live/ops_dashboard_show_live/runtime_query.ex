defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQuery do
  @moduledoc false

  alias Cadence.Dashboards.{Document, ScopeContext, TimeRange}

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.MarkerCategories
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAssigns
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQueryParams

  @supported_limit_modes ["observed", "current", "recomputed", "compare"]
  @supported_data_views ["canonical", "as_recorded", "all_revisions", "recomputed"]

  def runtime_context_from_params(
        params,
        current_scope,
        mission,
        spacecraft,
        data_realms,
        data_bindings,
        document,
        opts \\ []
      ) do
    scope_context =
      runtime_scope_context_from_params(
        params,
        current_scope,
        mission,
        spacecraft,
        document,
        opts
      )

    {scope_kind, scope_id, scope_ids} = scope_identity(scope_context)
    spacecraft_id = ScopeContext.scope_id(scope_context, :spacecraft)
    default_data_context = default_data_context(document, data_realms, data_bindings)
    default_realm = default_data_context["realm"] || default_data_realm(data_realms)

    %{
      mode: time_mode,
      from: time_from,
      to: time_to,
      from_value: from_value,
      to_value: to_value,
      axis: time_axis,
      replay_run_id: replay_run_id,
      validation: time_validation,
      window_seconds: window_seconds
    } = validate_time_params(params)

    realm =
      params
      |> Map.get("realm")
      |> validate_member(data_realms, default_realm(time_mode, data_realms, default_realm))

    data_view =
      params
      |> Map.get("data_view")
      |> validate_member(@supported_data_views, default_data_view(default_data_context))

    compare_data_view =
      params
      |> Map.get("compare_data_view")
      |> compare_data_view(data_view)

    source_context =
      source_context_from_params(params, realm, data_bindings, default_data_context)
      |> put_data_view(data_view)
      |> maybe_put("replay_run_id", replay_run_id)

    telemetry_source_context = telemetry_source_context(source_context)

    limit_mode = validate_member(params["limit_mode"], @supported_limit_modes, "observed")
    limit_mode_fallback = limit_mode_fallback(params["limit_mode"], limit_mode)

    %{
      scope_kind: scope_kind,
      scope_id: scope_id,
      scope_ids: scope_ids,
      scope_context: scope_context,
      spacecraft_id: spacecraft_id,
      time_mode: time_mode,
      time_from: time_from,
      time_to: time_to,
      time_axis: time_axis,
      replay_run_id: replay_run_id,
      time_validation: time_validation,
      realm: realm,
      data_view: data_view,
      compare_data_view: compare_data_view,
      data_source_id: Map.get(telemetry_source_context, "data_source_id"),
      source_binding_id: Map.get(telemetry_source_context, "source_binding_id"),
      limit_mode: limit_mode,
      limit_mode_fallback: limit_mode_fallback,
      hidden_marker_categories: hidden_marker_categories(params),
      time_context:
        time_context(time_mode, time_axis, from_value, to_value, replay_run_id, window_seconds),
      data_context: source_context,
      limit_context: %{"semantics_mode" => limit_mode}
    }
    |> RuntimeContext.new()
  end

  def normalize_runtime_query(params, data_realms, data_bindings, document) do
    default_data_context = default_data_context(document, data_realms, data_bindings)
    default_realm = default_data_context["realm"] || default_data_realm(data_realms)

    time_params = validate_time_params(params)

    realm =
      params
      |> Map.get("realm")
      |> validate_member(data_realms, default_realm(time_params.mode, data_realms, default_realm))

    data_view =
      params
      |> Map.get("data_view")
      |> validate_member(@supported_data_views, default_data_view(default_data_context))

    compare_data_view =
      params
      |> Map.get("compare_data_view")
      |> compare_data_view(data_view)

    source_context =
      source_context_from_params(params, realm, data_bindings, default_data_context)
      |> put_data_view(data_view)

    telemetry_source_context = telemetry_source_context(source_context)

    limit_mode = validate_member(params["limit_mode"], @supported_limit_modes, "observed")

    %{
      "time_mode" => if(time_params.mode == "live", do: nil, else: time_params.mode),
      "from" => time_params.from,
      "to" => time_params.to,
      "time_axis" =>
        if(time_params.axis == default_time_axis(time_params.mode),
          do: nil,
          else: time_params.axis
        ),
      "replay_run_id" => time_params.replay_run_id,
      "realm" => if(realm == default_realm, do: nil, else: realm),
      "data_view" =>
        if(data_view == default_data_view(default_data_context), do: nil, else: data_view),
      "compare_data_view" => compare_data_view,
      "data_source_id" => normalized_data_source_query(params, telemetry_source_context),
      "source_binding_id" =>
        normalized_source_binding_query(params, telemetry_source_context, default_data_context),
      "limit_mode" => if(limit_mode == "observed", do: nil, else: limit_mode),
      "hidden_markers" => params |> hidden_marker_categories() |> MarkerCategories.to_param()
    }
  end

  # The Data-popover form posts the checkbox map under "markers"; direct
  # patches and URLs carry the canonical "hidden_markers" string.
  defp hidden_marker_categories(params) do
    MarkerCategories.normalize_param(params["markers"] || params["hidden_markers"])
  end

  def current_query(assigns) when is_map(assigns) do
    default_data_context =
      default_data_context(
        assigns.dashboard_document,
        assigns.dashboard_data_realms,
        assigns.dashboard_data_bindings
      )

    default_realm =
      default_data_context["realm"] || default_data_realm(assigns.dashboard_data_realms)

    default_source_binding_id = default_telemetry_source_binding_id(default_data_context)

    assigns
    |> RuntimeAssigns.runtime_query_attrs(%{
      default_realm: default_realm,
      default_data_view: default_data_view(default_data_context),
      default_source_binding_id: default_source_binding_id
    })
    |> RuntimeQueryParams.to_params()
  end

  def live_time_overrides(assigns) when is_map(assigns) do
    overrides = %{
      "time_mode" => nil,
      "time_axis" => nil,
      "from" => nil,
      "to" => nil,
      "replay_run_id" => nil
    }

    if assigns[:dashboard_time_mode] == "replay_run" do
      Map.merge(overrides, %{
        "realm" => nil,
        "data_source_id" => nil,
        "source_binding_id" => nil
      })
    else
      overrides
    end
  end

  def runtime_default_data_context(data_context) do
    data_context
    |> stringify_keys()
    |> Map.take(["realm", "source_mode", "source_contexts"])
  end

  def document_data_defaults(%Document{} = document) do
    document.defaults
    |> ensure_map()
    |> Map.get("data", Map.get(document.defaults || %{}, :data, %{}))
    |> stringify_keys()
  end

  def default_scope_context,
    do:
      ScopeContext.from_map(%{
        "primary" => %{"kind" => "spacecraft", "mode" => "context", "ids" => []}
      })

  def default_data_realm(realms) when is_list(realms) do
    if "flight" in realms do
      "flight"
    else
      case realms do
        [realm | _rest] -> realm
        [] -> "flight"
      end
    end
  end

  def default_data_context(%Document{defaults: defaults}, data_realms, data_bindings)
      when is_map(defaults) do
    defaults
    |> Map.get("data", Map.get(defaults, :data, %{}))
    |> normalize_data_context(data_realms, data_bindings)
  end

  def default_data_context(_document, data_realms, data_bindings) do
    normalize_data_context(%{}, data_realms, data_bindings)
  end

  defp runtime_scope_context_from_params(
         params,
         current_scope,
         mission,
         spacecraft,
         document,
         opts
       ) do
    case explicit_scope_context_from_params(params, current_scope, mission, spacecraft, opts) do
      nil ->
        if legacy_spacecraft_scope_param?(params) do
          legacy_spacecraft_scope_context(params, spacecraft)
        else
          document_scope_context(document) || default_scope_context()
        end

      scope_context ->
        scope_context
    end
  end

  defp explicit_scope_context_from_params(params, current_scope, mission, spacecraft, opts) do
    scope_kind = params |> Map.get("scope_kind") |> normalize_scope_kind()
    scope_ids = scope_ids_param(params)

    explicit_scope_context(scope_kind, scope_ids, current_scope, mission, spacecraft, opts)
  end

  defp scope_ids_param(params) when is_map(params) do
    case normalize_scope_ids(Map.get(params, "scope_ids")) do
      [] ->
        params
        |> Map.get("scope_id")
        |> normalize_scope_ids()

      ids ->
        ids
    end
  end

  defp normalize_scope_ids(ids) when is_list(ids) do
    ids
    |> Enum.flat_map(&normalize_scope_ids/1)
    |> Enum.uniq()
  end

  defp normalize_scope_ids(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_scope_ids(_ids), do: []

  defp explicit_scope_context(nil, _scope_ids, _current_scope, _mission, _spacecraft, _opts),
    do: nil

  defp explicit_scope_context(_scope_kind, [], _current_scope, _mission, _spacecraft, _opts),
    do: default_scope_context()

  defp explicit_scope_context(
         "spacecraft",
         scope_ids,
         _current_scope,
         _mission,
         spacecraft,
         _opts
       ) do
    spacecraft_ids =
      scope_ids
      |> Enum.map(&validate_context(&1, spacecraft))
      |> Enum.reject(&is_nil/1)

    case spacecraft_ids do
      [] -> default_scope_context()
      ids -> scope_context("spacecraft", ids)
    end
  end

  defp explicit_scope_context("mission", scope_ids, _current_scope, mission, _spacecraft, _opts) do
    if scope_ids == [mission.mission_id] do
      scope_context("mission", scope_ids)
    else
      default_scope_context()
    end
  end

  defp explicit_scope_context("contact", scope_ids, current_scope, mission, _spacecraft, opts) do
    if Enum.all?(scope_ids, &valid_contact_scope?(current_scope, mission, &1, opts)) do
      scope_context("contact", scope_ids)
    else
      default_scope_context()
    end
  end

  defp explicit_scope_context(
         scope_kind,
         scope_ids,
         current_scope,
         mission,
         _spacecraft,
         opts
       )
       when scope_kind in ["ground_station", "source_endpoint", "transport", "link"] do
    if Enum.all?(
         scope_ids,
         &valid_operational_resource_scope?(current_scope, mission, scope_kind, &1, opts)
       ) do
      scope_context(scope_kind, scope_ids)
    else
      default_scope_context()
    end
  end

  defp explicit_scope_context(
         scope_kind,
         scope_ids,
         _current_scope,
         _mission,
         _spacecraft,
         _opts
       ),
       do: scope_context(scope_kind, scope_ids)

  defp legacy_spacecraft_scope_context(params, spacecraft) do
    params
    |> Map.get("spacecraft_id", Map.get(params, "spacecraft"))
    |> validate_context(spacecraft)
    |> case do
      nil -> default_scope_context()
      spacecraft_id -> scope_context("spacecraft", [spacecraft_id])
    end
  end

  defp legacy_spacecraft_scope_param?(params) when is_map(params) do
    params
    |> Map.get("spacecraft_id", Map.get(params, "spacecraft"))
    |> text_param()
    |> is_binary()
  end

  defp document_scope_context(%Document{defaults: defaults}) when is_map(defaults) do
    defaults
    |> Map.get("scope", Map.get(defaults, :scope))
    |> case do
      scope when is_map(scope) ->
        context = ScopeContext.from_map(scope)

        if ScopeContext.primary_kind(context) do
          context
        end

      _missing ->
        nil
    end
  end

  defp document_scope_context(_document), do: nil

  defp scope_context(kind, ids) when is_list(ids) do
    ids = Enum.uniq(ids)
    mode = if length(ids) > 1, do: "many", else: "one"

    ScopeContext.from_map(%{"primary" => %{"kind" => kind, "mode" => mode, "ids" => ids}})
  end

  defp scope_identity(scope_context) do
    kind = scope_context |> ScopeContext.primary_kind() |> context_text()
    ids = ScopeContext.primary_ids(scope_context)
    id = if kind in [nil, ""], do: nil, else: List.first(ids)

    {kind, id, if(is_nil(kind), do: [], else: ids)}
  end

  defp normalize_scope_kind(value) when is_binary(value) do
    value = String.trim(value)

    if value in [
         "mission",
         "spacecraft",
         "contact",
         "ground_station",
         "source_endpoint",
         "transport",
         "link"
       ] do
      value
    end
  end

  defp normalize_scope_kind(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_scope_kind()

  defp normalize_scope_kind(_value), do: nil

  defp valid_contact_scope?(current_scope, mission, contact_id, opts)
       when is_binary(contact_id) do
    valid_contact? =
      Keyword.get(opts, :valid_contact?, fn _scope, _mission, _contact_id -> false end)

    valid_contact?.(current_scope, mission, contact_id)
  end

  defp valid_contact_scope?(_current_scope, _mission, _contact_id, _opts), do: false

  defp valid_operational_resource_scope?(current_scope, mission, scope_kind, scope_id, opts)
       when is_binary(scope_id) do
    valid_scope? =
      Keyword.get(opts, :valid_operational_resource_scope?, fn
        _scope, _mission, _scope_kind, _scope_id -> true
      end)

    valid_scope?.(current_scope, mission, scope_kind, scope_id)
  end

  defp valid_operational_resource_scope?(_current_scope, _mission, _scope_kind, _scope_id, _opts),
    do: false

  defp time_context("archive", time_axis, from_value, to_value, _replay_run_id, _window_seconds) do
    %{"mode" => "archive", "axis" => time_axis}
    |> maybe_put("from", from_value)
    |> maybe_put("to", to_value)
  end

  defp time_context("replay_run", time_axis, from_value, to_value, replay_run_id, _window_seconds) do
    %{"mode" => "replay_run", "axis" => time_axis, "replay_run_id" => replay_run_id}
    |> maybe_put("from", from_value)
    |> maybe_put("to", to_value)
  end

  defp time_context(_mode, time_axis, _from_value, _to_value, _replay_run_id, window_seconds),
    do: maybe_put(%{"mode" => "live", "axis" => time_axis}, "window_seconds", window_seconds)

  defp validate_time_params(params) when is_map(params) do
    case params["time_mode"] do
      mode when mode in [nil, "", "live"] ->
        validate_live_time_params(params, mode)

      "archive" ->
        validate_archive_time_params(params)

      mode when mode in ["replay", "replay_run"] ->
        validate_replay_time_params(params)

      _unsupported ->
        live_time_params(:unsupported_time_mode, params)
    end
  end

  defp validate_live_time_params(params, explicit_mode) do
    from = text_param(params["from"])
    to = text_param(params["to"])

    case {from, to} do
      {nil, nil} ->
        live_time_params(:ok, params)

      {from, to} when is_binary(from) and is_binary(to) ->
        resolve_live_time_bounds(params, explicit_mode, from, to)

      _partial ->
        live_time_params(:time_range_required, params)
    end
  end

  # Grafana-style bounds on a live-mode URL: `from=now-6h&to=now` keeps the
  # dashboard live with a sliding window; frozen bounds fall back to archive
  # when no explicit `time_mode=live` was requested.
  defp resolve_live_time_bounds(params, explicit_mode, from, to) do
    case TimeRange.resolve(from, to, DateTime.utc_now()) do
      {:ok, {:sliding, window_seconds}} ->
        %{
          mode: "live",
          from: from,
          to: to,
          axis: time_axis(params, "live"),
          from_value: nil,
          to_value: nil,
          replay_run_id: nil,
          validation: "ok",
          window_seconds: window_seconds
        }

      {:ok, {:absolute, from_value, to_value}} when explicit_mode in [nil, ""] ->
        %{
          mode: "archive",
          from: DateTime.to_iso8601(from_value),
          to: DateTime.to_iso8601(to_value),
          axis: time_axis(params, "archive"),
          from_value: from_value,
          to_value: to_value,
          replay_run_id: nil,
          validation: "ok",
          window_seconds: nil
        }

      {:ok, {:absolute, _from_value, _to_value}} ->
        live_time_params(:sliding_range_required, params)

      {:error, reason} ->
        live_time_params(reason, params)
    end
  end

  defp validate_archive_time_params(params) do
    with {:ok, from_value} <- required_time_bound(params["from"]),
         {:ok, to_value} <- required_time_bound(params["to"]),
         :ok <- validate_time_order(from_value, to_value) do
      %{
        mode: "archive",
        from: DateTime.to_iso8601(from_value),
        to: DateTime.to_iso8601(to_value),
        axis: time_axis(params, "archive"),
        from_value: from_value,
        to_value: to_value,
        replay_run_id: nil,
        validation: "ok",
        window_seconds: nil
      }
    else
      {:error, reason} -> live_time_params(reason, params)
    end
  end

  defp validate_replay_time_params(params) do
    with {:ok, replay_run_id} <- required_replay_run_id(params["replay_run_id"]),
         {:ok, from_value, to_value} <- optional_time_bounds(params),
         :ok <- validate_time_order_if_present(from_value, to_value) do
      %{
        mode: "replay_run",
        from: optional_time_string(from_value),
        to: optional_time_string(to_value),
        axis: time_axis(params, "replay_run"),
        from_value: from_value,
        to_value: to_value,
        replay_run_id: replay_run_id,
        validation: "ok",
        window_seconds: nil
      }
    else
      {:error, reason} -> live_time_params(reason, params)
    end
  end

  defp live_time_params(validation, params) do
    %{
      mode: "live",
      from: nil,
      to: nil,
      axis: time_axis(params, "live"),
      from_value: nil,
      to_value: nil,
      replay_run_id: nil,
      validation: validation_code(validation),
      window_seconds: nil
    }
  end

  defp time_axis(params, mode) when is_map(params) do
    case params["time_axis"] do
      axis when axis in ["generation_time", "receipt_time"] -> axis
      _axis -> default_time_axis(mode)
    end
  end

  defp default_time_axis("archive"), do: "receipt_time"
  defp default_time_axis(_mode), do: "generation_time"

  defp required_replay_run_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :replay_run_required}
      replay_run_id -> {:ok, replay_run_id}
    end
  end

  defp required_replay_run_id(_value), do: {:error, :replay_run_required}

  defp optional_time_bounds(%{"from" => from, "to" => to})
       when is_binary(from) and is_binary(to) do
    from = String.trim(from)
    to = String.trim(to)

    cond do
      from == "" and to == "" ->
        {:ok, nil, nil}

      from == "" or to == "" ->
        {:error, :time_range_required}

      true ->
        with {:ok, from_value} <- required_time_bound(from),
             {:ok, to_value} <- required_time_bound(to) do
          {:ok, from_value, to_value}
        end
    end
  end

  defp optional_time_bounds(_params), do: {:ok, nil, nil}

  defp validate_time_order_if_present(nil, nil), do: :ok

  defp validate_time_order_if_present(from_value, to_value),
    do: validate_time_order(from_value, to_value)

  defp optional_time_string(nil), do: nil
  defp optional_time_string(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp required_time_bound(value) when is_binary(value) do
    value = String.trim(value)

    case parse_datetime(value) do
      {:ok, datetime} -> {:ok, datetime}
      :error -> {:error, :invalid_time_bound}
    end
  end

  defp required_time_bound(_value), do: {:error, :time_range_required}

  defp validate_time_order(from_value, to_value) do
    if DateTime.compare(from_value, to_value) == :gt do
      {:error, :time_range_reversed}
    else
      :ok
    end
  end

  defp parse_datetime(""), do: :error

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _reason} ->
        value
        |> Kernel.<>("Z")
        |> DateTime.from_iso8601()
        |> case do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _reason} -> :error
        end
    end
  end

  defp validation_code(:ok), do: "ok"
  defp validation_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp validation_code(reason) when is_binary(reason), do: reason

  defp validate_member(value, allowed, default) when is_binary(value) do
    value = String.trim(value)
    if value in allowed, do: value, else: default
  end

  defp validate_member(_value, _allowed, default), do: default

  defp limit_mode_fallback(requested_mode, applied_mode) do
    requested_mode = text_param(requested_mode)

    if is_nil(requested_mode) or requested_mode == applied_mode do
      nil
    else
      %{
        "requested_mode" => requested_mode,
        "applied_mode" => applied_mode,
        "reason" => "unsupported_limit_semantics_mode",
        "supported_modes" => @supported_limit_modes
      }
    end
  end

  defp default_realm("replay_run", data_realms, _default_realm) when is_list(data_realms) do
    if "replay" in data_realms, do: "replay", else: default_data_realm(data_realms)
  end

  defp default_realm(_time_mode, _data_realms, default_realm), do: default_realm

  defp source_context_from_params(params, realm, data_bindings, default_data_context)

  defp source_context_from_params(
         %{"source_binding_id" => source_binding_id},
         realm,
         _data_bindings,
         _default_data_context
       )
       when source_binding_id in ["", "primary"] do
    primary_source_context(realm)
  end

  defp source_context_from_params(params, realm, data_bindings, default_data_context) do
    case selected_telemetry_binding(params, realm, data_bindings) do
      nil ->
        default_source_context_for_realm(default_data_context, realm, data_bindings) ||
          primary_source_context(realm)

      binding ->
        telemetry_source_context(realm, binding)
    end
  end

  defp put_data_view(source_context, data_view) do
    Map.put(source_context, "view", data_view)
  end

  defp primary_source_context(realm),
    do: %{"realm" => realm, "source_mode" => "primary", "source_contexts" => %{}}

  defp telemetry_source_context(realm, binding) do
    telemetry_context =
      %{
        "source_mode" => "specific",
        "data_source_id" => binding.data_source_id,
        "source_binding_id" => binding.binding_id
      }
      |> maybe_put("dataset", binding.dataset)

    %{
      "realm" => realm,
      "source_mode" => "specific",
      "source_contexts" => %{"telemetry" => telemetry_context}
    }
  end

  defp telemetry_source_context(source_context) when is_map(source_context) do
    source_context
    |> Map.get("source_contexts", %{})
    |> Map.get("telemetry", %{})
  end

  defp default_source_context_for_realm(default_data_context, realm, data_bindings) do
    if normalize_realm(default_data_context["realm"]) == realm and
         map_size(source_contexts(default_data_context)) > 0 do
      default_data_context
    else
      default_telemetry_source_context_for_realm(default_data_context, realm, data_bindings)
    end
  end

  defp default_telemetry_source_context_for_realm(default_data_context, realm, data_bindings) do
    default_source_binding_id =
      default_data_context
      |> telemetry_source_context()
      |> Map.get("source_binding_id")

    case selected_telemetry_binding(
           %{"source_binding_id" => default_source_binding_id},
           realm,
           data_bindings
         ) do
      nil -> nil
      binding -> telemetry_source_context(realm, binding)
    end
  end

  defp normalized_data_source_query(%{"source_binding_id" => source_binding_id}, _context)
       when source_binding_id in ["", "primary"],
       do: nil

  defp normalized_data_source_query(_params, telemetry_source_context),
    do: Map.get(telemetry_source_context, "data_source_id")

  defp normalized_source_binding_query(
         %{"source_binding_id" => source_binding_id},
         _context,
         default_data_context
       )
       when source_binding_id in ["", "primary"],
       do: if(default_telemetry_source_binding_id(default_data_context), do: "primary")

  defp normalized_source_binding_query(_params, telemetry_source_context, _default_data_context),
    do: Map.get(telemetry_source_context, "source_binding_id")

  defp default_telemetry_source_binding_id(data_context) when is_map(data_context) do
    data_context
    |> telemetry_source_context()
    |> Map.get("source_binding_id")
  end

  defp default_telemetry_source_binding_id(_data_context), do: nil

  defp default_data_view(data_context) when is_map(data_context) do
    validate_member(data_context["view"], @supported_data_views, "canonical")
  end

  defp compare_data_view(compare_data_view, active_data_view) do
    compare_data_view
    |> validate_member(@supported_data_views, nil)
    |> case do
      ^active_data_view -> nil
      view -> view
    end
  end

  defp normalize_data_context(context, data_realms, data_bindings) when is_map(context) do
    context = stringify_keys(context)
    realm = validate_member(context["realm"], data_realms, default_data_realm(data_realms))
    source_contexts = source_contexts(context)
    telemetry_context = Map.get(source_contexts, "telemetry", %{})

    data_view =
      validate_member(context["view"] || context["data_view"], @supported_data_views, "canonical")

    telemetry_binding =
      selected_telemetry_binding(
        %{"source_binding_id" => telemetry_context["source_binding_id"]},
        realm,
        data_bindings
      )

    cond do
      telemetry_binding ->
        telemetry_source_context(realm, telemetry_binding)
        |> merge_source_contexts(source_contexts)

      map_size(source_contexts) > 0 ->
        %{
          "realm" => realm,
          "source_mode" => context["source_mode"] || "specific",
          "source_contexts" => source_contexts
        }

      true ->
        primary_source_context(realm)
    end
    |> put_data_view(data_view)
  end

  defp normalize_data_context(_context, data_realms, _data_bindings),
    do: primary_source_context(default_data_realm(data_realms))

  defp selected_telemetry_binding(%{"source_binding_id" => binding_id}, realm, data_bindings)
       when is_binary(binding_id) and binding_id != "" do
    Enum.find(data_bindings, fn binding ->
      binding.binding_id == binding_id and binding.logical_source == :telemetry and
        normalize_realm(binding.realm) == realm and DataBinding.active?(binding)
    end)
  end

  defp selected_telemetry_binding(%{"data_source_id" => data_source_id}, realm, data_bindings)
       when is_binary(data_source_id) and data_source_id != "" do
    data_bindings
    |> Enum.filter(fn binding ->
      binding.data_source_id == data_source_id and binding.logical_source == :telemetry and
        normalize_realm(binding.realm) == realm and DataBinding.active?(binding)
    end)
    |> Enum.sort_by(&{&1.priority, &1.binding_id})
    |> List.first()
  end

  defp selected_telemetry_binding(_params, _realm, _data_bindings), do: nil

  defp source_contexts(context) when is_map(context) do
    context
    |> Map.get("source_contexts", %{})
    |> ensure_map()
  end

  defp source_contexts(_context), do: %{}

  defp merge_source_contexts(source_context, source_contexts) when is_map(source_context) do
    Map.update(
      source_context,
      "source_contexts",
      source_contexts,
      &Map.merge(source_contexts, ensure_map(&1))
    )
  end

  defp normalize_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp normalize_realm(realm) when is_binary(realm), do: realm
  defp normalize_realm(_realm), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_keys(value)}
      {key, value} -> {key, stringify_keys(value)}
    end)
  end

  defp stringify_keys(value), do: value

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp validate_context(nil, _spacecraft), do: nil

  defp validate_context(spacecraft_id, spacecraft) do
    if Enum.any?(spacecraft, &(&1.spacecraft_id == spacecraft_id)), do: spacecraft_id
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
  defp context_text(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
