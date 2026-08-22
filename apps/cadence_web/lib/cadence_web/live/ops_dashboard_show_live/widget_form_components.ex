defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation

  attr :panel, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :binding_preview, :map, default: nil
  attr :spacecraft, :list, required: true
  attr :operational_observables, :list, required: true
  attr :filtered_points, :list, required: true
  attr :filtered_operational_observables, :list, required: true
  attr :points_empty?, :boolean, required: true
  attr :selected_point, :any, required: true
  attr :selected_points, :list, required: true
  attr :selected_operational_observables, :list, required: true
  attr :dashboard_scope_context, :any, required: true
  attr :dashboard_editor_focus, :map, default: nil
  attr :error, :string, required: true
  attr :mission_id, :string, required: true
  attr :dashboard_document, :any, default: %{sections: []}

  def widget_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="widget-form"
      phx-change="validate_widget"
      phx-submit="save_widget"
      class="space-y-4"
    >
      <.input
        field={@form[:type]}
        type="select"
        label="Widget Type"
        options={WidgetFormPresentation.type_options()}
      />
      <.input field={@form[:title]} type="text" label="Title" required />
      <.input
        :if={@dashboard_document.sections != []}
        field={@form[:section_id]}
        type="select"
        label="Operational section"
        options={section_options(@dashboard_document.sections)}
      />

      <%= if WidgetFormPresentation.point_widget?(@form) do %>
        <input
          type="hidden"
          name={@form[:scope_kind].name}
          value={WidgetFormPresentation.scope_override_kind(@dashboard_scope_context) || ""}
        />
        <input
          type="hidden"
          name={@form[:scope_id].name}
          value={WidgetFormPresentation.scope_override_id(@dashboard_scope_context) || ""}
        />
        <.input
          :if={WidgetFormPresentation.binding_source_select?(@form)}
          field={@form[:binding_source]}
          type="select"
          label="Binding Source"
          options={WidgetFormPresentation.binding_source_options(@form)}
        />
        <.input
          field={@form[:mode]}
          type="select"
          label="Widget Scope"
          options={WidgetFormPresentation.mode_options(@form)}
        />
        <p
          :if={WidgetFormPresentation.form_value(@form, :mode) == "scope"}
          class={[
            "flex items-start gap-1.5 rounded border px-2 py-1 text-xs",
            if(WidgetFormPresentation.scope_override_available?(@dashboard_scope_context),
              do: "border-primary/30 bg-primary/10 text-primary",
              else: "border-warning/40 bg-warning/10 text-warning"
            )
          ]}
          data-widget-scope-override
          data-widget-scope-override-kind={
            WidgetFormPresentation.scope_override_kind(@dashboard_scope_context) || ""
          }
          data-widget-scope-override-id={
            WidgetFormPresentation.scope_override_id(@dashboard_scope_context) || ""
          }
          data-widget-scope-override-state={
            if WidgetFormPresentation.scope_override_available?(@dashboard_scope_context),
              do: "ready",
              else: "missing_context"
          }
        >
          <.icon name="hero-map-pin" class="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>{WidgetFormPresentation.scope_override_summary(@dashboard_scope_context)}</span>
        </p>
        <.input
          :if={
            not WidgetFormPresentation.operational_observable_widget?(@form) and
              WidgetFormPresentation.form_value(@form, :mode) == "fixed"
          }
          field={@form[:spacecraft_id]}
          type="select"
          label="Spacecraft"
          options={WidgetFormPresentation.spacecraft_options(@spacecraft)}
        />
        <div
          :if={WidgetFormPresentation.form_value(@form, :mode) == "repeat"}
          id="widget-repeat-options"
          class="space-y-3 rounded border border-primary/30 bg-primary/5 p-3"
        >
          <div class="flex items-start gap-2 text-xs text-base-content/75">
            <.icon name="hero-squares-2x2" class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
            <p>
              Creates one scoped widget for each resource selected in the dashboard context.
              Instance IDs stay stable as the selection changes.
            </p>
          </div>
          <.input
            field={@form[:repeat_over]}
            type="select"
            label="Repeat domain"
            options={WidgetFormPresentation.repeat_over_options()}
          />
          <.input
            field={@form[:repeat_layout]}
            type="select"
            label="Instance layout"
            options={WidgetFormPresentation.repeat_layout_options()}
          />
          <.input
            field={@form[:repeat_max_instances]}
            type="select"
            label="Safety limit"
            options={WidgetFormPresentation.repeat_max_options()}
          />
        </div>
        <.point_picker
          :if={not WidgetFormPresentation.operational_observable_widget?(@form)}
          form={@form}
          filtered_points={@filtered_points}
          points_empty?={@points_empty?}
          selected_point={@selected_point}
          selected_points={@selected_points}
          mission_id={@mission_id}
        />
        <.operational_observable_picker
          :if={WidgetFormPresentation.operational_observable_widget?(@form)}
          form={@form}
          operational_observables={@operational_observables}
          filtered_operational_observables={@filtered_operational_observables}
          selected_operational_observables={@selected_operational_observables}
          dashboard_scope_context={@dashboard_scope_context}
          dashboard_editor_focus={@dashboard_editor_focus}
        />
        <.input
          field={@form[:precision]}
          type="select"
          label="Precision"
          options={WidgetFormPresentation.precision_options()}
        />
        <.input
          :if={WidgetFormPresentation.form_value(@form, :type) == "value_tile"}
          field={@form[:show_unit]}
          type="checkbox"
          label="Show engineering unit"
        />
        <.input
          :if={WidgetFormPresentation.form_value(@form, :type) == "time_series"}
          field={@form[:window_seconds]}
          type="select"
          label="Chart Window"
          options={WidgetFormPresentation.window_options()}
        />
        <div
          :if={WidgetFormPresentation.form_value(@form, :type) == "time_series"}
          id="time-series-presentation-options"
          class="space-y-3 rounded border border-base-300/60 bg-base-200/30 p-3"
        >
          <p class="hud-label">Chart presentation</p>
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@form[:legend_mode]}
              type="select"
              label="Legend"
              options={WidgetFormPresentation.legend_mode_options()}
            />
            <.input
              field={@form[:line_width]}
              type="select"
              label="Line width"
              options={WidgetFormPresentation.line_width_options()}
            />
            <.input
              field={@form[:fill_opacity]}
              type="select"
              label="Area fill"
              options={WidgetFormPresentation.fill_opacity_options()}
            />
            <.input
              field={@form[:axis_mode]}
              type="select"
              label="Value axes"
              options={WidgetFormPresentation.axis_mode_options()}
            />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <.input
              field={@form[:show_min_max_band]}
              type="checkbox"
              label="Show min/max band"
            />
            <.input field={@form[:show_points]} type="checkbox" label="Show point markers" />
            <.input field={@form[:span_gaps]} type="checkbox" label="Connect data gaps" />
            <.input
              field={@form[:shared_tooltip]}
              type="checkbox"
              label="Shared hover values"
            />
          </div>
        </div>
      <% else %>
        <p class="text-sm text-base-content/70">
          {WidgetFormPresentation.non_point_widget_help(@form)}
        </p>
      <% end %>

      <p :if={@error} class="text-sm text-error">{@error}</p>

      <.binding_preview preview={@binding_preview} />

      <div class="flex flex-wrap items-center gap-2 border-t border-base-300/60 pt-4">
        <.button
          id="test-widget-binding"
          type="button"
          size={:md}
          variant={:secondary}
          phx-click="preview_widget_binding"
        >
          <.icon name="hero-beaker" class="-ml-0.5 mr-1 h-4 w-4" /> Test binding
        </.button>
        <.button id="save-dashboard-widget" type="submit" size={:md}>
          {if match?({:edit_placement, _id}, @panel), do: "Save Widget", else: "Add Widget"}
        </.button>
      </div>
    </.form>
    """
  end

  attr :preview, :map, default: nil

  defp binding_preview(assigns) do
    ~H"""
    <div
      :if={@preview}
      id="widget-binding-preview"
      class={[
        "rounded border px-3 py-2",
        preview_class(@preview.status)
      ]}
      data-binding-preview-status={@preview.status}
    >
      <div class="flex items-start gap-2">
        <.icon name={preview_icon(@preview.status)} class="mt-0.5 h-4 w-4 shrink-0" />
        <div class="min-w-0">
          <p class="text-sm font-semibold">{@preview.title}</p>
          <p class="mt-0.5 text-xs opacity-80">{@preview.message}</p>
          <p class="mt-2 font-mono text-[0.65rem] uppercase tracking-wide opacity-65">
            {@preview.planned_request_count} requests / {@preview.frame_count} frames / {@preview.warning_count} warnings
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp preview_class(:ready), do: "border-success/40 bg-success/10 text-success"
  defp preview_class(:no_data), do: "border-warning/40 bg-warning/10 text-warning"
  defp preview_class(_status), do: "border-error/40 bg-error/10 text-error"

  defp preview_icon(:ready), do: "hero-check-circle"
  defp preview_icon(:no_data), do: "hero-information-circle"
  defp preview_icon(_status), do: "hero-exclamation-triangle"

  attr :form, Phoenix.HTML.Form, required: true
  attr :filtered_points, :list, required: true
  attr :points_empty?, :boolean, required: true
  attr :selected_point, :any, required: true
  attr :selected_points, :list, required: true
  attr :mission_id, :string, required: true

  defp point_picker(assigns) do
    ~H"""
    <fieldset class="space-y-2">
      <legend class="hud-label">{WidgetFormPresentation.point_picker_legend(@form)}</legend>
      <%= if @points_empty? do %>
        <p class="text-sm text-base-content/70">
          No telemetry points available. Activate packet definitions in
          <.link navigate={~p"/missions/#{@mission_id}/catalog"} class="text-primary hover:underline">
            Catalog
          </.link>
          / Telemetry Decom first.
        </p>
      <% else %>
        <div
          :if={not WidgetFormPresentation.multi_point_widget?(@form) and @selected_point}
          class="flex items-center gap-2 text-sm"
        >
          <span class="badge badge-primary badge-outline font-mono">{@selected_point.point_id}</span>
          <span :if={@selected_point.unit} class="text-base-content/60">
            {@selected_point.unit}
          </span>
        </div>
        <div
          :if={WidgetFormPresentation.multi_point_widget?(@form) and @selected_points != []}
          class="flex flex-wrap gap-1"
          data-selected-points
        >
          <button
            :for={point <- @selected_points}
            type="button"
            phx-click="pick_point"
            phx-value-point-id={point.point_id}
            class="badge badge-primary badge-outline gap-1 font-mono"
            data-selected-point={point.point_id}
            aria-label={"Remove #{point.point_id}"}
          >
            {point.point_id}
            <.icon name="hero-x-mark" class="h-3 w-3" />
          </button>
        </div>
        <.input
          field={@form[:point_q]}
          type="search"
          placeholder="Filter points by name or description"
          phx-debounce="150"
        />
        <ul class="max-h-48 space-y-1 overflow-y-auto rounded border border-base-300/60 p-1">
          <li :for={point <- @filtered_points}>
            <button
              type="button"
              phx-click="pick_point"
              phx-value-point-id={point.point_id}
              class={
                WidgetFormPresentation.point_button_class(
                  @form,
                  point,
                  @selected_points,
                  @selected_point
                )
              }
              aria-pressed={
                if WidgetFormPresentation.selected_point?(
                     @form,
                     point,
                     @selected_points,
                     @selected_point
                   ),
                   do: "true",
                   else: "false"
              }
              data-point-selected={
                if WidgetFormPresentation.selected_point?(
                     @form,
                     point,
                     @selected_points,
                     @selected_point
                   ),
                   do: "true",
                   else: "false"
              }
            >
              <.icon
                :if={
                  WidgetFormPresentation.selected_point?(
                    @form,
                    point,
                    @selected_points,
                    @selected_point
                  )
                }
                name="hero-check"
                class="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary"
              />
              <span class="font-mono">{point.point_id}</span>
              <span :if={point.unit} class="ml-2 text-base-content/60">{point.unit}</span>
              <span :if={point.description} class="ml-2 text-base-content/60">
                {point.description}
              </span>
            </button>
          </li>
          <li :if={@filtered_points == []} class="px-2 py-1 text-sm text-base-content/60">
            No points match the filter.
          </li>
        </ul>
      <% end %>
    </fieldset>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :operational_observables, :list, required: true
  attr :filtered_operational_observables, :list, required: true
  attr :selected_operational_observables, :list, required: true
  attr :dashboard_scope_context, :any, required: true
  attr :dashboard_editor_focus, :map, default: nil

  defp operational_observable_picker(assigns) do
    assigns =
      assigns
      |> assign(
        :readiness_focus_observable_ids,
        readiness_focus_observable_ids(assigns.dashboard_editor_focus)
      )
      |> assign(
        :readiness_capability_guidance,
        readiness_capability_guidance(assigns.dashboard_editor_focus)
      )
      |> assign(
        :selected_operational_scope_warning,
        WidgetFormPresentation.selected_operational_observable_scope_warning(
          assigns.selected_operational_observables,
          assigns.dashboard_scope_context
        )
      )
      |> assign(
        :selected_operational_scope_warning_ids,
        assigns.selected_operational_observables
        |> WidgetFormPresentation.unsupported_selected_operational_observable_ids(
          assigns.dashboard_scope_context
        )
        |> Enum.join(" ")
      )
      |> assign(
        :operational_observable_groups,
        WidgetFormPresentation.operational_observable_picker_groups(
          assigns.filtered_operational_observables,
          assigns.form
        )
      )

    ~H"""
    <fieldset
      class="space-y-2"
      data-operational-observable-picker
      data-operational-observable-readiness-focus-ids={
        Enum.join(@readiness_focus_observable_ids, " ")
      }
      data-operational-observable-readiness-source-empty-reason={
        focus_value(@dashboard_editor_focus, :source_empty_reason) || ""
      }
      data-operational-observable-readiness-requested-sampling={
        focus_value(@dashboard_editor_focus, :requested_sampling) || ""
      }
      data-operational-observable-readiness-requested-products={
        focus_product_value(@dashboard_editor_focus)
      }
      data-operational-observable-readiness-supported-products={
        focus_list_value(@dashboard_editor_focus, :supported_products)
      }
    >
      <legend class="hud-label">Operational Observables</legend>
      <%= if @operational_observables == [] do %>
        <p class="text-sm text-base-content/70">
          No backed operational observables are available for dashboard binding.
        </p>
      <% else %>
        <p
          :if={@readiness_capability_guidance}
          class="flex items-start gap-1.5 rounded border border-warning/40 bg-warning/10 px-2 py-1 text-xs text-warning"
          data-operational-observable-capability-warning
          data-operational-observable-capability-warning-products={
            focus_product_value(@dashboard_editor_focus)
          }
          data-operational-observable-capability-warning-supported-products={
            focus_list_value(@dashboard_editor_focus, :supported_products)
          }
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>{@readiness_capability_guidance}</span>
        </p>
        <div
          :if={@selected_operational_observables != []}
          class="flex flex-wrap gap-1"
          data-selected-operational-observables
        >
          <button
            :for={observable <- @selected_operational_observables}
            type="button"
            phx-click="pick_point"
            phx-value-point-id={observable.observable_id}
            class={[
              "badge badge-primary badge-outline gap-1 font-mono",
              operational_observable_readiness_focus?(
                observable,
                @readiness_focus_observable_ids
              ) && "ring-2 ring-warning ring-offset-1 ring-offset-base-200"
            ]}
            data-selected-operational-observable={observable.observable_id}
            data-selected-operational-observable-readiness-focus={
              if operational_observable_readiness_focus?(
                   observable,
                   @readiness_focus_observable_ids
                 ),
                 do: "true",
                 else: "false"
            }
            data-selected-operational-observable-scopes={
              WidgetFormPresentation.operational_observable_scope_values(observable)
            }
            data-selected-operational-observable-source-product={
              WidgetFormPresentation.operational_observable_source_product_value(observable)
            }
            data-selected-operational-observable-product-family={
              WidgetFormPresentation.operational_observable_product_family_value(observable)
            }
            data-selected-operational-observable-scope-supported={
              if WidgetFormPresentation.operational_observable_scope_supported?(
                   observable,
                   @dashboard_scope_context
                 ),
                 do: "true",
                 else: "false"
            }
            title={WidgetFormPresentation.operational_observable_scope_title(observable)}
            aria-label={"Remove #{observable.observable_id}"}
          >
            {observable.observable_id}
            <.icon name="hero-x-mark" class="h-3 w-3" />
          </button>
        </div>
        <p
          :if={@selected_operational_scope_warning}
          class="flex items-start gap-1.5 rounded border border-warning/40 bg-warning/10 px-2 py-1 text-xs text-warning"
          data-operational-observable-scope-warning
          data-operational-observable-scope-warning-ids={@selected_operational_scope_warning_ids}
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>{@selected_operational_scope_warning}</span>
        </p>
        <.input
          field={@form[:point_q]}
          type="search"
          placeholder="Filter operational observables"
          phx-debounce="150"
        />
        <ul class="max-h-48 space-y-1 overflow-y-auto rounded border border-base-300/60 p-1">
          <li
            :for={group <- @operational_observable_groups}
            data-operational-observable-product-group={group.id}
            data-operational-observable-source-product={group.source_product_value}
            data-operational-observable-product-family={group.product_family_value}
          >
            <div
              class="px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-normal text-base-content/50"
              data-operational-observable-product-group-label={group.id}
            >
              {group.label}
            </div>
            <ul class="space-y-1">
              <li :for={observable <- group.observables}>
                <button
                  type="button"
                  phx-click="pick_point"
                  phx-value-point-id={observable.observable_id}
                  class={
                    WidgetFormPresentation.operational_observable_button_class(
                      observable,
                      @selected_operational_observables,
                      @dashboard_scope_context
                    ) ++
                      [
                        operational_observable_readiness_focus?(
                          observable,
                          @readiness_focus_observable_ids
                        ) && "ring-1 ring-warning"
                      ]
                  }
                  disabled={
                    not WidgetFormPresentation.operational_observable_selectable?(
                      observable,
                      @selected_operational_observables,
                      @dashboard_scope_context
                    )
                  }
                  aria-pressed={
                    if WidgetFormPresentation.selected_operational_observable?(
                         observable,
                         @selected_operational_observables
                       ),
                      do: "true",
                      else: "false"
                  }
                  data-operational-observable={observable.observable_id}
                  data-operational-observable-readiness-focus={
                    if operational_observable_readiness_focus?(
                         observable,
                         @readiness_focus_observable_ids
                       ),
                       do: "true",
                       else: "false"
                  }
                  data-operational-observable-scopes={
                    WidgetFormPresentation.operational_observable_scope_values(observable)
                  }
                  data-operational-observable-source-product={
                    WidgetFormPresentation.operational_observable_source_product_value(observable)
                  }
                  data-operational-observable-product-family={
                    WidgetFormPresentation.operational_observable_product_family_value(observable)
                  }
                  data-operational-observable-scope-supported={
                    if WidgetFormPresentation.operational_observable_scope_supported?(
                         observable,
                         @dashboard_scope_context
                       ),
                       do: "true",
                       else: "false"
                  }
                  data-operational-observable-selected={
                    if WidgetFormPresentation.selected_operational_observable?(
                         observable,
                         @selected_operational_observables
                       ),
                      do: "true",
                      else: "false"
                  }
                >
                  <.icon
                    :if={
                      WidgetFormPresentation.selected_operational_observable?(
                        observable,
                        @selected_operational_observables
                      )
                    }
                    name="hero-check"
                    class="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary"
                  />
                  <span class="font-mono">{observable.observable_id}</span>
                  <span :if={observable.unit} class="ml-2 text-base-content/60">
                    {observable.unit}
                  </span>
                  <span class="ml-2 text-base-content/60">{observable.name}</span>
                  <span class="ml-auto flex flex-wrap justify-end gap-1">
                    <span
                      :for={
                        scope_label <- WidgetFormPresentation.operational_observable_scope_badges(
                          observable
                        )
                      }
                      class="badge badge-ghost badge-xs whitespace-nowrap"
                    >
                      {scope_label}
                    </span>
                  </span>
                </button>
              </li>
            </ul>
          </li>
          <li
            :if={@filtered_operational_observables == []}
            class="px-2 py-1 text-sm text-base-content/60"
          >
            No operational observables match the filter.
          </li>
        </ul>
      <% end %>
    </fieldset>
    """
  end

  defp readiness_focus_observable_ids(%{unsupported_observables: observables})
       when is_list(observables) do
    observables
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp readiness_focus_observable_ids(%{"unsupported_observables" => observables})
       when is_list(observables) do
    observables
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp readiness_focus_observable_ids(%{requested_observables: observables})
       when is_list(observables) do
    observables
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp readiness_focus_observable_ids(%{"requested_observables" => observables})
       when is_list(observables) do
    observables
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp readiness_focus_observable_ids(_focus), do: []

  defp readiness_capability_guidance(focus) do
    if focus_value(focus, :source_empty_reason) == "unsupported_source_capability" do
      requested_sampling = focus_value(focus, :requested_sampling) || "requested"
      requested_products = focus_product_value(focus)
      supported_products = focus_list_value(focus, :supported_products)

      "Selected source cannot satisfy #{requested_sampling} for #{fallback_text(requested_products, "these operational source products")}. Supported source products: #{fallback_text(supported_products, "none")}."
    end
  end

  defp focus_value(focus, key) when is_map(focus) do
    Map.get(focus, key) || Map.get(focus, Atom.to_string(key))
  end

  defp focus_value(_focus, _key), do: nil

  defp focus_list_value(focus, key) do
    focus
    |> focus_value(key)
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp focus_product_value(focus) do
    case focus_list_value(focus, :requested_source_products) do
      "" -> focus_list_value(focus, :requested_products)
      source_products -> source_products
    end
  end

  defp fallback_text("", fallback), do: fallback
  defp fallback_text(value, _fallback), do: value

  defp operational_observable_readiness_focus?(observable, focus_ids) when is_list(focus_ids) do
    observable.observable_id in focus_ids
  end

  defp section_options(sections) do
    [{"Unsectioned canvas", ""}] ++ Enum.map(sections, &{&1.title, &1.section_id})
  end
end
