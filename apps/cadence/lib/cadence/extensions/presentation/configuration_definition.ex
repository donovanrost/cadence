defmodule Cadence.Extensions.Presentation.ConfigurationDefinition do
  @moduledoc "Bounded configuration presentation contributed by a typed extension definition."

  alias Cadence.Extensions.Presentation.SectionDefinition

  @type t :: %__MODULE__{
          id: binary(),
          description: binary() | nil,
          sections: [SectionDefinition.t()]
        }

  @enforce_keys [:id, :sections]
  defstruct [:id, :description, sections: []]

  @max_sections 12
  @max_fields 24

  @spec validate(t()) :: :ok | {:error, :invalid_configuration_definition}
  def validate(%__MODULE__{} = definition) do
    sections = if is_list(definition.sections), do: definition.sections, else: []
    section_ids = Enum.map(sections, &section_id/1)
    fields = Enum.flat_map(sections, &section_fields/1)
    field_ids = Enum.map(fields, & &1.field)

    with true <- valid_text?(definition.id),
         true <- valid_optional_text?(definition.description),
         true <- is_list(definition.sections) and sections != [],
         true <- length(sections) <= @max_sections,
         true <- Enum.all?(sections, &(SectionDefinition.validate(&1) == :ok)),
         true <- length(Enum.uniq(section_ids)) == length(section_ids),
         true <- length(fields) <= @max_fields,
         true <- length(Enum.uniq(field_ids)) == length(field_ids),
         true <- valid_visibility_references?(fields, field_ids) do
      :ok
    else
      _invalid -> {:error, :invalid_configuration_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_configuration_definition}

  @spec default_params(t()) :: %{binary() => binary()}
  def default_params(%__MODULE__{} = definition) do
    definition.sections
    |> Enum.flat_map(& &1.fields)
    |> Map.new(&{Atom.to_string(&1.field), &1.default})
  end

  defp valid_visibility_references?(fields, field_ids) do
    Enum.all?(fields, fn field ->
      case field.visible_when do
        nil -> true
        %{field: dependency} -> dependency in field_ids and dependency != field.field
      end
    end)
  end

  defp section_id(%SectionDefinition{id: id}), do: id
  defp section_id(_section), do: nil
  defp section_fields(%SectionDefinition{fields: fields}) when is_list(fields), do: fields
  defp section_fields(_section), do: []

  defp valid_optional_text?(nil), do: true
  defp valid_optional_text?(value), do: valid_text?(value)
  defp valid_text?(value), do: is_binary(value) and value != ""
end
