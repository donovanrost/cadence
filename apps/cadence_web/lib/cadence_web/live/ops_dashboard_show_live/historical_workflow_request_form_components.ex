defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :form, Phoenix.HTML.Form, required: true

  def request_form(assigns) do
    assigns = assign(assigns, :preview_rows, request_preview_rows(assigns.form))

    ~H"""
    <.form
      for={@form}
      id="dashboard-historical-workflow-request-form"
      phx-submit="record_historical_workflow_request"
      class="space-y-3"
    >
      <input type="hidden" name={@form[:dashboard_id].name} value={@form[:dashboard_id].value} />
      <input
        type="hidden"
        name={@form[:dashboard_version].name}
        value={@form[:dashboard_version].value}
      />
      <input
        type="hidden"
        name={@form[:dashboard_time_mode].name}
        value={@form[:dashboard_time_mode].value}
      />
      <input
        type="hidden"
        name={@form[:dashboard_replay_run_id].name}
        value={@form[:dashboard_replay_run_id].value}
      />
      <input
        type="hidden"
        name={@form[:dashboard_data_view].name}
        value={@form[:dashboard_data_view].value}
      />
      <input
        type="hidden"
        name={@form[:dashboard_limit_mode].name}
        value={@form[:dashboard_limit_mode].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_request_event_id].name}
        value={@form[:comparison_review_request_event_id].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_request_kind].name}
        value={@form[:comparison_review_request_kind].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_open_count].name}
        value={@form[:comparison_review_open_count].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_open_placement_ids].name}
        value={@form[:comparison_review_open_placement_ids].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_workflow_kind].name}
        value={@form[:comparison_review_workflow_kind].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_workflow_action].name}
        value={@form[:comparison_review_workflow_action].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_workflow_selection_kind].name}
        value={@form[:comparison_review_workflow_selection_kind].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_workflow_selection_count].name}
        value={@form[:comparison_review_workflow_selection_count].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_primary_data_view].name}
        value={@form[:comparison_review_primary_data_view].value}
      />
      <input
        type="hidden"
        name={@form[:comparison_review_compare_data_view].name}
        value={@form[:comparison_review_compare_data_view].value}
      />
      <section
        id="dashboard-historical-workflow-request-preview"
        class="space-y-2 rounded border border-info/30 bg-info/10 p-2 text-xs"
      >
        <h3 class="hud-label">Request Preview</h3>
        <dl class="grid grid-cols-[minmax(5.5rem,auto)_1fr] gap-x-3 gap-y-1">
          <div
            :for={row <- @preview_rows}
            class="contents"
            data-preview-field={row.field}
          >
            <dt class="text-base-content/60">{row.label}</dt>
            <dd class="min-w-0 truncate text-base-content" title={row.value}>{row.value}</dd>
          </div>
        </dl>
      </section>
      <section class="space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs">
        <h3 class="hud-label">Request Context</h3>
        <.input
          field={@form[:workflow]}
          type="select"
          label="Workflow"
          options={[{"Backfill", "backfill"}, {"Import", "import"}]}
          compact
        />
        <.input field={@form[:run_id]} type="text" label="Run" compact />
        <div class="grid grid-cols-1 gap-2">
          <.input field={@form[:realm]} type="text" label="Realm" compact />
          <.input field={@form[:data_source_id]} type="text" label="Data Source" compact />
          <.input field={@form[:source_binding_id]} type="text" label="Source Binding" compact />
        </div>
      </section>
      <section class="space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs">
        <h3 class="hud-label">Source Window</h3>
        <.input field={@form[:observable_id]} type="text" label="Observable" compact />
        <.input field={@form[:point_id]} type="text" label="Point" compact />
        <.input
          field={@form[:point_ids]}
          type="text"
          label="Points"
          placeholder="Comma, space, or newline separated point IDs"
          compact
        />
        <.input field={@form[:source_from]} type="text" label="Source From" compact />
        <.input field={@form[:source_to]} type="text" label="Source To" compact />
        <.input field={@form[:reason]} type="text" label="Reason" compact />
      </section>
      <label
        id="dashboard-historical-workflow-request-confirm-row"
        class="flex items-start gap-2 rounded border border-warning/40 bg-warning/10 p-2 text-xs"
      >
        <input
          id="dashboard-historical-workflow-request-confirm"
          type="checkbox"
          name={@form[:confirmed].name}
          value="confirmed"
          required
          class="checkbox checkbox-xs mt-0.5"
        />
        <span class="text-base-content/80">
          Confirm historical data workflow request
        </span>
      </label>
      <button
        id="dashboard-historical-workflow-request-submit"
        type="submit"
        class="btn btn-xs btn-primary w-full justify-start"
      >
        <.icon name="hero-document-plus" class="h-3.5 w-3.5" /> Record request
      </button>
    </.form>
    """
  end

  defp request_preview_rows(form) do
    workflow = form_value(form, :workflow)

    [
      %{field: "workflow", label: "Workflow", value: workflow_label(workflow)},
      %{field: "effect", label: "Effect", value: workflow_effect(workflow)},
      %{field: "points", label: "Points", value: points_preview(form)},
      %{field: "source", label: "Source", value: source_preview(form)},
      %{field: "window", label: "Window", value: window_preview(form)},
      %{field: "dashboard", label: "Dashboard", value: dashboard_preview(form)},
      %{field: "runtime", label: "Runtime", value: runtime_preview(form)},
      %{field: "comparison", label: "Comparison", value: comparison_preview(form)}
    ]
  end

  defp workflow_label("import"), do: "Import"
  defp workflow_label("backfill"), do: "Backfill"
  defp workflow_label(value), do: text_or_dash(value)

  defp workflow_effect("import"),
    do: "Create import request event; samples are written after start."

  defp workflow_effect(_workflow),
    do: "Create backfill request event; samples are written after start."

  defp points_preview(form) do
    form
    |> form_value(:point_ids)
    |> split_point_ids()
    |> case do
      [] ->
        form
        |> form_value(:point_id)
        |> text_or_dash()

      [point_id] ->
        point_id

      point_ids ->
        "#{length(point_ids)} points: #{Enum.join(point_ids, ", ")}"
    end
  end

  defp source_preview(form) do
    [
      form_value(form, :realm),
      form_value(form, :data_source_id),
      form_value(form, :source_binding_id)
    ]
    |> text_join()
  end

  defp window_preview(form) do
    [form_value(form, :source_from), form_value(form, :source_to)]
    |> text_join(" -> ")
  end

  defp dashboard_preview(form) do
    case {form_value(form, :dashboard_id), form_value(form, :dashboard_version)} do
      {nil, nil} -> "-"
      {dashboard_id, nil} -> dashboard_id
      {nil, version} -> "v#{version}"
      {dashboard_id, version} -> "#{dashboard_id} v#{version}"
    end
  end

  defp runtime_preview(form) do
    [
      form_value(form, :dashboard_time_mode),
      form_value(form, :dashboard_replay_run_id),
      form_value(form, :dashboard_data_view),
      form_value(form, :dashboard_limit_mode)
    ]
    |> text_join()
  end

  defp comparison_preview(form) do
    [
      form_value(form, :comparison_review_workflow_kind),
      form_value(form, :comparison_review_workflow_action),
      form_value(form, :comparison_review_workflow_selection_count),
      form_value(form, :comparison_review_primary_data_view),
      form_value(form, :comparison_review_compare_data_view)
    ]
    |> text_join()
  end

  defp split_point_ids(nil), do: []

  defp split_point_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp split_point_ids(_value), do: []

  defp text_join(values, separator \\ " / ") do
    values
    |> Enum.map(&text_param/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "-"
      values -> Enum.join(values, separator)
    end
  end

  defp text_or_dash(value), do: text_param(value) || "-"

  defp form_value(form, field) do
    form
    |> then(& &1[field])
    |> Map.get(:value)
    |> text_param()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(value) when is_atom(value), do: Atom.to_string(value)
  defp text_param(value) when is_integer(value), do: Integer.to_string(value)
  defp text_param(_value), do: nil
end
