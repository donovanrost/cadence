defmodule Cadence.Applications.OpsConsole.Actions.TelemetryExplore do
  @moduledoc "Strict navigation actions for Telemetry Explore."

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Ops.PointCatalog

  @bindings [
    {"telemetry_explore", "apply_filters"},
    {"telemetry_explore", "apply_question"}
  ]

  @filter_keys ~w(
    point_id spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id
    order limit selection_view validity_state realm logical_source data_source_id source_binding_id
    source_dashboard_id sample_id selected_time question limit_mode
  )

  @question_ids ~w(recent_anomalies what_changed missing_history link_degradation)

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id} = host_context,
        surface_id,
        %ActionRequest{} = request
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(surface_id) do
    with :ok <- validate_request(surface_id, host_context, request),
         :ok <- validate_context(scope, host_context),
         :ok <- validate_json(request.params),
         :ok <- validate_mission_param(mission_id, request.params),
         :ok <- authorize(scope, organization_id, mission_id, request.action_id) do
      dispatch(scope, mission_id, request.action_id, request.params)
    end
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term()
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp validate_request(
         surface_id,
         %HostContext{placement: :mission} = host_context,
         %ActionRequest{
           application_key: "ops_console",
           application_version: 1,
           surface_id: surface_id,
           surface_version: 1,
           action_id: action_id,
           params: params
         }
       )
       when is_binary(action_id) and action_id != "" and is_map(params) do
    if HostContext.valid?(host_context) and {surface_id, action_id} in @bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_request(_surface_id, _host_context, _request),
    do: {:error, :unsupported_application_action}

  defp validate_context(%Scope{mission_id: nil}, %HostContext{}), do: :ok

  defp validate_context(%Scope{mission_id: mission_id}, %HostContext{mission_id: mission_id}),
    do: :ok

  defp validate_context(_scope, _host_context), do: {:error, :scope_mismatch}

  defp validate_json(params) do
    case JSONBoundary.validate(params) do
      :ok -> :ok
      {:error, _reason} -> {:error, :malformed_action_input}
    end
  end

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp authorize(scope, organization_id, mission_id, _action_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  defp dispatch(_scope, mission_id, "apply_filters", params) do
    with :ok <- exact_keys(params, @filter_keys),
         :ok <- validate_filter_values(params) do
      {:ok, navigation_result(explore_path(mission_id, filter_query(params)))}
    end
  end

  defp dispatch(scope, mission_id, "apply_question", params) do
    with :ok <- exact_keys(params, ["question", "source_dashboard_id"]),
         {:ok, question} <- required_question(params["question"]),
         :ok <- optional_text(params["source_dashboard_id"]) do
      points = PointCatalog.list_points(scope.organization_id, mission_id)

      {:ok,
       navigation_result(
         explore_path(mission_id, question_query(question, points, params["source_dashboard_id"]))
       )}
    end
  end

  defp dispatch(_scope, _mission_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp exact_keys(params, expected) when is_map(params) do
    keys = Map.keys(params)
    expected_keys = expected |> Enum.uniq() |> Enum.sort()

    if Enum.all?(keys, &is_binary/1) and Enum.sort(keys) == expected_keys,
      do: :ok,
      else: {:error, :malformed_action_input}
  end

  defp exact_keys(_params, _expected), do: {:error, :malformed_action_input}

  defp validate_filter_values(params) do
    if Enum.all?(@filter_keys, &is_binary(Map.get(params, &1))),
      do: :ok,
      else: {:error, :malformed_action_input}
  end

  defp required_question(question) when question in @question_ids, do: {:ok, question}
  defp required_question(_question), do: {:error, :invalid_question}

  defp optional_text(value) when is_binary(value), do: :ok
  defp optional_text(_value), do: {:error, :malformed_action_input}

  defp filter_query(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.update!("time_mode", &normalize_time_mode/1)
    |> maybe_clear_range()
    |> compact_query()
    |> Map.update("order", "desc", &normalize_order/1)
    |> Map.update("limit", "100", &normalize_limit/1)
    |> Map.update("selection_view", "canonical", &normalize_selection_view/1)
    |> Map.update("logical_source", "telemetry", &normalize_logical_source/1)
    |> compact_query()
  end

  defp maybe_clear_range(%{"time_mode" => mode} = params)
       when mode not in ["archive", "replay_run"],
       do: Map.merge(params, %{"from" => "", "to" => ""})

  defp maybe_clear_range(params), do: params

  defp question_query("link_degradation", _points, source_dashboard_id),
    do:
      compact_query(%{
        "question" => "link_degradation",
        "time_mode" => "last_1h",
        "logical_source" => "operational_observables",
        "source_dashboard_id" => source_dashboard_id
      })

  defp question_query(question, points, source_dashboard_id) do
    point_id =
      case points do
        [point | _rest] -> point.point_id
        _empty -> nil
      end

    compact_query(%{
      "question" => question,
      "point_id" => point_id,
      "time_mode" => if(question == "recent_anomalies", do: "last_15m", else: "last_1h"),
      "selection_view" => "all_revisions",
      "source_dashboard_id" => source_dashboard_id
    })
  end

  defp explore_path(mission_id, query),
    do: "/missions/#{URI.encode(mission_id)}/ops/explore?#{URI.encode_query(query)}"

  defp navigation_result(href), do: %{"navigation" => href}

  defp compact_query(query),
    do: Map.reject(query, fn {_key, value} -> is_nil(value) or value == "" end)

  defp normalize_time_mode("live"), do: "latest"

  defp normalize_time_mode(value)
       when value in ["latest", "last_5m", "last_15m", "last_1h", "archive", "replay_run"],
       do: value

  defp normalize_time_mode(_value), do: "latest"

  defp normalize_order("asc"), do: "asc"
  defp normalize_order(_value), do: "desc"

  defp normalize_limit(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..1000 -> Integer.to_string(limit)
      _invalid -> "100"
    end
  end

  defp normalize_selection_view(value) when value in ["canonical", "all_revisions"], do: value
  defp normalize_selection_view(_value), do: "canonical"

  defp normalize_logical_source(value)
       when value in ["telemetry", "limits", "events", "operational_observables"],
       do: value

  defp normalize_logical_source(_value), do: "telemetry"
end
