defmodule Cadence.Persistence.Schemas.MissionEventRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.MissionEvents.Entry
  alias Cadence.Persistence.JsonDocument

  @primary_key {:mission_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_events" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:category, :string)
    field(:kind, :string)
    field(:severity, :string)
    field(:status, :string)
    field(:title, :string)
    field(:summary, :string)
    field(:source_record_kind, :string)
    field(:source_record_id, :string)
    field(:subject_kind, :string)
    field(:subject_id, :string)
    field(:correlation_key, :string)
    field(:spacecraft_id, :string)
    field(:source_endpoint_ref, :string)
    field(:scheduled_contact_id, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:capability_instance_id, :string)
    field(:activation_id, :string)
    field(:actor_document, :map, default: %{})
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :mission_event_id,
    :mission_id,
    :occurred_at,
    :category,
    :kind,
    :title,
    :source_record_kind,
    :source_record_id,
    :actor_document,
    :metadata_document
  ]

  @optional_fields [
    :severity,
    :status,
    :summary,
    :subject_kind,
    :subject_id,
    :correlation_key,
    :spacecraft_id,
    :source_endpoint_ref,
    :scheduled_contact_id,
    :realized_contact_id,
    :path_id,
    :capability_instance_id,
    :activation_id
  ]

  @spec changeset(Entry.t()) :: Ecto.Changeset.t()
  def changeset(%Entry{} = entry) do
    %__MODULE__{}
    |> cast(domain_attrs(entry), @required_fields ++ @optional_fields)
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Entry.t()
  def to_domain(%__MODULE__{} = row) do
    Entry.new(%{
      mission_event_id: row.mission_event_id,
      mission_id: row.mission_id,
      occurred_at: row.occurred_at,
      category: row.category,
      kind: row.kind,
      severity: row.severity,
      status: row.status,
      title: row.title,
      summary: row.summary,
      source_record_kind: row.source_record_kind,
      source_record_id: row.source_record_id,
      subject_kind: row.subject_kind,
      subject_id: row.subject_id,
      correlation_key: row.correlation_key,
      spacecraft_id: row.spacecraft_id,
      source_endpoint_ref: row.source_endpoint_ref,
      scheduled_contact_id: row.scheduled_contact_id,
      realized_contact_id: row.realized_contact_id,
      path_id: row.path_id,
      capability_instance_id: row.capability_instance_id,
      activation_id: row.activation_id,
      actor: JsonDocument.unwrap_value(row.actor_document),
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  @spec upsert_fields() :: [atom()]
  def upsert_fields do
    [
      :occurred_at,
      :category,
      :kind,
      :severity,
      :status,
      :title,
      :summary,
      :source_record_kind,
      :source_record_id,
      :subject_kind,
      :subject_id,
      :correlation_key,
      :spacecraft_id,
      :source_endpoint_ref,
      :scheduled_contact_id,
      :realized_contact_id,
      :path_id,
      :capability_instance_id,
      :activation_id,
      :actor_document,
      :metadata_document
    ]
  end

  defp domain_attrs(%Entry{} = entry) do
    %{
      mission_event_id: entry.mission_event_id,
      mission_id: entry.mission_id,
      occurred_at: entry.occurred_at,
      category: Atom.to_string(entry.category),
      kind: Atom.to_string(entry.kind),
      severity: maybe_atom_to_string(entry.severity),
      status: entry.status,
      title: entry.title,
      summary: entry.summary,
      source_record_kind: Atom.to_string(entry.source_record_kind),
      source_record_id: entry.source_record_id,
      subject_kind: maybe_atom_to_string(entry.subject_kind),
      subject_id: entry.subject_id,
      correlation_key: entry.correlation_key,
      spacecraft_id: entry.spacecraft_id,
      source_endpoint_ref: entry.source_endpoint_ref,
      scheduled_contact_id: entry.scheduled_contact_id,
      realized_contact_id: entry.realized_contact_id,
      path_id: entry.path_id,
      capability_instance_id: entry.capability_instance_id,
      activation_id: entry.activation_id,
      actor_document: JsonDocument.wrap_value(entry.actor),
      metadata_document: JsonDocument.wrap_value(entry.metadata)
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
end
