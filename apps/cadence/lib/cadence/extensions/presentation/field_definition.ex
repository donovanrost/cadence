defmodule Cadence.Extensions.Presentation.FieldDefinition do
  @moduledoc """
  Bounded host-rendered configuration field shared by typed extension points.

  Field identifiers are compiled atoms supplied by first-party definitions.
  Options and visibility are data; definitions cannot contribute HTML, CSS,
  JavaScript, queries, or validation callbacks.
  """

  alias Cadence.Extensions.Presentation.{ReferenceDefinition, ReferencePage}

  @type input_type :: :text | :textarea | :number | :url | :select | :reference
  @type visibility :: %{field: atom(), equals: term()} | nil
  @type option :: {binary(), binary()} | {binary(), binary(), keyword()}

  @type t :: %__MODULE__{
          field: atom(),
          label: binary(),
          type: input_type(),
          required: boolean(),
          placeholder: binary() | nil,
          help: binary() | nil,
          step: binary() | nil,
          min: number() | nil,
          max: number() | nil,
          default: binary(),
          options: [option()],
          reference: ReferenceDefinition.t() | nil,
          reference_page: ReferencePage.t() | nil,
          visible_when: visibility()
        }

  @enforce_keys [:field, :label, :type]
  defstruct [
    :field,
    :label,
    :type,
    :placeholder,
    :help,
    :step,
    :min,
    :max,
    :reference,
    :reference_page,
    :visible_when,
    required: false,
    default: "",
    options: []
  ]

  @input_types [:text, :textarea, :number, :url, :select, :reference]
  @max_options 128

  @spec validate(t()) :: :ok | {:error, :invalid_field_definition}
  def validate(%__MODULE__{} = field) do
    with true <- is_atom(field.field) and not is_nil(field.field),
         true <- valid_text?(field.label),
         true <- field.type in @input_types,
         true <- is_boolean(field.required),
         true <- valid_optional_text?(field.placeholder),
         true <- valid_optional_text?(field.help),
         true <- valid_optional_text?(field.step),
         true <- valid_optional_number?(field.min),
         true <- valid_optional_number?(field.max),
         true <- valid_numeric_bounds?(field.min, field.max),
         true <- is_binary(field.default),
         true <- valid_options?(field.options),
         true <- valid_visibility?(field.visible_when),
         true <- valid_reference_contract?(field) do
      :ok
    else
      _invalid -> {:error, :invalid_field_definition}
    end
  end

  def validate(_field), do: {:error, :invalid_field_definition}

  defp valid_options?(options) when is_list(options) do
    length(options) <= @max_options and Enum.all?(options, &valid_option?/1)
  end

  defp valid_options?(_options), do: false

  defp valid_option?({label, value}), do: valid_text?(label) and valid_text?(value)

  defp valid_option?({label, value, opts}) when is_list(opts) do
    valid_text?(label) and valid_text?(value) and
      Keyword.keys(opts) == [:disabled] and is_boolean(opts[:disabled])
  end

  defp valid_option?(_option), do: false

  defp valid_visibility?(nil), do: true

  defp valid_visibility?(%{field: field, equals: _value}),
    do: is_atom(field) and not is_nil(field)

  defp valid_visibility?(_visibility), do: false

  defp valid_reference_contract?(%__MODULE__{type: :select} = field),
    do: field.options != [] and is_nil(field.reference) and is_nil(field.reference_page)

  defp valid_reference_contract?(%__MODULE__{type: :reference} = field) do
    field.options == [] and is_nil(field.reference_page) and
      ReferenceDefinition.validate(field.reference) == :ok
  end

  defp valid_reference_contract?(%__MODULE__{} = field),
    do: field.options == [] and is_nil(field.reference) and is_nil(field.reference_page)

  defp valid_numeric_bounds?(nil, _max), do: true
  defp valid_numeric_bounds?(_min, nil), do: true
  defp valid_numeric_bounds?(min, max), do: min <= max

  defp valid_optional_number?(nil), do: true
  defp valid_optional_number?(value), do: is_number(value)

  defp valid_optional_text?(nil), do: true
  defp valid_optional_text?(value), do: valid_text?(value)

  defp valid_text?(value), do: is_binary(value) and value != ""
end
