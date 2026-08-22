defmodule Cadence.Extensions.Presentation.SectionDefinition do
  @moduledoc "A host-rendered group of typed extension configuration fields."

  alias Cadence.Extensions.Presentation.FieldDefinition

  @type t :: %__MODULE__{
          id: binary(),
          number: binary(),
          title: binary(),
          description: binary() | nil,
          fields: [FieldDefinition.t()]
        }

  @enforce_keys [:id, :number, :title, :fields]
  defstruct [:id, :number, :title, :description, fields: []]

  @max_fields 24

  @spec validate(t()) :: :ok | {:error, :invalid_section_definition}
  def validate(%__MODULE__{} = section) do
    fields = if is_list(section.fields), do: section.fields, else: []
    field_ids = Enum.map(fields, &field_id/1)

    if valid_header?(section) and valid_fields?(section.fields, fields, field_ids) do
      :ok
    else
      {:error, :invalid_section_definition}
    end
  end

  def validate(_section), do: {:error, :invalid_section_definition}

  defp field_id(%FieldDefinition{field: field}), do: field
  defp field_id(_field), do: nil

  defp valid_header?(section) do
    valid_text?(section.id) and valid_text?(section.number) and valid_text?(section.title) and
      valid_optional_text?(section.description)
  end

  defp valid_fields?(raw_fields, fields, field_ids) do
    is_list(raw_fields) and fields != [] and length(fields) <= @max_fields and
      Enum.all?(fields, &(FieldDefinition.validate(&1) == :ok)) and
      length(Enum.uniq(field_ids)) == length(field_ids)
  end

  defp valid_optional_text?(nil), do: true
  defp valid_optional_text?(value), do: valid_text?(value)
  defp valid_text?(value), do: is_binary(value) and value != ""
end
