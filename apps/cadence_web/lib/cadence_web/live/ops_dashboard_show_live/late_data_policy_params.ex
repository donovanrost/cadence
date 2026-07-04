defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams do
  @moduledoc false

  @type t :: %__MODULE__{
          decision: String.t() | nil,
          execution_mode: String.t() | nil,
          run_id: String.t() | nil,
          dashboard_time_mode: String.t() | nil,
          dashboard_replay_run_id: String.t() | nil,
          dashboard_limit_mode: String.t() | nil,
          realm: String.t() | nil,
          data_source_id: String.t() | nil,
          source_binding_id: String.t() | nil,
          observable_id: String.t() | nil,
          point_id: String.t() | nil,
          source_from: String.t() | nil,
          source_to: String.t() | nil,
          receipt_from: String.t() | nil,
          receipt_to: String.t() | nil,
          sample_count: non_neg_integer() | nil,
          authority: String.t() | nil,
          reason: String.t() | nil,
          confirmed: String.t() | nil,
          source_event_id: String.t() | nil,
          source_event_type: String.t() | nil
        }

  defstruct [
    :decision,
    :execution_mode,
    :run_id,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_limit_mode,
    :realm,
    :data_source_id,
    :source_binding_id,
    :observable_id,
    :point_id,
    :source_from,
    :source_to,
    :receipt_from,
    :receipt_to,
    :sample_count,
    :authority,
    :reason,
    :confirmed,
    :source_event_id,
    :source_event_type
  ]

  @spec from_event(map()) :: t()
  def from_event(%{"late_data_policy" => params}) when is_map(params), do: new(params)
  def from_event(params) when is_map(params), do: new(params)

  @spec new(map() | t()) :: t()
  def new(%__MODULE__{} = params), do: params

  def new(params) when is_map(params) do
    %__MODULE__{
      decision: param(params, "decision"),
      execution_mode: param(params, "execution_mode"),
      run_id: param(params, "run_id"),
      dashboard_time_mode: param(params, "dashboard_time_mode"),
      dashboard_replay_run_id: param(params, "dashboard_replay_run_id"),
      dashboard_limit_mode: param(params, "dashboard_limit_mode"),
      realm: param(params, "realm"),
      data_source_id: param(params, "data_source_id"),
      source_binding_id: param(params, "source_binding_id"),
      observable_id: param(params, "observable_id"),
      point_id: param(params, "point_id"),
      source_from: param(params, "source_from"),
      source_to: param(params, "source_to"),
      receipt_from: param(params, "receipt_from"),
      receipt_to: param(params, "receipt_to"),
      sample_count:
        integer_param(Map.get(params, "sample_count", Map.get(params, :sample_count))),
      authority: param(params, "authority"),
      reason: param(params, "reason"),
      confirmed: param(params, "confirmed"),
      source_event_id: param(params, "source_event_id"),
      source_event_type: param(params, "source_event_type")
    }
  end

  @spec confirmed?(t() | map()) :: boolean()
  def confirmed?(%__MODULE__{} = params), do: params.confirmed in ["confirmed", "true", "on"]
  def confirmed?(params) when is_map(params), do: params |> from_event() |> confirmed?()

  @spec attrs(t(), map(), map()) :: map()
  def attrs(%__MODULE__{} = params, scope, mission) do
    %{
      backfill_run_id: params.run_id,
      execution_mode: params.execution_mode,
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      realm: params.realm,
      data_source_id: params.data_source_id,
      binding_id: params.source_binding_id,
      observable_id: params.observable_id,
      point_id: params.point_id,
      source_from: params.source_from,
      source_to: params.source_to,
      receipt_from: params.receipt_from,
      receipt_to: params.receipt_to,
      sample_count: params.sample_count,
      authority: params.authority,
      reason: params.reason,
      payload: dashboard_context_payload(params),
      actor_id: user_id(scope),
      actor_kind: "operator",
      source_event_id: params.source_event_id,
      source_event_type: params.source_event_type,
      requested_by: "dashboard_data_link_inspector"
    }
  end

  def attrs(params, scope, mission) when is_map(params),
    do: params |> new() |> attrs(scope, mission)

  @spec to_event_params(t()) :: map()
  def to_event_params(%__MODULE__{} = params) do
    %{
      "decision" => params.decision,
      "execution_mode" => params.execution_mode,
      "run_id" => params.run_id,
      "dashboard_time_mode" => params.dashboard_time_mode,
      "dashboard_replay_run_id" => params.dashboard_replay_run_id,
      "dashboard_limit_mode" => params.dashboard_limit_mode,
      "realm" => params.realm,
      "data_source_id" => params.data_source_id,
      "source_binding_id" => params.source_binding_id,
      "observable_id" => params.observable_id,
      "point_id" => params.point_id,
      "source_from" => params.source_from,
      "source_to" => params.source_to,
      "receipt_from" => params.receipt_from,
      "receipt_to" => params.receipt_to,
      "sample_count" => params.sample_count && Integer.to_string(params.sample_count),
      "authority" => params.authority,
      "reason" => params.reason,
      "confirmed" => params.confirmed,
      "source_event_id" => params.source_event_id,
      "source_event_type" => params.source_event_type
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp param(params, key) do
    params
    |> Map.get(key, Map.get(params, atom_key(key)))
    |> text_param()
  end

  defp atom_key("decision"), do: :decision
  defp atom_key("execution_mode"), do: :execution_mode
  defp atom_key("run_id"), do: :run_id
  defp atom_key("dashboard_time_mode"), do: :dashboard_time_mode
  defp atom_key("dashboard_replay_run_id"), do: :dashboard_replay_run_id
  defp atom_key("dashboard_limit_mode"), do: :dashboard_limit_mode
  defp atom_key("realm"), do: :realm
  defp atom_key("data_source_id"), do: :data_source_id
  defp atom_key("source_binding_id"), do: :source_binding_id
  defp atom_key("observable_id"), do: :observable_id
  defp atom_key("point_id"), do: :point_id
  defp atom_key("source_from"), do: :source_from
  defp atom_key("source_to"), do: :source_to
  defp atom_key("receipt_from"), do: :receipt_from
  defp atom_key("receipt_to"), do: :receipt_to
  defp atom_key("sample_count"), do: :sample_count
  defp atom_key("authority"), do: :authority
  defp atom_key("reason"), do: :reason
  defp atom_key("confirmed"), do: :confirmed
  defp atom_key("source_event_id"), do: :source_event_id
  defp atom_key("source_event_type"), do: :source_event_type

  defp user_id(%{user: %{id: id}}) when is_binary(id), do: id
  defp user_id(%{user: %{user_id: id}}) when is_binary(id), do: id
  defp user_id(_scope), do: nil

  defp dashboard_context_payload(%__MODULE__{} = params) do
    context =
      %{
        "dashboard_time_mode" => params.dashboard_time_mode,
        "dashboard_replay_run_id" => params.dashboard_replay_run_id,
        "dashboard_limit_mode" => params.dashboard_limit_mode
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    case context do
      context when map_size(context) > 0 -> %{"dashboard_context" => context}
      _empty -> %{}
    end
  end

  defp integer_param(value) when is_integer(value) and value >= 0, do: value
  defp integer_param(value) when is_integer(value), do: nil

  defp integer_param(value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> nil
    end
  end

  defp integer_param(_value), do: nil

  defp text_param(nil), do: nil
  defp text_param(value) when is_atom(value), do: Atom.to_string(value)

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(value) when is_integer(value), do: Integer.to_string(value)
  defp text_param(_value), do: nil
end
