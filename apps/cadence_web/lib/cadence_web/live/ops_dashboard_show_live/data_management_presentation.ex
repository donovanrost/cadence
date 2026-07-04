defmodule CadenceWeb.OpsDashboardShowLive.DataManagementPresentation do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames}

  @spec frame(Frame.t()) :: map() | nil
  def frame(%Frame{meta: meta}) when is_map(meta) do
    source_context =
      meta
      |> context_value(:source_request_context)
      |> request_context_or_empty()

    data_view =
      context_value(meta, :data_view) ||
        context_value(source_context, :requested_data_view)

    warning_codes =
      meta
      |> context_value(:warning_codes)
      |> List.wrap()
      |> Enum.map(&warning_code_atom/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    badges =
      [
        data_view_badge(data_view),
        analysis_basis_badge(context_value(meta, :analysis_basis)),
        source_health_badge(meta),
        realm_badge(
          context_value(meta, :realm) || context_value(source_context, :requested_realm)
        ),
        replay_badge(meta, source_context)
      ]
      |> Kernel.++(revision_state_badges(meta))
      |> Kernel.++(historical_workflow_badges(meta))
      |> Kernel.++(Enum.map(warning_codes, &warning_code_badge/1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&badge_key/1)

    if is_nil(data_view) and warning_codes == [] and badges == [] do
      nil
    else
      %{
        data_view: data_view && value_text(data_view),
        warning_codes: Enum.map(warning_codes, &Atom.to_string/1),
        badges: badges
      }
    end
  end

  def frame(%Frame{}), do: nil

  @spec placement(PlacementFrames.t()) :: map() | nil
  def placement(%PlacementFrames{primary: frames}) when is_list(frames) do
    Enum.find_value(frames, &frame/1)
  end

  def placement(%PlacementFrames{}), do: nil

  @spec aggregate_rows([map()]) :: map() | nil
  def aggregate_rows(rows) when is_list(rows) do
    rows
    |> Enum.map(&Map.get(&1, :data_management))
    |> aggregate_summaries()
  end

  @spec event_row(map()) :: map() | nil
  def event_row(row) when is_map(row) do
    badges =
      row
      |> event_row_badges()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&badge_key/1)

    if badges == [] do
      nil
    else
      %{
        data_view: nil,
        warning_codes: [],
        badges: badges
      }
    end
  end

  defp aggregate_summaries(summaries) do
    summaries
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      summaries ->
        badges =
          summaries
          |> Enum.flat_map(& &1.badges)
          |> Enum.uniq_by(&badge_key/1)

        %{
          data_views:
            summaries
            |> Enum.map(& &1.data_view)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq(),
          warning_codes:
            summaries
            |> Enum.flat_map(& &1.warning_codes)
            |> Enum.uniq(),
          badges: badges
        }
    end
  end

  defp data_view_badge(view) when view in [:as_recorded, "as_recorded"] do
    badge(:data_view, "as_recorded", "As recorded", :attention, :as_recorded_view)
  end

  defp data_view_badge(view) when view in [:all_revisions, "all_revisions"] do
    badge(:data_view, "all_revisions", "All revisions", :attention, :all_revisions_view)
  end

  defp data_view_badge(view) when view in [:recomputed, "recomputed"] do
    badge(:data_view, "recomputed", "Recomputed", :attention, :recomputed_values)
  end

  defp data_view_badge(_view), do: nil

  defp analysis_basis_badge(basis) when basis in [:recomputed_analysis, "recomputed_analysis"] do
    badge(
      :analysis_basis,
      "recomputed_analysis",
      "Recomputed analysis",
      :attention,
      :recomputed_analysis
    )
  end

  defp analysis_basis_badge(_basis), do: nil

  defp realm_badge(realm) when realm in [:replay, "replay"] do
    badge(:realm, "replay", "Replay", :info, :replay_data)
  end

  defp realm_badge(realm) when realm in [:simulation, "simulation"] do
    badge(:realm, "simulation", "Simulation", :info, :simulation_data)
  end

  defp realm_badge(_realm), do: nil

  defp replay_badge(meta, source_context) do
    if replay_context?(meta, source_context) do
      badge(:time_mode, "replay_run", "Replay", :info, :replay_data)
    end
  end

  defp replay_context?(meta, source_context) do
    not is_nil(context_value(meta, :replay_run_id)) ||
      not is_nil(context_value(source_context, :replay_run_id)) ||
      context_value(source_context, :time_mode) in [:replay_run, "replay_run"]
  end

  defp warning_code_badge(:as_recorded_view), do: data_view_badge(:as_recorded)
  defp warning_code_badge(:all_revisions_view), do: data_view_badge(:all_revisions)
  defp warning_code_badge(:recomputed_values), do: data_view_badge(:recomputed)

  defp warning_code_badge(:corrected_range) do
    badge(:revision_state, "corrected", "Corrected", :warning, :corrected_range)
  end

  defp warning_code_badge(:advisory_backfill) do
    badge(:revision_state, "backfill", "Backfill", :warning, :advisory_backfill)
  end

  defp warning_code_badge(:late_arrival) do
    badge(:revision_state, "late", "Late", :attention, :late_arrival)
  end

  defp warning_code_badge(:partial_data) do
    badge(:revision_state, "partial", "Partial", :warning, :partial_data)
  end

  defp warning_code_badge(:conflicting_observations) do
    badge(:revision_state, "conflict", "Conflict", :warning, :conflicting_observations)
  end

  defp warning_code_badge(:mixed_revisions) do
    badge(:revision_state, "mixed", "Mixed", :attention, :mixed_revisions)
  end

  defp warning_code_badge(_code), do: nil

  defp event_row_badges(row) do
    category = context_value(row, :category)
    kind = context_value(row, :kind)

    cond do
      category in [:telemetry_backfill, "telemetry_backfill"] ->
        [backfill_workflow_badge(kind, row)]

      category in [:telemetry_revision, "telemetry_revision"] ->
        [correction_workflow_badge(kind)]

      category in [:source_watermark, "source_watermark"] ->
        [source_watermark_badge(kind, row)]

      true ->
        []
    end
  end

  defp historical_workflow_badges(meta) when is_map(meta) do
    meta
    |> historical_workflow_rows()
    |> Enum.flat_map(&event_row_badges/1)
  end

  defp historical_workflow_rows(meta) do
    [
      context_value(meta, :historical_workflows),
      context_value(meta, :active_historical_workflows),
      context_value(meta, :historical_workflow_outcomes)
    ]
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.filter(&is_map/1)
  end

  defp backfill_workflow_badge(kind, row) do
    kind
    |> value_text()
    |> String.split("_", parts: 2)
    |> case do
      [workflow, stage] when workflow in ["backfill", "import"] ->
        badge(
          :historical_workflow,
          workflow_badge_value(workflow, stage, row),
          workflow_badge_label(workflow, stage, row),
          workflow_badge_status(stage, row),
          workflow_badge_code(workflow, stage, row)
        )
        |> put_workflow_link(row)
        |> put_workflow_job_context(row)

      ["late", "data_" <> stage] ->
        badge(
          :historical_workflow,
          "late_data_#{stage}",
          "Late data #{String.replace(stage, "_", " ")}",
          workflow_stage_status(stage),
          "late_data_#{stage}"
        )
        |> put_workflow_link(row)
        |> put_policy_execution_summary(row)

      _other ->
        nil
    end
  end

  defp correction_workflow_badge(kind) do
    case value_text(kind) do
      "mark_canonical" ->
        badge(
          :historical_workflow,
          "correction_canonical",
          "Correction canonical",
          :info,
          :mark_canonical
        )

      "mark_conflict" ->
        badge(
          :historical_workflow,
          "correction_conflict",
          "Correction conflict",
          :warning,
          :mark_conflict
        )

      "mark_superseded" ->
        badge(
          :historical_workflow,
          "correction_superseded",
          "Correction superseded",
          :warning,
          :mark_superseded
        )

      "mark_advisory" ->
        badge(
          :historical_workflow,
          "correction_advisory",
          "Correction advisory",
          :info,
          :mark_advisory
        )

      _other ->
        nil
    end
  end

  defp source_watermark_badge(kind, row) do
    status =
      case context_value(row, :severity) do
        severity when severity in [:error, "error"] -> :error
        severity when severity in [:warning, "warning"] -> :warning
        _severity -> :info
      end

    kind_text =
      kind
      |> value_text()
      |> String.replace("_", " ")

    badge(:source_freshness, value_text(kind), "Watermark #{kind_text}", status, kind)
    |> put_source_watermark_link(row)
  end

  defp source_health_badge(meta) when is_map(meta) do
    source_health = context_value(meta, :source_health)
    freshness = context_value(meta, :source_health_freshness)
    event_id = context_value(meta, :source_health_event_id)

    cond do
      source_health in [:unavailable, "unavailable"] ->
        source_health_badge(meta, "unavailable", "Source unavailable", :error)

      source_health in [:degraded, "degraded"] ->
        source_health_badge(meta, "degraded", "Source degraded", :warning)

      source_health in [:unknown, "unknown"] ->
        source_health_badge(meta, "unknown", "Source unknown", :warning)

      freshness in [:stale, "stale"] ->
        source_health_badge(meta, "stale", "Source health stale", :warning)

      freshness in [:missing, "missing"] ->
        source_health_badge(meta, "missing", "Source health missing", :warning)

      source_health in [:healthy, "healthy"] and event_id_present?(event_id) ->
        source_health_badge(meta, "healthy", "Source healthy", :info)

      true ->
        nil
    end
  end

  defp source_health_badge(meta, value, label, status) do
    reason = context_value(meta, :source_health_reason)

    badge(:source_health, value, label, status, reason || value)
    |> put_source_health_link(meta)
    |> maybe_put_source_health_summary(meta)
  end

  defp workflow_stage_status(stage) when stage in ["failed", "rejected"], do: :warning

  defp workflow_stage_status(stage) when stage in ["requested", "approved", "started"],
    do: :attention

  defp workflow_stage_status(_stage), do: :info

  defp workflow_badge_value(workflow, "started", row) do
    if workflow_job_failed?(row) do
      "#{workflow}_started_dispatch_degraded"
    else
      "#{workflow}_started"
    end
  end

  defp workflow_badge_value(workflow, stage, _row), do: "#{workflow}_#{stage}"

  defp workflow_badge_label(workflow, "started", row) do
    if workflow_job_failed?(row) do
      "#{String.capitalize(workflow)} dispatch failed"
    else
      "#{String.capitalize(workflow)} started"
    end
  end

  defp workflow_badge_label(workflow, stage, _row) do
    "#{String.capitalize(workflow)} #{String.replace(stage, "_", " ")}"
  end

  defp workflow_badge_status("started", row) do
    if workflow_job_failed?(row), do: :warning, else: workflow_stage_status("started")
  end

  defp workflow_badge_status(stage, _row), do: workflow_stage_status(stage)

  defp workflow_badge_code(workflow, stage, row), do: workflow_badge_value(workflow, stage, row)

  defp workflow_job_failed?(row) when is_map(row) do
    context_value(row, :workflow_job_status) in [:failed, "failed"] or
      context_value(row, :job_status) in [:failed, "failed"]
  end

  defp workflow_job_failed?(_row), do: false

  defp revision_state_badges(meta) when is_map(meta) do
    revision_state =
      meta
      |> context_value(:revision_state)
      |> request_context_or_empty()

    [
      revision_badge(
        revision_state,
        :has_superseded?,
        :superseded_count,
        :corrected_range
      ),
      revision_badge(
        revision_state,
        :has_advisory?,
        :advisory_count,
        :advisory_backfill
      ),
      revision_badge(
        revision_state,
        :has_conflicts?,
        :conflict_count,
        :conflicting_observations
      ),
      revision_badge(
        revision_state,
        :mixed_revisions?,
        :identity_count,
        :mixed_revisions,
        &mixed_revision_state?/1
      )
    ]
  end

  defp revision_badge(revision_state, flag_key, count_key, warning_code, predicate \\ nil) do
    cond do
      revision_state == %{} ->
        nil

      is_function(predicate, 1) and predicate.(revision_state) ->
        warning_code_badge(warning_code)

      truthy?(context_value(revision_state, flag_key)) ->
        warning_code_badge(warning_code)

      positive?(context_value(revision_state, count_key)) ->
        warning_code_badge(warning_code)

      true ->
        nil
    end
  end

  defp mixed_revision_state?(revision_state) when is_map(revision_state) do
    Enum.any?(
      [:has_conflicts?, :has_duplicates?, :has_superseded?, :has_advisory?],
      &truthy?(context_value(revision_state, &1))
    ) or
      Enum.any?(
        [:conflict_count, :duplicate_count, :superseded_count, :advisory_count],
        &positive?(context_value(revision_state, &1))
      )
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp positive?(count) when is_integer(count), do: count > 0

  defp positive?(count) when is_binary(count) do
    case Integer.parse(count) do
      {value, ""} -> value > 0
      _other -> false
    end
  end

  defp positive?(_count), do: false

  defp badge(kind, value, label, status, code) do
    %{
      kind: kind,
      value: value,
      label: label,
      status: status,
      code: code_text(code)
    }
  end

  defp put_workflow_link(badge, row) when is_map(row) do
    case context_value(row, :source_record_id) || context_value(row, :backfill_lifecycle_event_id) do
      event_id when is_binary(event_id) and event_id != "" ->
        badge
        |> Map.put(:data_link_target, :telemetry_backfill_lifecycle_event)
        |> Map.put(:data_link_id, event_id)
        |> put_workflow_context(row)

      _missing ->
        badge
    end
  end

  defp put_workflow_link(badge, _row), do: badge

  defp put_source_watermark_link(badge, row) when is_map(row) do
    case context_value(row, :source_record_id) || context_value(row, :source_watermark_event_id) do
      event_id when is_binary(event_id) and event_id != "" ->
        badge
        |> Map.put(:data_link_target, :source_watermark_event)
        |> Map.put(:data_link_id, event_id)
        |> put_workflow_context(row)

      _missing ->
        badge
    end
  end

  defp put_source_watermark_link(badge, _row), do: badge

  defp put_source_health_link(badge, row) when is_map(row) do
    case context_value(row, :source_health_event_id) do
      event_id when is_binary(event_id) and event_id != "" ->
        badge
        |> Map.put(:data_link_target, :source_health_event)
        |> Map.put(:data_link_id, event_id)
        |> put_workflow_context(row)

      _missing ->
        badge
    end
  end

  defp put_source_health_link(badge, _row), do: badge

  defp maybe_put_source_health_summary(badge, row) do
    case source_health_summary_text(row) do
      nil -> badge
      summary -> Map.put(badge, :summary, summary)
    end
  end

  defp source_health_summary_text(row) do
    [
      source_health_reason_summary(row),
      source_health_freshness_summary(row),
      source_health_age_summary(row)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  defp source_health_reason_summary(row) do
    case context_value(row, :source_health_reason) do
      nil -> nil
      reason -> "reason #{value_text(reason)}"
    end
  end

  defp source_health_freshness_summary(row) do
    case context_value(row, :source_health_freshness) do
      nil -> nil
      freshness -> "freshness #{value_text(freshness)}"
    end
  end

  defp source_health_age_summary(row) do
    age_ms = context_value(row, :source_health_age_ms)
    max_age_ms = context_value(row, :source_health_max_age_ms)

    cond do
      is_nil(age_ms) ->
        nil

      is_nil(max_age_ms) ->
        "age #{age_ms}ms"

      true ->
        "age #{age_ms}ms of #{max_age_ms}ms"
    end
  end

  defp put_workflow_context(badge, row) do
    [
      {:realm, [:realm, :requested_realm]},
      {:data_view, [:data_view, :requested_data_view]},
      {:data_source_id, [:data_source_id, :requested_data_source_id]},
      {:source_binding_id, [:source_binding_id, :binding_id, :requested_source_binding_id]},
      {:time_mode, [:time_mode]},
      {:time_axis, [:time_axis]},
      {:replay_run_id, [:replay_run_id]}
    ]
    |> Enum.reduce(badge, fn {badge_key, row_keys}, acc ->
      case first_context_value(row, row_keys) do
        nil -> acc
        value -> Map.put(acc, badge_key, value_text(value))
      end
    end)
  end

  defp put_workflow_job_context(badge, row) when is_map(badge) and is_map(row) do
    [
      {:workflow_run_id, [:workflow_run_id, :run_id, :backfill_run_id]},
      {:workflow_job_id, [:workflow_job_id, :job_id]},
      {:workflow_job_status, [:workflow_job_status, :job_status]},
      {:workflow_job_failure, [:workflow_job_failure, :job_failure, :failure_reason]}
    ]
    |> Enum.reduce(badge, fn {badge_key, row_keys}, acc ->
      case first_context_value(row, row_keys) do
        nil -> acc
        value -> Map.put(acc, badge_key, value_text(value))
      end
    end)
    |> maybe_put_workflow_job_summary(row)
  end

  defp put_workflow_job_context(badge, _row), do: badge

  defp maybe_put_workflow_job_summary(badge, row) do
    case workflow_job_summary_text(row) do
      nil -> badge
      summary -> Map.put(badge, :summary, summary)
    end
  end

  defp workflow_job_summary_text(row) do
    status = first_context_value(row, [:workflow_job_status, :job_status])
    failure = first_context_value(row, [:workflow_job_failure, :job_failure, :failure_reason])

    cond do
      is_nil(status) ->
        nil

      is_nil(failure) or failure == "" ->
        "workflow job #{value_text(status)}"

      true ->
        "workflow job #{value_text(status)}: #{value_text(failure)}"
    end
  end

  defp first_context_value(row, keys) do
    Enum.find_value(keys, &context_value(row, &1))
  end

  defp put_policy_execution_summary(badge, row) when is_map(badge) and is_map(row) do
    [
      :selected_sample_count,
      :projection_effect,
      :write_validity_state,
      :record_current_values,
      :refresh_latest_value
    ]
    |> Enum.reduce(badge, fn key, acc ->
      value = context_value(row, key)

      if is_nil(value), do: acc, else: Map.put(acc, key, value)
    end)
    |> maybe_put_policy_execution_summary_text(row)
  end

  defp put_policy_execution_summary(badge, _row), do: badge

  defp maybe_put_policy_execution_summary_text(badge, row) do
    case policy_execution_summary_text(row) do
      nil -> badge
      summary -> Map.put(badge, :summary, summary)
    end
  end

  defp policy_execution_summary_text(row) do
    [
      selected_sample_count_summary(row),
      write_validity_summary(row),
      projection_refresh_summary(row),
      projection_effect_summary(row)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  defp selected_sample_count_summary(row) do
    case context_value(row, :selected_sample_count) do
      nil ->
        nil

      1 ->
        "1 selected sample"

      count ->
        "#{count} selected samples"
    end
  end

  defp write_validity_summary(row) do
    case context_value(row, :write_validity_state) do
      nil -> nil
      state -> "#{write_validity_verb(row)} #{value_text(state)} #{write_validity_noun(row)}"
    end
  end

  defp write_validity_verb(row) do
    if context_value(row, :projection_effect) == "audit_event_only", do: "records", else: "writes"
  end

  defp write_validity_noun(row) do
    if context_value(row, :projection_effect) == "audit_event_only",
      do: "audit decision",
      else: "history"
  end

  defp projection_refresh_summary(row) do
    current? = context_value(row, :record_current_values)
    latest? = context_value(row, :refresh_latest_value)

    cond do
      current? == true and latest? == true ->
        "refreshes current/latest"

      current? == false and latest? == false ->
        "does not refresh current/latest"

      current? == true ->
        "refreshes current"

      latest? == true ->
        "refreshes latest"

      true ->
        nil
    end
  end

  defp projection_effect_summary(row) do
    case context_value(row, :projection_effect) do
      nil -> nil
      effect -> "effect #{value_text(effect)}"
    end
  end

  defp badge_key(badge) when is_map(badge) do
    {
      Map.get(badge, :kind),
      Map.get(badge, :value),
      Map.get(badge, :code),
      Map.get(badge, :data_link_target),
      Map.get(badge, :data_link_id)
    }
  end

  defp code_text(nil), do: nil
  defp code_text(code) when is_atom(code), do: Atom.to_string(code)
  defp code_text(code) when is_binary(code), do: code

  defp warning_code_atom(code) when is_atom(code), do: code

  defp warning_code_atom(code) when is_binary(code) do
    code
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp warning_code_atom(_code), do: nil

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp request_context_or_empty(context) when is_map(context), do: context
  defp request_context_or_empty(_context), do: %{}

  defp event_id_present?(event_id), do: is_binary(event_id) and event_id != ""

  defp value_text(%{"tuple" => values}) when is_list(values) do
    Enum.map_join(values, ":", &value_text/1)
  end

  defp value_text(%{tuple: values}) when is_list(values) do
    Enum.map_join(values, ":", &value_text/1)
  end

  defp value_text(value) when is_atom(value), do: Atom.to_string(value)

  defp value_text(value) when is_list(value) do
    Enum.map_join(value, ",", &value_text/1)
  end

  defp value_text(value) when is_map(value) do
    Jason.encode!(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
    Jason.EncodeError -> inspect(value)
  end

  defp value_text(value), do: to_string(value)
end
