defmodule CadenceWeb.OpsDashboardShowLive.DashboardSectionComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :document, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil

  def section_manager(assigns) do
    ~H"""
    <div class="space-y-5">
      <div id="dashboard-section-list" class="space-y-2">
        <p :if={@document.sections == []} class="text-sm text-base-content/60">
          No sections yet. Existing widgets remain in the unsectioned canvas.
        </p>
        <article
          :for={{section, index} <- Enum.with_index(@document.sections)}
          id={"dashboard-section-#{section.section_id}"}
          class="rounded border border-base-300/60 bg-base-200/35 p-3"
          data-dashboard-section={section.section_id}
        >
          <div class="flex items-start gap-2">
            <.icon name="hero-rectangle-group" class="mt-0.5 h-4 w-4 text-primary" />
            <div class="min-w-0 flex-1">
              <p class="font-medium">{section.title}</p>
              <p :if={section.description} class="mt-0.5 text-xs text-base-content/55">
                {section.description}
              </p>
              <span class="mt-1 inline-flex font-mono text-[0.65rem] text-base-content/45">
                {if section.collapsed_by_default?, do: "Collapsed by default", else: "Open by default"}
              </span>
            </div>
            <div class="flex gap-1">
              <button
                type="button"
                phx-click="move_dashboard_section"
                phx-value-section-id={section.section_id}
                phx-value-direction="up"
                disabled={index == 0}
                class="btn btn-ghost btn-xs btn-square"
                aria-label={"Move #{section.title} up"}
              ><.icon name="hero-arrow-up" class="h-3.5 w-3.5" /></button>
              <button
                type="button"
                phx-click="move_dashboard_section"
                phx-value-section-id={section.section_id}
                phx-value-direction="down"
                disabled={index == length(@document.sections) - 1}
                class="btn btn-ghost btn-xs btn-square"
                aria-label={"Move #{section.title} down"}
              ><.icon name="hero-arrow-down" class="h-3.5 w-3.5" /></button>
              <button
                type="button"
                phx-click="edit_dashboard_section"
                phx-value-section-id={section.section_id}
                class="btn btn-ghost btn-xs btn-square"
                aria-label={"Edit #{section.title}"}
              ><.icon name="hero-pencil-square" class="h-3.5 w-3.5" /></button>
              <button
                type="button"
                phx-click="remove_dashboard_section"
                phx-value-section-id={section.section_id}
                class="btn btn-ghost btn-xs btn-square text-error"
                data-confirm="Remove this section? Its widgets will move to the unsectioned canvas."
                aria-label={"Remove #{section.title}"}
              ><.icon name="hero-trash" class="h-3.5 w-3.5" /></button>
            </div>
          </div>
        </article>
      </div>

      <.form
        for={@form}
        id="dashboard-section-form"
        phx-change="validate_dashboard_section"
        phx-submit="save_dashboard_section"
        class="space-y-3 border-t border-base-300/60 pt-4"
      >
        <input type="hidden" name={@form[:section_id].name} value={@form[:section_id].value} />
        <p class="hud-label">
          {if @form[:section_id].value in [nil, ""], do: "Add section", else: "Edit section"}
        </p>
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input
          field={@form[:collapsed_by_default]}
          type="checkbox"
          label="Collapse by default for operators"
        />
        <p :if={@error} class="text-sm text-error">{@error}</p>
        <div class="flex gap-2">
          <.button id="save-dashboard-section" type="submit" size={:sm}>
            {if @form[:section_id].value in [nil, ""], do: "Add section", else: "Save section"}
          </.button>
          <button
            :if={@form[:section_id].value not in [nil, ""]}
            type="button"
            phx-click="open_dashboard_sections"
            class="btn btn-ghost btn-sm"
          >Cancel</button>
        </div>
      </.form>
    </div>
    """
  end
end
