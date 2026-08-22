defmodule Cadence.Applications.SurfaceElements.GeneratedForm do
  @moduledoc "Host-rendered form bound to one declared typed application action."

  alias Cadence.Extensions.Presentation.FieldDefinition

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary() | nil,
          action_id: binary(),
          submit_label: binary(),
          success_message: binary(),
          fields: [FieldDefinition.t()]
        }

  @enforce_keys [:id, :title, :action_id, :submit_label, :success_message, :fields]
  defstruct [:id, :title, :description, :action_id, :submit_label, :success_message, fields: []]

  @max_fields 24
  @field_types [:text, :textarea, :number, :url, :select, :reference]

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_form}
  def validate(%__MODULE__{} = form) do
    with true <- valid_text?(form.id),
         true <- valid_text?(form.title),
         true <- optional_text?(form.description),
         true <- valid_text?(form.action_id),
         true <- valid_text?(form.submit_label),
         true <- valid_text?(form.success_message),
         true <- is_list(form.fields),
         true <- form.fields != [],
         true <- length(form.fields) <= @max_fields,
         true <- Enum.all?(form.fields, &valid_field?/1),
         true <- unique_fields?(form.fields) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_form}
    end
  end

  def validate(_form), do: {:error, :invalid_application_surface_form}

  defp valid_field?(%FieldDefinition{} = field) do
    valid_field_identity?(field) and valid_field_presentation?(field) and
      valid_field_constraints?(field)
  end

  defp valid_field?(_field), do: false

  defp valid_field_identity?(field) do
    is_atom(field.field) and valid_text?(field.label) and field.type in @field_types
  end

  defp valid_field_presentation?(field) do
    is_boolean(field.required) and optional_text?(field.placeholder) and
      optional_text?(field.help) and is_binary(field.default)
  end

  defp valid_field_constraints?(field) do
    optional_text?(field.step) and valid_bound?(field.min) and valid_bound?(field.max) and
      valid_bounds?(field) and valid_options?(field.options) and
      valid_visibility?(field.visible_when)
  end

  defp valid_options?(options) when is_list(options), do: Enum.all?(options, &valid_option?/1)
  defp valid_options?(_options), do: false

  defp valid_option?({label, value}), do: is_binary(label) and is_binary(value)

  defp valid_option?({label, value, options}),
    do: is_binary(label) and is_binary(value) and is_list(options)

  defp valid_option?(_option), do: false

  defp valid_bound?(nil), do: true
  defp valid_bound?(value), do: is_number(value)

  defp valid_bounds?(%FieldDefinition{min: min, max: max})
       when is_number(min) and is_number(max),
       do: min <= max

  defp valid_bounds?(%FieldDefinition{}), do: true

  defp valid_visibility?(nil), do: true

  defp valid_visibility?(%{field: field} = visibility),
    do: is_atom(field) and Map.has_key?(visibility, :equals)

  defp valid_visibility?(_visibility), do: false

  defp unique_fields?(fields) do
    field_ids = Enum.map(fields, & &1.field)
    length(Enum.uniq(field_ids)) == length(field_ids)
  end

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
