defmodule Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowRequest do
  @moduledoc "Shared pre-effect validation for native and compatibility historical-workflow requests."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.DataSources
  alias Cadence.Telemetry.DataManagement.WorkflowEvents

  def validate(%Scope{} = scope, mission_id, values) when is_map(values) do
    with :ok <- authorize(scope, mission_id),
         :ok <- valid_values(values),
         {:ok, workflow} <- workflow(values),
         {:ok, from} <- timestamp(values, "source_from"),
         {:ok, to} <- timestamp(values, "source_to"),
         :ok <- ordered_range(from, to),
         {:ok, source} <- source(scope, mission_id, values),
         {:ok, binding} <- binding(scope, mission_id, values, source),
         {:ok, points} <- points(values),
         {:ok, run_id} <- run_id(values),
         {:ok, reason} <- reason(values),
         attrs = attrs(scope, mission_id, source, binding, run_id, from, to, reason),
         :ok <- WorkflowEvents.validate_context(workflow, attrs) do
      {:ok, %{workflow: workflow, attrs: attrs, point_ids: points}}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      _ -> invalid("request", "unavailable")
    end
  end

  def validate(_, _, _), do: invalid("request", "invalid")

  defp authorize(scope, mission) do
    if is_binary(mission) and mission != "" and
         (is_nil(scope.mission_id) or scope.mission_id == mission) do
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission
      })
    else
      {:error, :forbidden}
    end
  end

  defp valid_values(values) do
    if map_size(values) <= 64 and
         Enum.all?(values, fn {key, value} ->
           is_binary(key) and is_binary(value) and byte_size(value) <= 8_192 and
             String.valid?(value)
         end), do: :ok, else: invalid("request", "invalid")
  end

  defp workflow(values) do
    case WorkflowEvents.normalize_workflow(text(values, "workflow")) do
      {:ok, workflow} -> {:ok, workflow}
      _ -> invalid("workflow", "unsupported")
    end
  end

  defp timestamp(values, field) do
    case DateTime.from_iso8601(text(values, field)) do
      {:ok, value, _offset} -> {:ok, value}
      _ -> invalid(field, "invalid_timestamp")
    end
  end

  defp ordered_range(from, to) do
    if DateTime.compare(from, to) == :lt, do: :ok, else: invalid("source_to", "must_follow_start")
  end

  defp source(scope, mission, values) do
    with {:ok, source} <- DataSources.fetch_data_source(text(values, "data_source_id")),
         true <- scoped?(source, scope, mission),
         true <- source.status == :active do
      {:ok, source}
    else
      _ -> invalid("data_source_id", "unavailable")
    end
  end

  defp binding(scope, mission, values, source) do
    with {:ok, binding} <- DataSources.fetch_data_binding(text(values, "source_binding_id")),
         true <- scoped?(binding, scope, mission),
         true <- binding.data_source_id == source.data_source_id,
         true <- to_string(binding.realm) == text(values, "realm"),
         true <- binding.logical_source == :telemetry,
         true <- binding.status == :active,
         true <- active_now?(binding) do
      {:ok, binding}
    else
      _ -> invalid("source_binding_id", "unavailable")
    end
  end

  defp scoped?(resource, scope, mission),
    do:
      resource.organization_id in [nil, scope.organization_id] and
        resource.mission_id in [nil, mission]

  defp active_now?(binding) do
    now = DateTime.utc_now()

    (is_nil(binding.active_from) or DateTime.compare(binding.active_from, now) != :gt) and
      (is_nil(binding.active_to) or DateTime.compare(binding.active_to, now) == :gt)
  end

  defp points(values) do
    points =
      case text(values, "point_ids") do
        "" -> [text(values, "point_id"), text(values, "observable_id")]
        value -> String.split(value, [",", "\n", "\r", "\t", " "], trim: true)
      end
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if length(points) <= 100 and Enum.all?(points, &(String.valid?(&1) and byte_size(&1) <= 240)),
      do: {:ok, points},
      else: invalid("point_ids", "too_large")
  end

  defp run_id(values) do
    case text(values, "run_id") do
      "" -> {:ok, Cadence.Ids.new("telemetry_backfill_run")}
      value when byte_size(value) <= 240 -> {:ok, value}
      _ -> invalid("run_id", "too_large")
    end
  end

  defp reason(values) do
    case text(values, "reason") do
      "" -> {:ok, "operator_requested_backfill"}
      value when byte_size(value) <= 4_096 -> {:ok, value}
      _ -> invalid("reason", "too_large")
    end
  end

  defp attrs(scope, mission, source, binding, run_id, from, to, reason) do
    %{
      organization_id: scope.organization_id,
      mission_id: mission,
      backfill_run_id: run_id,
      import_run_id: run_id,
      realm: binding.realm,
      data_source_id: source.data_source_id,
      binding_id: binding.binding_id,
      source_from: from,
      source_to: to,
      reason: reason,
      authority: :unknown,
      actor_id: actor_id(scope),
      actor_kind: "operator",
      payload: %{}
    }
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: id}}), do: id

  defp actor_id(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}}),
    do: id

  defp actor_id(_), do: nil

  defp text(values, key) do
    case Map.get(values, key) do
      value when is_binary(value) -> if String.valid?(value), do: String.trim(value), else: ""
      _ -> ""
    end
  end

  defp invalid(field, code), do: {:error, [%{field: field, code: code}]}
end
