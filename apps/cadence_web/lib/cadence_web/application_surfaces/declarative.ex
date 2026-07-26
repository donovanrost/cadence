defmodule CadenceWeb.ApplicationSurfaces.Declarative do
  @moduledoc "Bounded renderer for first-party declarative application surface documents."

  use CadenceWeb, :html

  alias Cadence.Applications.SurfaceDocument
  alias Cadence.Applications.SurfaceElements.{Activity, GeneratedForm, Table}
  alias Cadence.Extensions.Presentation.FieldDefinition

  attr :document, SurfaceDocument, required: true
  attr :application_definition, :any, required: true
  attr :surface_definition, :any, required: true
  attr :form, :any, default: nil
  attr :action_feedback, :map, default: nil
  attr :rows, :any, required: true
  attr :activity_items, :any, required: true

  def surface(assigns) do
    ~H"""
    <div id="declarative-application-surface" class="space-y-6">
      <.page_header title={@document.title} subtitle={@document.description} />

      <.action_feedback :if={@action_feedback} feedback={@action_feedback} />

      <section
        :if={@document.stats != []}
        id="application-surface-stats"
        class="grid gap-4 md:grid-cols-3"
      >
        <.card :for={stat <- @document.stats} id={"application-surface-stat-#{stat.id}"}>
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="hud-label">{stat.label}</p>
              <p class="mt-2 text-2xl font-semibold">{stat.value}</p>
            </div>
            <.status_badge status={stat.tone} />
          </div>
        </.card>
      </section>

      <.application_diagnostics
        :if={@document.diagnostics}
        definition={@document.diagnostics}
      />
      <.generated_form
        :if={@document.form}
        definition={@document.form}
        application_definition={@application_definition}
        surface_definition={@surface_definition}
        form={@form}
      />
      <.surface_table :if={@document.table} definition={@document.table} rows={@rows} />
      <.activity
        :if={@document.activity}
        definition={@document.activity}
        items={@activity_items}
      />
    </div>
    """
  end

  attr :feedback, :map, required: true

  defp action_feedback(assigns) do
    ~H"""
    <aside
      id="application-action-feedback"
      role={if(@feedback.kind == :error, do: "alert", else: "status")}
      aria-live="polite"
      data-kind={Atom.to_string(@feedback.kind)}
      data-code={@feedback.code}
      class={[
        "grid grid-cols-[0.3rem_auto_minmax(0,1fr)] items-center gap-4 border-y border-base-300/70 bg-base-200/45 px-4 py-3",
        @feedback.kind == :success && "text-success",
        @feedback.kind == :error && "text-error"
      ]}
    >
      <span
        class={[
          "h-full min-h-10 rounded-full",
          @feedback.kind == :success && "bg-success",
          @feedback.kind == :error && "bg-error"
        ]}
      >
      </span>
      <.icon
        name={if(@feedback.kind == :success, do: "hero-check-circle", else: "hero-exclamation-triangle")}
        class="size-5"
      />
      <div class="text-base-content">
        <p class="hud-label">
          {if(@feedback.kind == :success, do: "Action complete", else: "Action blocked")}
        </p>
        <p class="mt-1 text-sm text-base-content/75">{@feedback.message}</p>
      </div>
    </aside>
    """
  end

  attr :definition, GeneratedForm, required: true
  attr :application_definition, :any, required: true
  attr :surface_definition, :any, required: true
  attr :form, :any, required: true

  defp generated_form(assigns) do
    ~H"""
    <.card id={@definition.id}>
      <.section_header
        title={@definition.title}
        description={@definition.description}
      />

      <.form
        for={@form}
        id={"#{@definition.id}-fields"}
        phx-change="application_form_change"
        phx-submit="application_action"
        phx-value-action-id={@definition.action_id}
        class="mt-5"
      >
        <div class="grid gap-x-4 md:grid-cols-2">
          <div
            :for={field <- @definition.fields}
            id={"#{@definition.id}-field-#{field.field}"}
            data-field-type={field.type}
            data-reference-provider={reference_provider_id(field)}
            data-reference-version={reference_provider_version(field)}
            data-reference-mode={reference_mode(field)}
            data-reference-query={reference_query(field)}
          >
            <%= if searchable_reference?(field) do %>
              <.input
                field={@form[field.field]}
                type="text"
                label={field.label}
                placeholder={field.placeholder}
                required={field.required}
                list={reference_list_id(@definition.id, field)}
                maxlength="120"
                autocomplete="off"
                phx-debounce="250"
                class="font-mono text-sm"
              />
              <datalist id={reference_list_id(@definition.id, field)}>
                <option
                  :for={option <- field.reference_page.options}
                  value={option.value}
                  label={option.label}
                >
                  {option.description}
                </option>
              </datalist>
              <p
                id={"#{@definition.id}-reference-#{field.field}-status"}
                data-match-count={length(field.reference_page.options)}
                data-more-matches={to_string(field.reference_page.more?)}
                aria-live="polite"
                class="-mt-1 mb-2 flex items-center gap-1.5 border-l-2 border-primary/45 pl-2 font-mono text-[0.68rem] uppercase tracking-[0.09em] text-base-content/55"
              >
                <.icon name="hero-magnifying-glass" class="size-3.5 text-primary/70" />
                {reference_result_summary(field.reference_page)}
              </p>
            <% else %>
              <.input
                field={@form[field.field]}
                type={input_type(field)}
                label={field.label}
                placeholder={field.placeholder}
                required={field.required}
                options={field_options(field)}
                step={field.step}
                min={field.min}
                max={field.max}
                class={if(field.type == :textarea, do: "min-h-24", else: nil)}
              />
            <% end %>
            <p
              :if={field.help}
              class={[
                "mb-3 text-xs text-base-content/55",
                searchable_reference?(field) && "mt-1",
                !searchable_reference?(field) && "-mt-1"
              ]}
            >
              {field.help}
            </p>
          </div>
        </div>
        <.application_domain_action
          id={"#{@definition.id}-submit"}
          application_definition={@application_definition}
          surface_definition={@surface_definition}
          action_id={@definition.action_id}
          label={@definition.submit_label}
          type="submit"
          size={:md}
        />
      </.form>
    </.card>
    """
  end

  attr :definition, Table, required: true
  attr :rows, :any, required: true

  defp surface_table(assigns) do
    assigns = assign(assigns, :page, assigns.definition.page)

    ~H"""
    <.card id={@definition.id} padding={:none}>
      <div class="px-4 pt-4">
        <.section_header
          title={@definition.title}
          description={@definition.description}
        />
      </div>

      <div class="mt-5 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th :for={column <- @definition.columns}>{column.label}</th>
            </tr>
          </thead>
          <tbody id={"#{@definition.id}-rows"} phx-update="stream">
            <tr id={"#{@definition.id}-empty"} class="hidden only:table-row">
              <td colspan={length(@definition.columns)}>
                <div class="py-8 text-center">
                  <p class="font-medium">{@definition.empty_title}</p>
                  <p :if={@definition.empty_description} class="mt-1 text-sm text-base-content/60">
                    {@definition.empty_description}
                  </p>
                </div>
              </td>
            </tr>
            <tr :for={{dom_id, row} <- @rows} id={dom_id}>
              <td
                :for={column <- @definition.columns}
                class={column.mono && "font-mono text-xs"}
              >
                {Map.get(row, column.key)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <.pagination
        id={"#{@definition.id}-pagination"}
        page={@page.page}
        page_size={@page.page_size}
        total_count={@page.total_count}
        on_paginate="application_table_page"
      />
    </.card>
    """
  end

  attr :definition, Activity, required: true
  attr :items, :any, required: true

  defp activity(assigns) do
    ~H"""
    <.card id={@definition.id}>
      <.section_header title={@definition.title} description={@definition.description} />

      <div
        id={"#{@definition.id}-items"}
        class="mt-5 divide-y divide-base-300/60 border-y border-base-300/60"
        phx-update="stream"
      >
        <div id={"#{@definition.id}-empty"} class="hidden only:block py-8 text-center">
          <p class="font-medium">{@definition.empty_title}</p>
          <p :if={@definition.empty_description} class="mt-1 text-sm text-base-content/60">
            {@definition.empty_description}
          </p>
        </div>
        <article
          :for={{dom_id, item} <- @items}
          id={dom_id}
          class="group grid grid-cols-[0.35rem_minmax(0,1fr)_auto] gap-4 py-4"
        >
          <div class={[
            "rounded-full transition-transform duration-200 group-hover:scale-y-110",
            activity_rail_class(item.tone)
          ]}>
          </div>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="truncate font-medium text-base-content">{item.title}</h3>
              <.status_badge status={item.tone} />
            </div>
            <p class="mt-1 text-xs uppercase tracking-[0.12em] text-base-content/55">
              {item.detail}
            </p>
            <time :if={item.timestamp} class="mt-2 block font-mono text-[0.7rem] text-base-content/45">
              {item.timestamp}
            </time>
          </div>
          <p :if={item.value} class="self-center font-mono text-lg text-base-content">
            {item.value}
          </p>
        </article>
      </div>
    </.card>
    """
  end

  defp activity_rail_class(:blocked), do: "bg-error"
  defp activity_rail_class(:attention), do: "bg-warning"
  defp activity_rail_class(:ready), do: "bg-success"
  defp activity_rail_class(:info), do: "bg-info"

  defp input_type(%FieldDefinition{type: :reference}), do: "select"
  defp input_type(%FieldDefinition{type: type}), do: Atom.to_string(type)

  defp field_options(%FieldDefinition{type: :reference, reference_page: reference_page}),
    do: reference_page.options

  defp field_options(%FieldDefinition{} = field), do: field.options

  defp searchable_reference?(%FieldDefinition{
         type: :reference,
         reference: %{mode: :search},
         reference_page: %{options: options}
       })
       when is_list(options),
       do: true

  defp searchable_reference?(%FieldDefinition{}), do: false

  defp reference_list_id(form_id, %FieldDefinition{field: field}),
    do: "#{form_id}-reference-#{field}-options"

  defp reference_result_summary(%{options: [], query: ""}),
    do: "No active mission references"

  defp reference_result_summary(%{options: [], query: _query}),
    do: "No matching mission references"

  defp reference_result_summary(%{options: options, more?: true}),
    do: "First #{length(options)} matches · keep typing to narrow"

  defp reference_result_summary(%{options: options}),
    do: "#{length(options)} mission reference#{if(length(options) == 1, do: "", else: "s")}"

  defp reference_provider_id(%FieldDefinition{reference: %{provider_id: provider_id}}),
    do: provider_id

  defp reference_provider_id(%FieldDefinition{}), do: nil

  defp reference_provider_version(%FieldDefinition{reference: %{version: version}}),
    do: version

  defp reference_provider_version(%FieldDefinition{}), do: nil

  defp reference_mode(%FieldDefinition{reference: %{mode: mode}}), do: mode
  defp reference_mode(%FieldDefinition{}), do: nil

  defp reference_query(%FieldDefinition{reference_page: %{query: query}}), do: query
  defp reference_query(%FieldDefinition{}), do: nil
end
