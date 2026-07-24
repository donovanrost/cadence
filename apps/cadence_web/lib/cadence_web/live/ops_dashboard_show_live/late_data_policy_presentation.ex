defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentation do
  alias Cadence.Telemetry.DataManagement, as: DataManagement

  @moduledoc false

  @sample_accept_effect "canonical history; refreshes current/latest projections"
  @event_only_accept_effect "auditable policy decision; telemetry projections unchanged"
  @reject_effect "advisory history only; current/latest projections unchanged"

  def build(context) when is_map(context) do
    execution_mode = execution_mode(context)

    %{
      form_params: form_params(context),
      execution_mode: execution_mode,
      execution_label: execution_label(execution_mode),
      execution_badge_class: execution_badge_class(execution_mode),
      accept_effect: accept_effect(execution_mode),
      reject_effect: @reject_effect,
      decision_options: decision_options(),
      authority_options: authority_options()
    }
  end

  def build(_context), do: build(%{})

  def controls_available?(context) when is_map(context) do
    Enum.all?(
      [
        Map.get(context, :source_event_id),
        Map.get(context, :run_id),
        Map.get(context, :realm),
        Map.get(context, :data_source_id),
        Map.get(context, :source_binding_id)
      ],
      &present_text?/1
    ) and not policy_event?(Map.get(context, :source_event_type))
  end

  def controls_available?(_context), do: false

  def form_params(context) when is_map(context) do
    %{
      "execution_mode" => execution_mode(context),
      "source_event_id" => context_value(context, :source_event_id),
      "source_event_type" => context_value(context, :source_event_type),
      "run_id" => context_value(context, :run_id),
      "dashboard_time_mode" => context_value(context, :dashboard_time_mode),
      "dashboard_replay_run_id" => context_value(context, :dashboard_replay_run_id),
      "dashboard_data_view" => context_value(context, :dashboard_data_view),
      "dashboard_limit_mode" => context_value(context, :dashboard_limit_mode),
      "realm" => context_value(context, :realm),
      "data_source_id" => context_value(context, :data_source_id),
      "source_binding_id" => context_value(context, :source_binding_id),
      "observable_id" => context_value(context, :observable_id),
      "point_id" => context_value(context, :point_id),
      "source_from" => context_value(context, :source_from),
      "source_to" => context_value(context, :source_to),
      "receipt_from" => context_value(context, :receipt_from),
      "receipt_to" => context_value(context, :receipt_to),
      "sample_count" => context_value(context, :sample_count),
      "decision" => "accept",
      "authority" => default_authority(context),
      "reason" => default_reason(context),
      "confirmed" => nil
    }
  end

  defp decision_options do
    [{"Accept late data", "accept"}, {"Reject late data", "reject"}]
  end

  defp authority_options do
    [
      {"Authoritative", "authoritative"},
      {"Advisory", "advisory"},
      {"Comparison", "comparison"}
    ]
  end

  defp default_authority(%{authority: authority})
       when authority in ["authoritative", "advisory", "comparison"],
       do: authority

  defp default_authority(_context), do: "authoritative"

  defp default_reason(%{source_event_type: source_event_type})
       when is_binary(source_event_type) and source_event_type != "" do
    "dashboard_late_data_policy_for_#{source_event_type}"
  end

  defp default_reason(_context), do: "dashboard_late_data_policy"

  defp policy_event?(event_type) when is_binary(event_type),
    do: String.starts_with?(event_type, "late_data_")

  defp policy_event?(_event_type), do: false

  defp execution_mode(%{dashboard_time_mode: "replay_run"}), do: "event_only"
  defp execution_mode(%{"dashboard_time_mode" => "replay_run"}), do: "event_only"

  defp execution_mode(context) when is_map(context) do
    context
    |> DataManagement.late_data_policy_execution_mode()
    |> Atom.to_string()
  end

  defp accept_effect("sample_execution"), do: @sample_accept_effect
  defp accept_effect(_mode), do: @event_only_accept_effect

  defp execution_label("sample_execution"), do: "Sample execution"
  defp execution_label(_mode), do: "Event only"

  defp execution_badge_class("sample_execution"), do: "badge-success badge-outline"
  defp execution_badge_class(_mode), do: "badge-warning badge-outline"

  defp context_value(context, key) when is_map(context) do
    context
    |> Map.get(key)
    |> text_value()
  end

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp present_text?(value), do: is_binary(value) and value != ""
end
