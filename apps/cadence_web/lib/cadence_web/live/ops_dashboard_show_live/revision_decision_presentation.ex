defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentation do
  @moduledoc false

  def build(context) when is_map(context) do
    %{
      form_params: form_params(context),
      options: options(),
      effects: effects(),
      default_effect: effect("mark_conflict")
    }
  end

  def build(_context), do: build(%{})

  def controls_available?(context) when is_map(context) do
    Enum.all?(
      [
        Map.get(context, :observation_identity_id),
        Map.get(context, :realm),
        Map.get(context, :data_source_id),
        Map.get(context, :source_binding_id)
      ],
      &present_text?/1
    )
  end

  def controls_available?(_context), do: false

  def form_params(context) when is_map(context) do
    %{
      "source_decision_event_id" => context_value(context, :source_decision_event_id),
      "source_target" => context_value(context, :source_target),
      "source_target_id" => context_value(context, :source_target_id),
      "source_link_label" => context_value(context, :source_link_label),
      "observation_identity_id" => context_value(context, :observation_identity_id),
      "source_decision" => context_value(context, :source_decision),
      "dashboard_time_mode" => context_value(context, :dashboard_time_mode),
      "dashboard_replay_run_id" => context_value(context, :dashboard_replay_run_id),
      "dashboard_data_view" => context_value(context, :dashboard_data_view),
      "dashboard_limit_mode" => context_value(context, :dashboard_limit_mode),
      "decision" => "mark_conflict",
      "realm" => context_value(context, :realm),
      "data_source_id" => context_value(context, :data_source_id),
      "source_binding_id" => context_value(context, :source_binding_id),
      "canonical_observation_id" => context_value(context, :canonical_observation_id),
      "canonical_sample_id" => context_value(context, :canonical_sample_id),
      "canonical_revision" => context_value(context, :canonical_revision),
      "decision_reason" => context_value(context, :decision_reason),
      "correction_workflow_id" => context_value(context, :correction_workflow_id),
      "authority" => context_value(context, :authority),
      "comparison_state" => context_value(context, :comparison_state),
      "comparison_delta" => context_value(context, :comparison_delta),
      "primary_sample_id" => context_value(context, :primary_sample_id),
      "compare_sample_id" => context_value(context, :compare_sample_id),
      "primary_data_view" => context_value(context, :primary_data_view),
      "compare_data_view" => context_value(context, :compare_data_view),
      "primary_count" => context_value(context, :primary_count),
      "compare_count" => context_value(context, :compare_count),
      "widget_id" => context_value(context, :widget_id),
      "widget_title" => context_value(context, :widget_title),
      "confirmed" => nil
    }
  end

  defp options do
    [
      {"Mark conflict", "mark_conflict"},
      {"Mark canonical", "mark_canonical"},
      {"Mark superseded", "mark_superseded"},
      {"Mark advisory", "mark_advisory"}
    ]
  end

  defp effects do
    [
      effect_row("mark_conflict", "Conflict"),
      effect_row("mark_canonical", "Canonical"),
      effect_row("mark_superseded", "Superseded"),
      effect_row("mark_advisory", "Advisory")
    ]
  end

  defp effect_row(value, label) do
    %{
      value: value,
      label: label,
      effect: effect(value),
      class: effect_class(value)
    }
  end

  defp effect("mark_canonical"),
    do: "sets this identity canonical for default dashboard reads"

  defp effect("mark_conflict"),
    do: "removes this identity from canonical reads until resolved"

  defp effect("mark_superseded"),
    do: "marks this identity superseded by a correction"

  defp effect("mark_advisory"),
    do: "keeps this identity as advisory history only"

  defp effect(_decision), do: nil

  defp effect_class("mark_canonical"), do: "border-success/30 bg-success/10"
  defp effect_class("mark_conflict"), do: "border-warning/30 bg-warning/10"
  defp effect_class("mark_superseded"), do: "border-info/30 bg-info/10"
  defp effect_class("mark_advisory"), do: "border-base-300 bg-base-100/70"

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
