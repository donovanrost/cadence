defmodule Cadence.Persistence.Schemas.CommandQueueEntryRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Persistence.JsonDocument

  @primary_key {:command_queue_entry_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_queue_entries" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:command_request_id, :string)
    field(:source_endpoint_ref, :string)
    field(:queue_lane_key, :string)
    field(:priority, :integer, default: 3)
    field(:queue_sequence, :integer)
    field(:not_before, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:lifecycle_state, :string)
    field(:enqueued_by_document, :map, default: %{})
    field(:enqueued_at, :utc_datetime_usec)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_queue_entry_id,
    :mission_id,
    :command_request_id,
    :source_endpoint_ref,
    :queue_lane_key,
    :priority,
    :queue_sequence,
    :lifecycle_state,
    :enqueued_by_document,
    :enqueued_at,
    :metadata_document
  ]

  @spec changeset(CommandQueueEntry.t()) :: Ecto.Changeset.t()
  def changeset(%CommandQueueEntry{} = command_queue_entry) do
    %__MODULE__{}
    |> cast(domain_attrs(command_queue_entry), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:queue_sequence, greater_than: 0)
    |> unique_constraint([:mission_id, :command_queue_entry_id],
      name: :command_queue_entries_scope_idx
    )
    |> unique_constraint([:organization_id, :mission_id, :command_request_id],
      name: :command_queue_entries_request_org_scope_idx
    )
  end

  @spec lifecycle_changeset(struct(), atom()) :: Ecto.Changeset.t()
  def lifecycle_changeset(%__MODULE__{} = row, lifecycle_state) when is_atom(lifecycle_state) do
    change(row, %{lifecycle_state: Atom.to_string(lifecycle_state)})
  end

  @spec to_domain(struct()) :: CommandQueueEntry.t()
  def to_domain(%__MODULE__{} = row) do
    CommandQueueEntry.new(%{
      command_queue_entry_id: row.command_queue_entry_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      command_request_id: row.command_request_id,
      source_endpoint_ref: row.source_endpoint_ref,
      queue_lane_key: row.queue_lane_key,
      priority: row.priority,
      queue_sequence: row.queue_sequence,
      not_before: row.not_before,
      expires_at: row.expires_at,
      lifecycle_state: row.lifecycle_state,
      enqueued_by: JsonDocument.unwrap_value(row.enqueued_by_document),
      enqueued_at: row.enqueued_at,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandQueueEntry{} = command_queue_entry) do
    %{
      command_queue_entry_id: command_queue_entry.command_queue_entry_id,
      organization_id: command_queue_entry.organization_id,
      mission_id: command_queue_entry.mission_id,
      command_request_id: command_queue_entry.command_request_id,
      source_endpoint_ref: command_queue_entry.source_endpoint_ref,
      queue_lane_key: command_queue_entry.queue_lane_key,
      priority: command_queue_entry.priority,
      queue_sequence: command_queue_entry.queue_sequence,
      not_before: command_queue_entry.not_before,
      expires_at: command_queue_entry.expires_at,
      lifecycle_state: Atom.to_string(command_queue_entry.lifecycle_state),
      enqueued_by_document: JsonDocument.wrap_value(command_queue_entry.enqueued_by),
      enqueued_at: command_queue_entry.enqueued_at,
      metadata_document: JsonDocument.wrap_value(command_queue_entry.metadata)
    }
  end

  defp all_fields do
    [
      :command_queue_entry_id,
      :organization_id,
      :mission_id,
      :command_request_id,
      :source_endpoint_ref,
      :queue_lane_key,
      :priority,
      :queue_sequence,
      :not_before,
      :expires_at,
      :lifecycle_state,
      :enqueued_by_document,
      :enqueued_at,
      :metadata_document
    ]
  end
end
