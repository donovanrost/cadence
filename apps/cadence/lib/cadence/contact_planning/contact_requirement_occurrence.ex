defmodule Cadence.ContactPlanning.ContactRequirementOccurrence do
  @moduledoc "Durable exactly-once generation evidence for one template occurrence."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @states [:materializing, :generated, :failed]

  @type generation_state :: :materializing | :generated | :failed

  @type t :: %__MODULE__{
          contact_requirement_occurrence_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_requirement_template_id: binary(),
          contact_requirement_template_version: pos_integer(),
          occurrence_at: DateTime.t(),
          generation_state: generation_state(),
          generated_contact_requirement_id: binary() | nil,
          generated_contact_requirement_version: pos_integer() | nil,
          error_document: map(),
          materialized_by: binary(),
          materialized_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :contact_requirement_occurrence_id,
    :organization_id,
    :mission_id,
    :contact_requirement_template_id,
    :contact_requirement_template_version,
    :occurrence_at,
    :generation_state,
    :generated_contact_requirement_id,
    :generated_contact_requirement_version,
    :error_document,
    :materialized_by,
    :materialized_at,
    :inserted_at,
    :updated_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      contact_requirement_occurrence_id:
        value(
          attrs,
          :contact_requirement_occurrence_id,
          Ids.new("contact_requirement_occurrence")
        ),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_requirement_template_id: required(attrs, :contact_requirement_template_id),
      contact_requirement_template_version:
        positive(
          value(attrs, :contact_requirement_template_version),
          :contact_requirement_template_version
        ),
      occurrence_at: datetime(value(attrs, :occurrence_at), :occurrence_at),
      generation_state:
        attrs
        |> value(:generation_state, :materializing)
        |> atom(@states, :generation_state),
      generated_contact_requirement_id:
        optional_string(value(attrs, :generated_contact_requirement_id)),
      generated_contact_requirement_version:
        optional_positive(value(attrs, :generated_contact_requirement_version)),
      error_document: document(value(attrs, :error_document, %{}), :error_document),
      materialized_by: required(attrs, :materialized_by),
      materialized_at:
        datetime(value(attrs, :materialized_at, DateTime.utc_now()), :materialized_at),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
    |> validate_generated_binding()
  end

  defp validate_generated_binding(%__MODULE__{generation_state: :generated} = occurrence) do
    if occurrence.generated_contact_requirement_id &&
         occurrence.generated_contact_requirement_version do
      occurrence
    else
      raise ArgumentError, "generated occurrence requires an exact Contact Requirement version"
    end
  end

  defp validate_generated_binding(%__MODULE__{} = occurrence), do: occurrence

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: raise(ArgumentError, "generated requirement id is invalid")

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp optional_positive(nil), do: nil
  defp optional_positive(value), do: positive(value, :generated_contact_requirement_version)

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp atom(value, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
