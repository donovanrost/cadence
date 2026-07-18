defmodule Cadence.Persistence.Schemas.ContactRequirementOccurrenceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactRequirementOccurrence
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_requirement_occurrence_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_requirement_occurrences" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_requirement_template_id, :string)
    field(:contact_requirement_template_version, :integer)
    field(:occurrence_at, :utc_datetime_usec)
    field(:generation_state, :string)
    field(:generated_contact_requirement_id, :string)
    field(:generated_contact_requirement_version, :integer)
    field(:error_document, :map, default: %{})
    field(:materialized_by, :string)
    field(:materialized_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
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
    :materialized_at
  ]

  @required_fields [
    :contact_requirement_occurrence_id,
    :organization_id,
    :mission_id,
    :contact_requirement_template_id,
    :contact_requirement_template_version,
    :occurrence_at,
    :generation_state,
    :error_document,
    :materialized_by,
    :materialized_at
  ]

  @spec changeset(ContactRequirementOccurrence.t()) :: Ecto.Changeset.t()
  def changeset(%ContactRequirementOccurrence{} = occurrence) do
    %__MODULE__{}
    |> cast(domain_attrs(occurrence), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:contact_requirement_template_version, greater_than: 0)
    |> validate_optional_positive(:generated_contact_requirement_version)
    |> validate_inclusion(:generation_state, ~w(materializing generated failed))
    |> validate_generated_binding()
    |> unique_constraint(
      [
        :organization_id,
        :mission_id,
        :contact_requirement_template_id,
        :contact_requirement_template_version,
        :occurrence_at
      ],
      name: :contact_requirement_occurrences_identity_uniq
    )
  end

  @spec generation_changeset(struct(), map()) :: Ecto.Changeset.t()
  def generation_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :generation_state,
      :generated_contact_requirement_id,
      :generated_contact_requirement_version,
      :error_document,
      :materialized_at
    ])
    |> validate_required([:generation_state, :error_document, :materialized_at])
    |> validate_optional_positive(:generated_contact_requirement_version)
    |> validate_inclusion(:generation_state, ~w(materializing generated failed))
    |> validate_generated_binding()
  end

  @spec to_domain(struct()) :: ContactRequirementOccurrence.t()
  def to_domain(%__MODULE__{} = row) do
    ContactRequirementOccurrence.new(%{
      contact_requirement_occurrence_id: row.contact_requirement_occurrence_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_requirement_template_id: row.contact_requirement_template_id,
      contact_requirement_template_version: row.contact_requirement_template_version,
      occurrence_at: row.occurrence_at,
      generation_state: row.generation_state,
      generated_contact_requirement_id: row.generated_contact_requirement_id,
      generated_contact_requirement_version: row.generated_contact_requirement_version,
      error_document: JsonDocument.unwrap_value(row.error_document),
      materialized_by: row.materialized_by,
      materialized_at: row.materialized_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp domain_attrs(occurrence) do
    %{
      contact_requirement_occurrence_id: occurrence.contact_requirement_occurrence_id,
      organization_id: occurrence.organization_id,
      mission_id: occurrence.mission_id,
      contact_requirement_template_id: occurrence.contact_requirement_template_id,
      contact_requirement_template_version: occurrence.contact_requirement_template_version,
      occurrence_at: occurrence.occurrence_at,
      generation_state: Atom.to_string(occurrence.generation_state),
      generated_contact_requirement_id: occurrence.generated_contact_requirement_id,
      generated_contact_requirement_version: occurrence.generated_contact_requirement_version,
      error_document: JsonDocument.wrap_value(occurrence.error_document),
      materialized_by: occurrence.materialized_by,
      materialized_at: occurrence.materialized_at
    }
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_generated_binding(changeset) do
    if get_field(changeset, :generation_state) == "generated" do
      validate_required(changeset, [
        :generated_contact_requirement_id,
        :generated_contact_requirement_version
      ])
    else
      changeset
    end
  end
end
