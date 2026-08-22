defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams do
  @moduledoc false

  @type t :: %__MODULE__{
          observation_identity_id: String.t() | nil,
          decision: String.t() | nil,
          realm: String.t() | nil,
          data_source_id: String.t() | nil,
          source_binding_id: String.t() | nil,
          canonical_observation_id: String.t() | nil,
          canonical_sample_id: String.t() | nil,
          canonical_revision: integer() | nil,
          decision_reason: String.t() | nil,
          correction_workflow_id: String.t() | nil,
          authority: String.t() | nil,
          confirmed: String.t() | nil,
          source_decision_event_id: String.t() | nil,
          source_target: String.t() | nil,
          source_target_id: String.t() | nil,
          source_link_label: String.t() | nil,
          source_decision: String.t() | nil,
          dashboard_context: map(),
          dashboard_limit_mode: String.t() | nil,
          comparison_state: String.t() | nil,
          comparison_delta: String.t() | nil,
          primary_sample_id: String.t() | nil,
          compare_sample_id: String.t() | nil,
          primary_data_view: String.t() | nil,
          compare_data_view: String.t() | nil,
          primary_data_management: String.t() | nil,
          compare_data_management: String.t() | nil,
          primary_count: String.t() | nil,
          compare_count: String.t() | nil,
          widget_id: String.t() | nil,
          widget_title: String.t() | nil
        }

  defstruct [
    :observation_identity_id,
    :decision,
    :realm,
    :data_source_id,
    :source_binding_id,
    :canonical_observation_id,
    :canonical_sample_id,
    :canonical_revision,
    :decision_reason,
    :correction_workflow_id,
    :authority,
    :confirmed,
    :source_decision_event_id,
    :source_target,
    :source_target_id,
    :source_link_label,
    :source_decision,
    :dashboard_limit_mode,
    :comparison_state,
    :comparison_delta,
    :primary_sample_id,
    :compare_sample_id,
    :primary_data_view,
    :compare_data_view,
    :primary_data_management,
    :compare_data_management,
    :primary_count,
    :compare_count,
    :widget_id,
    :widget_title,
    dashboard_context: %{}
  ]

  @spec from_event(map()) :: t()
  def from_event(%{"revision_decision" => params}) when is_map(params), do: new(params)
  def from_event(params) when is_map(params), do: new(params)

  @spec new(map() | t()) :: t()
  def new(%__MODULE__{} = params), do: params

  def new(params) when is_map(params) do
    %__MODULE__{
      observation_identity_id: param(params, "observation_identity_id"),
      decision: param(params, "decision"),
      realm: param(params, "realm"),
      data_source_id: param(params, "data_source_id"),
      source_binding_id: param(params, "source_binding_id"),
      canonical_observation_id: param(params, "canonical_observation_id"),
      canonical_sample_id: param(params, "canonical_sample_id"),
      canonical_revision:
        integer_param(Map.get(params, "canonical_revision", Map.get(params, :canonical_revision))),
      decision_reason: param(params, "decision_reason"),
      correction_workflow_id: param(params, "correction_workflow_id"),
      authority: param(params, "authority"),
      confirmed: param(params, "confirmed"),
      source_decision_event_id: param(params, "source_decision_event_id"),
      source_target: param(params, "source_target"),
      source_target_id: param(params, "source_target_id"),
      source_link_label: param(params, "source_link_label"),
      source_decision: param(params, "source_decision"),
      dashboard_context: dashboard_context(params),
      dashboard_limit_mode: param(params, "dashboard_limit_mode"),
      comparison_state: param(params, "comparison_state"),
      comparison_delta: param(params, "comparison_delta"),
      primary_sample_id: param(params, "primary_sample_id"),
      compare_sample_id: param(params, "compare_sample_id"),
      primary_data_view: param(params, "primary_data_view"),
      compare_data_view: param(params, "compare_data_view"),
      primary_data_management: param(params, "primary_data_management"),
      compare_data_management: param(params, "compare_data_management"),
      primary_count: param(params, "primary_count"),
      compare_count: param(params, "compare_count"),
      widget_id: param(params, "widget_id"),
      widget_title: param(params, "widget_title")
    }
  end

  @spec confirmed?(t() | map()) :: boolean()
  def confirmed?(%__MODULE__{} = params), do: params.confirmed in ["confirmed", "true", "on"]
  def confirmed?(params) when is_map(params), do: params |> from_event() |> confirmed?()

  @spec attrs(t(), map(), map()) :: map()
  def attrs(%__MODULE__{} = params, scope, mission) do
    %{
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      realm: params.realm,
      data_source_id: params.data_source_id,
      binding_id: params.source_binding_id,
      canonical_observation_id: params.canonical_observation_id,
      canonical_sample_id: params.canonical_sample_id,
      canonical_revision: params.canonical_revision,
      decision_reason: params.decision_reason,
      correction_workflow_id: params.correction_workflow_id,
      authority: params.authority || "dashboard_operator",
      requested_by: "dashboard_data_link_inspector",
      operator_id: user_id(scope),
      actor_id: user_id(scope),
      actor_kind: "operator",
      evidence_ref: evidence_ref(params)
    }
  end

  def attrs(params, scope, mission) when is_map(params),
    do: params |> new() |> attrs(scope, mission)

  defp evidence_ref(%__MODULE__{} = params) do
    %{
      "kind" => "dashboard_revision_decision",
      "id" => params.source_decision_event_id,
      "source_target" => params.source_target,
      "source_target_id" => params.source_target_id,
      "source_link_label" => params.source_link_label,
      "source_panel" => "data_link_inspector",
      "source_decision" => params.source_decision,
      "dashboard_context" => dashboard_context_ref(params),
      "comparison_finding" => comparison_finding_ref(params)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp comparison_finding_ref(%__MODULE__{} = params) do
    %{
      "placement_id" => params.source_target_id,
      "state" => params.comparison_state,
      "delta" => params.comparison_delta,
      "primary_sample_id" => params.primary_sample_id,
      "compare_sample_id" => params.compare_sample_id,
      "primary_data_view" => params.primary_data_view,
      "compare_data_view" => params.compare_data_view,
      "primary_data_management" => params.primary_data_management,
      "compare_data_management" => params.compare_data_management,
      "primary_count" => params.primary_count,
      "compare_count" => params.compare_count,
      "widget_id" => params.widget_id,
      "widget_title" => params.widget_title
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> empty_to_nil()
  end

  defp dashboard_context_ref(%__MODULE__{} = params) do
    params.dashboard_context
    |> Map.put("dashboard_limit_mode", params.dashboard_limit_mode)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> empty_to_nil()
  end

  defp dashboard_context(params) when is_map(params) do
    %{
      "dashboard_time_mode" => param(params, "dashboard_time_mode"),
      "dashboard_replay_run_id" => param(params, "dashboard_replay_run_id"),
      "dashboard_data_view" => param(params, "dashboard_data_view")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp param(params, key) do
    params
    |> Map.get(key, Map.get(params, atom_key(key)))
    |> text_param()
  end

  defp atom_key("observation_identity_id"), do: :observation_identity_id
  defp atom_key("decision"), do: :decision
  defp atom_key("realm"), do: :realm
  defp atom_key("data_source_id"), do: :data_source_id
  defp atom_key("source_binding_id"), do: :source_binding_id
  defp atom_key("canonical_observation_id"), do: :canonical_observation_id
  defp atom_key("canonical_sample_id"), do: :canonical_sample_id
  defp atom_key("canonical_revision"), do: :canonical_revision
  defp atom_key("decision_reason"), do: :decision_reason
  defp atom_key("correction_workflow_id"), do: :correction_workflow_id
  defp atom_key("authority"), do: :authority
  defp atom_key("confirmed"), do: :confirmed
  defp atom_key("source_decision_event_id"), do: :source_decision_event_id
  defp atom_key("source_target"), do: :source_target
  defp atom_key("source_target_id"), do: :source_target_id
  defp atom_key("source_link_label"), do: :source_link_label
  defp atom_key("source_decision"), do: :source_decision
  defp atom_key("dashboard_time_mode"), do: :dashboard_time_mode
  defp atom_key("dashboard_replay_run_id"), do: :dashboard_replay_run_id
  defp atom_key("dashboard_data_view"), do: :dashboard_data_view
  defp atom_key("dashboard_limit_mode"), do: :dashboard_limit_mode
  defp atom_key("comparison_state"), do: :comparison_state
  defp atom_key("comparison_delta"), do: :comparison_delta
  defp atom_key("primary_sample_id"), do: :primary_sample_id
  defp atom_key("compare_sample_id"), do: :compare_sample_id
  defp atom_key("primary_data_view"), do: :primary_data_view
  defp atom_key("compare_data_view"), do: :compare_data_view
  defp atom_key("primary_data_management"), do: :primary_data_management
  defp atom_key("compare_data_management"), do: :compare_data_management
  defp atom_key("primary_count"), do: :primary_count
  defp atom_key("compare_count"), do: :compare_count
  defp atom_key("widget_id"), do: :widget_id
  defp atom_key("widget_title"), do: :widget_title

  defp user_id(%{user: %{id: id}}) when is_binary(id), do: id
  defp user_id(%{user: %{user_id: id}}) when is_binary(id), do: id
  defp user_id(_scope), do: nil

  defp integer_param(value) when is_integer(value), do: value

  defp integer_param(value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {integer, ""} -> integer
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

  defp empty_to_nil(map) when map == %{}, do: nil
  defp empty_to_nil(map), do: map
end
