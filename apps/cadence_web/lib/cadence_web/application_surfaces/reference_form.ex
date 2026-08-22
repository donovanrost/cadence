defmodule CadenceWeb.ApplicationSurfaces.ReferenceForm do
  @moduledoc "Pure document updates for host-rendered searchable reference fields."

  alias Cadence.Applications.SurfaceDocument
  alias Cadence.Applications.SurfaceElements.GeneratedForm
  alias Cadence.Extensions.Presentation.{FieldDefinition, ReferencePage}

  @spec search_field_name(SurfaceDocument.t(), term()) :: {:ok, binary()} | :none
  def search_field_name(
        %SurfaceDocument{form: %GeneratedForm{fields: fields}},
        ["application_action", field_name]
      )
      when is_binary(field_name) do
    if Enum.any?(fields, &search_field?(&1, field_name)) do
      {:ok, field_name}
    else
      :none
    end
  end

  def search_field_name(%SurfaceDocument{}, _target), do: :none

  @spec put_page(SurfaceDocument.t(), binary(), ReferencePage.t()) :: SurfaceDocument.t()
  def put_page(
        %SurfaceDocument{form: %GeneratedForm{} = form} = document,
        field_name,
        %ReferencePage{} = page
      )
      when is_binary(field_name) do
    fields =
      Enum.map(form.fields, fn
        %FieldDefinition{} = field ->
          if search_field?(field, field_name) do
            %FieldDefinition{field | reference_page: page}
          else
            field
          end
      end)

    %SurfaceDocument{document | form: %GeneratedForm{form | fields: fields}}
  end

  defp search_field?(
         %FieldDefinition{field: field, type: :reference, reference: %{mode: :search}},
         field_name
       ),
       do: Atom.to_string(field) == field_name

  defp search_field?(%FieldDefinition{}, _field_name), do: false
end
