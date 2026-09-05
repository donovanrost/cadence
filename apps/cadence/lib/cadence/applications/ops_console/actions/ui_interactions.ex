defmodule Cadence.Applications.OpsConsole.Actions.UiInteractions do
  @moduledoc "Mission-scoped host actions for the federated Ops UI surfaces."

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.{Alarms, MissionTimeline}

  @application_key "ops_console"
  @application_version 1
  @alarm_filter_keys ~w(severity state spacecraft_id query)
  @timeline_filter_keys ~w(category kind severity spacecraft_id from to)

  @bindings [
    {"alarms", "filter"},
    {"alarms", "reset_filters"},
    {"timeline", "apply_timeline_filters"},
    {"timeline", "clear_timeline_selection"}
  ]

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
    with :ok <- validate_request_identity(surface_id, request),
         :ok <- validate_host_context(host_context, scope),
         :ok <- validate_json_params(request.params),
         {:ok, normalized_params} <-
           normalize_action_params(surface_id, request.action_id, request.params),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         {:ok, result} <-
           dispatch(
             organization_id,
             mission_id,
             surface_id,
             request.action_id,
             normalized_params
           ) do
      case JSONBoundary.safe(result) do
        {:ok, safe_result} -> {:ok, safe_result}
        {:error, _reason} -> {:error, :unsupported_application_action}
      end
    else
      {:error, _reason} = error -> error
    end
  rescue
    _exception -> {:error, :unsupported_application_action}
  catch
    _kind, _value -> {:error, :unsupported_application_action}
  end

  def execute(%Scope{}, %HostContext{}, _surface_id, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term()
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe} -> safe
      _invalid -> nil
    end
  end

  defp validate_request_identity(surface_id, %ActionRequest{
         application_key: @application_key,
         application_version: @application_version,
         action_id: action_id,
         params: params
       })
       when is_binary(action_id) and is_map(params) do
    if {surface_id, action_id} in @bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_request_identity(_surface_id, _request),
    do: {:error, :unsupported_application_action}

  defp validate_host_context(%HostContext{placement: :mission} = host_context, %Scope{}) do
    if HostContext.valid?(host_context),
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_host_context(_host_context, _scope),
    do: {:error, :unsupported_application_action}

  defp validate_json_params(params) do
    case JSONBoundary.validate(params) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unsupported_application_action}
    end
  end

  defp normalize_action_params(surface_id, action_id, params) do
    case normalize_params(surface_id, action_id, params) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, :unsupported_application_action}
    end
  end

  defp normalize_params("alarms", "filter", %{"filters" => filters})
       when is_map(filters) do
    with {:ok, filters} <- normalize_filter_map(filters, @alarm_filter_keys),
         :ok <- validate_alarm_filters(filters) do
      {:ok, %{"filters" => Map.merge(%{"state" => "active"}, filters)}}
    end
  end

  defp normalize_params("alarms", "reset_filters", %{}),
    do: {:ok, %{"filters" => %{"state" => "active"}}}

  defp normalize_params("timeline", "apply_timeline_filters", %{"timeline" => filters})
       when is_map(filters) do
    with {:ok, filters} <- normalize_filter_map(filters, @timeline_filter_keys),
         {:ok, filters} <- normalize_timeline_filters(filters) do
      {:ok, %{"timeline" => filters}}
    end
  end

  defp normalize_params("timeline", "clear_timeline_selection", %{}),
    do: {:ok, %{"timeline" => %{}}}

  defp normalize_params(_surface_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp normalize_filter_map(filters, allowed_keys) do
    with true <- Enum.all?(Map.keys(filters), &is_binary/1),
         true <- Enum.all?(Map.keys(filters), &(&1 in allowed_keys)),
         true <- Enum.all?(Map.values(filters), &is_binary/1) do
      {:ok, Map.take(filters, allowed_keys)}
    else
      _invalid -> {:error, :invalid_application_action_input}
    end
  end

  defp validate_alarm_filters(filters) do
    with true <-
           Map.get(filters, "severity", "all") in [
             "",
             "all",
             "critical",
             "warning",
             "info",
             "nominal"
           ],
         true <- Map.get(filters, "state", "active") in ["", "active", "all", "nominal"] do
      :ok
    else
      _invalid -> {:error, :invalid_application_action_input}
    end
  end

  defp normalize_timeline_filters(filters) do
    with {:ok, _from} <- parse_datetime(Map.get(filters, "from")),
         {:ok, _to} <- parse_datetime(Map.get(filters, "to")) do
      {:ok, filters}
    end
  end

  defp parse_datetime(nil), do: {:ok, nil}
  defp parse_datetime(""), do: {:ok, nil}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> {:ok, value}
      _invalid -> {:error, :invalid_application_action_input}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_application_action_input}

  defp dispatch(organization_id, mission_id, "alarms", action_id, %{"filters" => filters}) do
    snapshot = Alarms.snapshot(organization_id, mission_id, filters: filters)

    {:ok,
     %{
       "surfaceId" => "alarms",
       "actionId" => action_id,
       "missionId" => mission_id,
       "filters" => filters,
       "observedAt" => iso(snapshot.observed_at),
       "summary" => alarm_summary(snapshot.summary),
       "rows" => Enum.map(snapshot.rows, &alarm_row/1)
     }}
  end

  defp dispatch(organization_id, mission_id, "timeline", "apply_timeline_filters", %{
         "timeline" => filters
       }) do
    timeline_result(organization_id, mission_id, "apply_timeline_filters", filters)
  end

  defp dispatch(organization_id, mission_id, "timeline", "clear_timeline_selection", %{
         "timeline" => filters
       }) do
    timeline_result(organization_id, mission_id, "clear_timeline_selection", filters)
  end

  defp dispatch(_organization_id, _mission_id, _surface_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp timeline_result(organization_id, mission_id, action_id, filters) do
    with {:ok, opts} <- timeline_read_opts(filters) do
      events = MissionTimeline.list_for_mission(organization_id, mission_id, opts)

      {:ok,
       %{
         "surfaceId" => "timeline",
         "actionId" => action_id,
         "missionId" => mission_id,
         "filters" => filters,
         "selectedEventId" => nil,
         "events" => Enum.map(events, &timeline_event/1)
       }}
    end
  end

  defp timeline_read_opts(filters) do
    with {:ok, from} <- parse_datetime(Map.get(filters, "from")),
         {:ok, to} <- parse_datetime(Map.get(filters, "to")) do
      opts =
        [limit: 500]
        |> maybe_put(:category, present(Map.get(filters, "category")))
        |> maybe_put(:kind, present(Map.get(filters, "kind")))
        |> maybe_put(:severity, present(Map.get(filters, "severity")))
        |> maybe_put(:spacecraft_id, present(Map.get(filters, "spacecraft_id")))
        |> maybe_put(:from_occurred_at, datetime_from_iso8601(from))
        |> maybe_put(:to_occurred_at, datetime_from_iso8601(to))

      {:ok, opts}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp datetime_from_iso8601(nil), do: nil

  defp datetime_from_iso8601(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp alarm_summary(summary) do
    %{
      "activeCount" => summary.active_count,
      "criticalCount" => summary.critical_count,
      "warningCount" => summary.warning_count,
      "infoCount" => summary.info_count,
      "status" => to_string(summary.status),
      "freshness" => to_string(summary.freshness)
    }
  end

  defp alarm_row(row) do
    %{
      "id" => row.id,
      "limitEventId" => row.limit_event_id,
      "severity" => to_string(row.severity),
      "state" => if(row.active?, do: "active", else: "nominal"),
      "limitState" => to_string(row.limit_state),
      "spacecraftId" => row.spacecraft_id,
      "pointId" => row.point_id,
      "pointName" => row.point_name,
      "value" => inspect(row.evaluated_value),
      "observedAt" => iso(row.receipt_time)
    }
  end

  defp timeline_event(event) do
    %{
      "id" => event.mission_event_id,
      "missionEventId" => event.mission_event_id,
      "occurredAt" => iso(event.occurred_at),
      "category" => to_string(event.category),
      "kind" => to_string(event.kind),
      "severity" => event.severity && to_string(event.severity),
      "title" => event.title,
      "summary" => event.summary,
      "subject" => event.subject_id || event.source_record_id,
      "spacecraftId" => event.spacecraft_id
    }
  end

  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp iso(value) when is_binary(value), do: value
  defp iso(_value), do: nil
end
