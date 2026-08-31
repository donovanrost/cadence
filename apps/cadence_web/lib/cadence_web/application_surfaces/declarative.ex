defmodule CadenceWeb.ApplicationSurfaces.Declarative do
  @moduledoc "Builds bounded, JSON-safe presentation DTOs for declarative application surfaces."

  alias Cadence.Applications.{
    ActionConfirmation,
    ActionDefinition,
    ApplicationDefinition,
    JSONBoundary,
    SurfaceDefinition,
    SurfaceDocument
  }

  alias Cadence.Applications.SurfaceElements.{
    Activity,
    Diagnostics,
    GeneratedForm,
    PacketBindings,
    Table
  }

  alias Cadence.Extensions.Presentation.{
    FieldDefinition,
    ReferenceDefinition,
    ReferenceOption,
    ReferencePage
  }

  alias Phoenix.HTML.Form

  @spec presentation(
          SurfaceDocument.t(),
          ApplicationDefinition.t(),
          SurfaceDefinition.t(),
          Form.t() | nil,
          map() | nil
        ) :: map()
  def presentation(
        %SurfaceDocument{} = document,
        %ApplicationDefinition{} = application,
        %SurfaceDefinition{} = surface,
        form,
        action_feedback
      ) do
    dto = %{
      id: "declarative-application-surface",
      page: %{
        title: document.title,
        subtitle: document.description
      },
      action_feedback: action_feedback_dto(action_feedback),
      stats: Enum.map(document.stats, &stat_dto/1),
      diagnostics: diagnostics_dto(document.diagnostics),
      form: generated_form_dto(document.form, application, surface, form),
      packet_bindings: packet_bindings_dto(document.packet_bindings, application, surface, form),
      table: table_dto(document.table),
      activity: activity_dto(document.activity)
    }

    case JSONBoundary.validate(dto) do
      :ok -> dto
      {:error, _reason} -> blocked_presentation()
    end
  end

  @spec table_row_dtos(SurfaceDocument.t()) :: [map()]
  def table_row_dtos(%SurfaceDocument{table: nil}), do: []

  def table_row_dtos(%SurfaceDocument{table: %Table{columns: columns, page: page}}) do
    Enum.map(page.items, fn row ->
      %{
        id: row.id,
        __dom_id: table_row_dom_id(row),
        values:
          Map.new(columns, fn column ->
            {Atom.to_string(column.key), Map.fetch!(row, column.key)}
          end)
      }
    end)
  end

  @spec activity_item_dtos(SurfaceDocument.t()) :: [map()]
  def activity_item_dtos(%SurfaceDocument{activity: nil}), do: []

  def activity_item_dtos(%SurfaceDocument{activity: %Activity{items: items}}) do
    Enum.map(items, fn item ->
      %{
        id: item.id,
        __dom_id: activity_item_dom_id(item),
        title: item.title,
        detail: item.detail,
        value: item.value,
        timestamp: item.timestamp,
        tone: Atom.to_string(item.tone),
        tone_label: status_tone_label(item.tone)
      }
    end)
  end

  @spec packet_group_dtos(SurfaceDocument.t()) :: [map()]
  def packet_group_dtos(%SurfaceDocument{packet_bindings: nil}), do: []

  def packet_group_dtos(%SurfaceDocument{packet_bindings: %PacketBindings{packet_groups: groups}}) do
    Enum.map(groups, fn group ->
      %{
        id: group.id,
        __dom_id: packet_group_dom_id(group),
        packet_id: group.packet_id,
        packet_name: group.packet_name,
        apid: group.apid,
        selector_summary: group.selector_summary,
        model_label: group.model_label,
        selected: group.selected,
        expanded: group.expanded,
        selectable: group.selectable,
        state: Atom.to_string(group.state),
        reason: group.reason,
        consumers: group.consumers,
        resources: Enum.map(group.resources, &packet_resource_dto/1)
      }
    end)
  end

  @spec table_row_dom_id(map()) :: binary()
  def table_row_dom_id(%{__dom_id: dom_id}) when is_binary(dom_id), do: dom_id
  def table_row_dom_id(%{id: id}) when is_binary(id), do: "application-surface-row-#{id}"

  @spec activity_item_dom_id(map()) :: binary()
  def activity_item_dom_id(%{__dom_id: dom_id}) when is_binary(dom_id), do: dom_id

  def activity_item_dom_id(%{id: id}) when is_binary(id),
    do: "application-surface-activity-#{id}"

  @spec packet_group_dom_id(map()) :: binary()
  def packet_group_dom_id(%{__dom_id: dom_id}) when is_binary(dom_id), do: dom_id
  def packet_group_dom_id(%{id: id}) when is_binary(id), do: "packet-binding-group-#{id}"

  defp stat_dto(stat) do
    %{
      id: "application-surface-stat-#{stat.id}",
      stat_id: stat.id,
      label: stat.label,
      value: stat.value,
      tone: Atom.to_string(stat.tone),
      tone_label: status_tone_label(stat.tone)
    }
  end

  defp diagnostics_dto(nil), do: nil
  defp diagnostics_dto(%Diagnostics{items: []}), do: nil

  defp diagnostics_dto(%Diagnostics{} = diagnostics) do
    severity = overall_severity(diagnostics.items)

    %{
      id: diagnostics.id,
      items_id: "#{diagnostics.id}-items",
      role: if(severity == :error, do: "alert", else: "status"),
      severity: Atom.to_string(severity),
      count: length(diagnostics.items),
      total_count: diagnostics.total_count,
      count_label: diagnostic_count_label(diagnostics),
      label: diagnostic_severity_label(severity),
      title: diagnostics.title,
      description: diagnostics.description,
      items: Enum.map(diagnostics.items, &diagnostic_item_dto(diagnostics.id, &1))
    }
  end

  defp diagnostic_item_dto(diagnostics_id, item) do
    %{
      id: "#{diagnostics_id}-item-#{item.id}",
      diagnostic_id: item.id,
      code: item.code,
      severity: Atom.to_string(item.severity),
      title: item.title,
      detail: item.detail,
      value: item.value
    }
  end

  defp overall_severity(items) do
    cond do
      Enum.any?(items, &(&1.severity == :error)) -> :error
      Enum.any?(items, &(&1.severity == :warning)) -> :warning
      true -> :info
    end
  end

  defp diagnostic_count_label(%Diagnostics{items: items, total_count: total_count}) do
    visible_count = length(items)

    if visible_count < total_count do
      "#{visible_count} shown · #{total_count} total"
    else
      "#{total_count} #{if(total_count == 1, do: "finding", else: "findings")}"
    end
  end

  defp diagnostic_severity_label(:error), do: "Blocked"
  defp diagnostic_severity_label(:warning), do: "Advisory"
  defp diagnostic_severity_label(:info), do: "Notice"

  defp action_feedback_dto(nil), do: nil

  defp action_feedback_dto(feedback) do
    %{
      id: "application-action-feedback",
      role: if(feedback.kind == :error, do: "alert", else: "status"),
      kind: Atom.to_string(feedback.kind),
      code: feedback.code,
      label: if(feedback.kind == :success, do: "Action complete", else: "Action blocked"),
      message: feedback.message
    }
  end

  defp blocked_presentation do
    %{
      id: "declarative-application-surface",
      page: %{
        title: "Application unavailable",
        subtitle: "The application returned data outside the host boundary."
      },
      action_feedback: %{
        id: "application-action-feedback",
        role: "alert",
        kind: "error",
        code: "surface_bounds_exceeded",
        label: "Action blocked",
        message: "The application surface could not be safely rendered."
      },
      stats: [],
      diagnostics: nil,
      form: nil,
      packet_bindings: nil,
      table: nil,
      activity: nil
    }
  end

  defp generated_form_dto(nil, _application, _surface, _form), do: nil

  defp generated_form_dto(
         %GeneratedForm{} = definition,
         %ApplicationDefinition{} = application,
         %SurfaceDefinition{} = surface,
         %Form{} = form
       ) do
    %{
      id: definition.id,
      form_id: "#{definition.id}-fields",
      title: definition.title,
      description: definition.description,
      fields: Enum.map(definition.fields, &field_dto(definition.id, form, &1)),
      action:
        domain_action_dto(
          application,
          surface,
          definition.action_id,
          "#{definition.id}-submit",
          definition.submit_label,
          false
        )
    }
  end

  defp field_dto(form_id, %Form{} = form, %FieldDefinition{} = field) do
    field_name = Atom.to_string(field.field)

    %{
      id: "#{form_id}-field-#{field_name}",
      field: field_name,
      input_id: Form.input_id(form, field.field),
      name: Form.input_name(form, field.field),
      type: field_input_type(field),
      contract_type: Atom.to_string(field.type),
      label: field.label,
      placeholder: field.placeholder,
      help: field.help,
      required: field.required,
      step: field.step,
      min: field.min,
      max: field.max,
      value: string_form_value(form, field.field),
      errors: form_errors(form, field.field),
      options: field_options_dto(field),
      reference: reference_dto(form_id, field),
      visible_when: visibility_dto(field.visible_when)
    }
  end

  defp field_input_type(%FieldDefinition{type: :reference, reference: %{mode: :search}}),
    do: "text"

  defp field_input_type(%FieldDefinition{type: :reference}), do: "select"
  defp field_input_type(%FieldDefinition{type: type}), do: Atom.to_string(type)

  defp field_options_dto(%FieldDefinition{type: :reference, reference_page: page}),
    do: reference_options_dto(page)

  defp field_options_dto(%FieldDefinition{options: options}),
    do: Enum.map(options, &option_dto/1)

  defp option_dto({label, value}) do
    %{label: label, value: value, disabled: false, description: nil}
  end

  defp option_dto({label, value, opts}) do
    %{
      label: label,
      value: value,
      disabled: Keyword.get(opts, :disabled, false),
      description: Keyword.get(opts, :title)
    }
  end

  defp option_dto(%ReferenceOption{} = option) do
    %{
      label: option.label,
      value: option.value,
      disabled: false,
      description: option.description
    }
  end

  defp reference_dto(_form_id, %FieldDefinition{reference: nil}), do: nil

  defp reference_dto(
         form_id,
         %FieldDefinition{
           field: field,
           reference: %ReferenceDefinition{} = reference,
           reference_page: page
         }
       ) do
    page = page || %ReferencePage{query: "", options: [], more?: false}

    %{
      provider_id: reference.provider_id,
      version: reference.version,
      mode: Atom.to_string(reference.mode),
      query: page.query,
      result_limit: reference.result_limit,
      options_id: "#{form_id}-reference-#{field}-options",
      status_id: "#{form_id}-reference-#{field}-status",
      match_count: length(page.options),
      more_matches: page.more?,
      debounce_ms: 250,
      max_length: 120,
      result_summary: reference_result_summary(page),
      options: reference_options_dto(page)
    }
  end

  defp reference_options_dto(%ReferencePage{options: options}),
    do: Enum.map(options, &option_dto/1)

  defp reference_options_dto(nil), do: []

  defp reference_result_summary(%ReferencePage{options: [], query: ""}),
    do: "No active mission references"

  defp reference_result_summary(%ReferencePage{options: [], query: _query}),
    do: "No matching mission references"

  defp reference_result_summary(%ReferencePage{options: options, more?: true}),
    do: "First #{length(options)} matches · keep typing to narrow"

  defp reference_result_summary(%ReferencePage{options: options}) do
    "#{length(options)} mission reference#{if(length(options) == 1, do: "", else: "s")}"
  end

  defp visibility_dto(nil), do: nil

  defp visibility_dto(%{field: field, equals: expected}) do
    %{field: Atom.to_string(field), equals: presentation_string(expected)}
  end

  defp packet_bindings_dto(nil, _application, _surface, _form), do: nil

  defp packet_bindings_dto(
         %PacketBindings{} = definition,
         %ApplicationDefinition{} = application,
         %SurfaceDefinition{} = surface,
         %Form{} = form
       ) do
    %{
      id: definition.id,
      activation_state: Atom.to_string(definition.activation_state),
      tone: packet_binding_tone(definition.activation_state),
      tone_label: definition.activation_state |> packet_binding_tone() |> status_tone_label(),
      state_label: definition.activation_state |> Atom.to_string() |> String.replace("_", " "),
      title: definition.title,
      description: definition.description,
      configured_version_label: version_label(definition.configured_version),
      applied_version_label: version_label(definition.applied_version),
      save_enabled: definition.save_enabled,
      application_display_name: application.display_name,
      form: packet_form_dto(form, definition),
      action:
        domain_action_dto(
          application,
          surface,
          definition.action_id,
          "packet-bindings-submit",
          definition.submit_label,
          not definition.save_enabled
        ),
      instructions: %{
        shared_input:
          "Shared input policy: another application reading this APID does not block selection.",
        save_status:
          "Saving changes desired routing only. Mission activation remains separately governed."
      },
      empty: %{
        id: "packet-bindings-empty",
        title: definition.empty_title,
        description: definition.empty_description
      }
    }
  end

  defp packet_form_dto(%Form{} = form, %PacketBindings{} = definition) do
    %{
      id: "packet-bindings-form",
      hidden_fields:
        Enum.map(
          [:input_id, :input_version, :catalog_revision_id, :expected_configuration_version],
          &basic_form_field_dto(form, &1, "hidden")
        ),
      source_endpoint:
        basic_form_field_dto(form, :source_endpoint_ref, "select")
        |> Map.merge(%{
          label: "Source endpoint",
          disabled: not definition.save_enabled,
          options:
            Enum.map(definition.source_endpoints, fn endpoint ->
              %{label: endpoint.label, value: endpoint.value, disabled: false}
            end)
        }),
      selected_packet_ids: string_list_form_value(form, :selected_packet_ids)
    }
  end

  defp basic_form_field_dto(%Form{} = form, field, type) do
    %{
      id: Form.input_id(form, field),
      field: Atom.to_string(field),
      name: Form.input_name(form, field),
      type: type,
      value: string_form_value(form, field),
      errors: form_errors(form, field)
    }
  end

  defp packet_resource_dto(resource) do
    %{
      id: "packet-binding-resource-#{resource.id}",
      resource_id: resource.resource_id,
      path: resource.path,
      resource_kind: Atom.to_string(resource.resource_kind),
      data_type: atom_string(resource.data_type),
      size_bits: resource.size_bits,
      compatibility: Atom.to_string(resource.compatibility),
      reason: resource.reason,
      selected: resource.selected,
      role: Atom.to_string(resource.role),
      consumers: resource.consumers,
      type_label: resource_type_label(resource),
      size_label: resource_size_label(resource.size_bits),
      consumer_label: consumer_label(resource.consumers),
      selection_label: resource_selection_label(resource)
    }
  end

  defp resource_type_label(%{resource_kind: :binary_region}), do: "binary"
  defp resource_type_label(%{data_type: nil}), do: "packet"
  defp resource_type_label(%{data_type: data_type}), do: Atom.to_string(data_type)

  defp resource_size_label(nil), do: "—"

  defp resource_size_label(size_bits) when rem(size_bits, 8) == 0,
    do: "#{div(size_bits, 8)} B"

  defp resource_size_label(size_bits), do: "#{size_bits} bit"

  defp consumer_label([]), do: "Unbound"
  defp consumer_label(consumers), do: Enum.join(consumers, ", ")

  defp resource_selection_label(%{compatibility: :incompatible}), do: "Not accepted"
  defp resource_selection_label(%{selected: true}), do: "Selected"
  defp resource_selection_label(_resource), do: "Available"

  defp packet_binding_tone(:active), do: "ready"
  defp packet_binding_tone(:outdated), do: "attention"
  defp packet_binding_tone(:configured), do: "attention"
  defp packet_binding_tone(:unavailable), do: "blocked"
  defp packet_binding_tone(:disabled), do: "info"
  defp packet_binding_tone(:unconfigured), do: "info"

  defp status_tone_label(:ready), do: "Ready"
  defp status_tone_label(:attention), do: "Needs Work"
  defp status_tone_label(:blocked), do: "Missing"
  defp status_tone_label(:info), do: "Setup"
  defp status_tone_label("ready"), do: "Ready"
  defp status_tone_label("attention"), do: "Needs Work"
  defp status_tone_label("blocked"), do: "Missing"
  defp status_tone_label("info"), do: "Setup"

  defp version_label(nil), do: "—"
  defp version_label(version), do: "v#{version}"

  defp table_dto(nil), do: nil

  defp table_dto(%Table{} = table) do
    %{
      id: table.id,
      rows_id: "#{table.id}-rows",
      title: table.title,
      description: table.description,
      columns:
        Enum.map(table.columns, fn column ->
          %{key: Atom.to_string(column.key), label: column.label, mono: column.mono}
        end),
      empty: %{
        id: "#{table.id}-empty",
        title: table.empty_title,
        description: table.empty_description
      },
      pagination: pagination_dto(table)
    }
  end

  defp pagination_dto(%Table{page: page, id: table_id}) do
    last_page = max(ceil(page.total_count / page.page_size), 1)

    %{
      id: "#{table_id}-pagination",
      visible: page.total_count > page.page_size,
      page: page.page,
      page_size: page.page_size,
      total_count: page.total_count,
      range_label: pagination_range_label(page),
      previous_label: "Prev",
      next_label: "Next",
      previous_page: max(page.page - 1, 1),
      next_page: min(page.page + 1, last_page),
      previous_disabled: page.page <= 1,
      next_disabled: page.page >= last_page
    }
  end

  defp pagination_range_label(page) do
    first = (page.page - 1) * page.page_size + 1
    last = min(page.page * page.page_size, page.total_count)
    "#{first}–#{last} of #{page.total_count}"
  end

  defp activity_dto(nil), do: nil

  defp activity_dto(%Activity{} = activity) do
    %{
      id: activity.id,
      items_id: "#{activity.id}-items",
      title: activity.title,
      description: activity.description,
      empty: %{
        id: "#{activity.id}-empty",
        title: activity.empty_title,
        description: activity.empty_description
      }
    }
  end

  defp domain_action_dto(
         %ApplicationDefinition{} = application,
         %SurfaceDefinition{} = surface,
         action_id,
         id,
         label,
         disabled
       ) do
    with true <- action_id in surface.actions,
         {:ok, %ActionDefinition{} = action} <-
           ApplicationDefinition.fetch_action(application, action_id),
         true <- action.scope == surface.scope,
         :ok <- ActionDefinition.validate(action) do
      %{
        id: id,
        action_id: action.action_id,
        label: label,
        version: action.version,
        intent: Atom.to_string(action.intent),
        scope: Atom.to_string(action.scope),
        effect: Atom.to_string(action.effect),
        execution: Atom.to_string(action.execution),
        confirmation: confirmation_dto(action.confirmation),
        disabled: disabled
      }
    else
      reason -> raise ArgumentError, "invalid declarative domain action: #{inspect(reason)}"
    end
  end

  defp confirmation_dto(nil), do: nil

  defp confirmation_dto(%ActionConfirmation{} = confirmation) do
    %{
      title: confirmation.title,
      message: confirmation.message,
      confirm_label: confirmation.confirm_label,
      tone: Atom.to_string(confirmation.tone),
      prompt: ActionConfirmation.prompt(confirmation)
    }
  end

  defp string_form_value(%Form{} = form, field) do
    form.params
    |> Map.get(Atom.to_string(field), Form.input_value(form, field))
    |> presentation_string()
  end

  defp string_list_form_value(%Form{} = form, field) do
    case Map.get(form.params, Atom.to_string(field), Form.input_value(form, field)) do
      values when is_list(values) -> Enum.map(values, &presentation_string/1)
      nil -> []
      value -> [presentation_string(value)]
    end
  end

  defp form_errors(%Form{} = form, field) do
    form.errors
    |> Keyword.get_values(field)
    |> Enum.map(&format_form_error/1)
  end

  defp format_form_error({message, opts}) when is_binary(message) and is_list(opts) do
    Enum.reduce(opts, message, fn {key, value}, formatted ->
      String.replace(formatted, "%{#{key}}", to_string(value))
    end)
  end

  defp format_form_error(message) when is_binary(message), do: message
  defp format_form_error(_invalid), do: "Invalid value"

  defp presentation_string(nil), do: ""
  defp presentation_string(value) when is_binary(value), do: value
  defp presentation_string(value) when is_atom(value), do: Atom.to_string(value)
  defp presentation_string(value) when is_number(value), do: to_string(value)
  defp presentation_string(_unsupported), do: ""

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
end
