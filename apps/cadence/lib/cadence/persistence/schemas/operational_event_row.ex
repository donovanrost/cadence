defmodule Cadence.Persistence.Schemas.OperationalEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "operational_events" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:recorded_at, :utc_datetime_usec)
    field(:effective_at, :utc_datetime_usec)
    field(:category, :string)
    field(:kind, :string)
    field(:severity, :string)
    field(:subject_kind, :string)
    field(:subject_id, :string)
    field(:correlation_id, :string)
    field(:causation_event_id, :string)
    field(:source_record_kind, :string)
    field(:source_record_id, :string)
    field(:job_id, :string)
    field(:replay_run_id, :string)
    field(:import_run_id, :string)
    field(:actor_document, :map, default: %{})
    field(:scope_document, :map, default: %{})
    field(:causality_document, :map, default: %{})
    field(:payload_document, :map, default: %{})
    field(:previous_document, :map, default: %{})
    field(:current_document, :map, default: %{})
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :event_id,
    :mission_id,
    :occurred_at,
    :recorded_at,
    :category,
    :kind,
    :actor_document,
    :scope_document,
    :causality_document,
    :payload_document,
    :previous_document,
    :current_document,
    :metadata_document
  ]

  @optional_fields [
    :organization_id,
    :effective_at,
    :severity,
    :subject_kind,
    :subject_id,
    :correlation_id,
    :causation_event_id,
    :source_record_kind,
    :source_record_id,
    :job_id,
    :replay_run_id,
    :import_run_id
  ]

  @spec changeset(Event.t()) :: Ecto.Changeset.t()
  def changeset(%Event{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @required_fields ++ @optional_fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Event.t()
  def to_domain(%__MODULE__{} = row) do
    Event.new(%{
      event_id: row.event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      occurred_at: row.occurred_at,
      recorded_at: row.recorded_at,
      effective_at: row.effective_at,
      category: row.category,
      kind: row.kind,
      severity: row.severity,
      actor: JsonDocument.unwrap_value(row.actor_document),
      subject: subject_document(row),
      scope: JsonDocument.unwrap_value(row.scope_document),
      causality: causality_document(row),
      payload: JsonDocument.unwrap_value(row.payload_document),
      previous: JsonDocument.unwrap_value(row.previous_document),
      current: JsonDocument.unwrap_value(row.current_document),
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  @spec upsert_fields() :: [atom()]
  def upsert_fields do
    (@required_fields ++ @optional_fields) -- [:event_id]
  end

  defp domain_attrs(%Event{} = event) do
    %{
      event_id: event.event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      occurred_at: event.occurred_at,
      recorded_at: event.recorded_at,
      effective_at: event.effective_at,
      category: Atom.to_string(event.category),
      kind: Atom.to_string(event.kind),
      severity: maybe_atom_to_string(event.severity),
      subject_kind: subject_kind(event.subject),
      subject_id: subject_id(event.subject),
      correlation_id: Map.get(event.causality, :correlation_id),
      causation_event_id: Map.get(event.causality, :causation_event_id),
      source_record_kind:
        event.causality |> Map.get(:source_record_kind) |> maybe_atom_to_string(),
      source_record_id: Map.get(event.causality, :source_record_id),
      job_id: Map.get(event.causality, :job_id),
      replay_run_id: Map.get(event.causality, :replay_run_id),
      import_run_id: Map.get(event.causality, :import_run_id),
      actor_document: JsonDocument.wrap_value(event.actor),
      scope_document: JsonDocument.wrap_value(event.scope),
      causality_document: JsonDocument.wrap_value(event.causality),
      payload_document: JsonDocument.wrap_value(event.payload),
      previous_document: JsonDocument.wrap_value(event.previous),
      current_document: JsonDocument.wrap_value(event.current),
      metadata_document: JsonDocument.wrap_value(event.metadata)
    }
  end

  defp subject_document(%__MODULE__{subject_kind: nil}), do: nil

  defp subject_document(%__MODULE__{} = row) do
    %{kind: row.subject_kind, id: row.subject_id}
  end

  defp causality_document(%__MODULE__{} = row) do
    row.causality_document
    |> JsonDocument.unwrap_value()
    |> Map.merge(%{
      "correlation_id" => row.correlation_id,
      "causation_event_id" => row.causation_event_id,
      "source_record_kind" => row.source_record_kind,
      "source_record_id" => row.source_record_id,
      "job_id" => row.job_id,
      "replay_run_id" => row.replay_run_id,
      "import_run_id" => row.import_run_id
    })
    |> compact_string_map()
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)

  defp subject_kind(nil), do: nil

  defp subject_kind(subject) when is_map(subject),
    do: subject |> Map.get(:kind) |> maybe_atom_to_string()

  defp subject_id(nil), do: nil
  defp subject_id(subject) when is_map(subject), do: Map.get(subject, :id)

  defp compact_string_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
    |> Map.new()
  end
end
