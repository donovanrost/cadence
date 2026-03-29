defmodule Cadence.Persistence.Schemas.CombinedDownlinkRecordRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.CombinedDownlinkRecord
  alias Cadence.Persistence.JsonDocument

  @primary_key {:merged_record_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "combined_downlink_records" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:realized_contact_id, :string)
    field(:observation_key, :string)
    field(:source_endpoint_ref, :string)
    field(:selected_path_id, :string)
    field(:selected_observation_id, :string)
    field(:payload, :map, default: %{})
    field(:selected_reason, :string)
    field(:observed_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :merged_record_id,
    :mission_id,
    :realized_contact_id,
    :observation_key,
    :selected_path_id,
    :selected_observation_id,
    :payload,
    :selected_reason,
    :observed_at,
    :metadata
  ]

  @spec changeset(CombinedDownlinkRecord.t()) :: Ecto.Changeset.t()
  def changeset(%CombinedDownlinkRecord{} = combined_record) do
    %__MODULE__{}
    |> cast(domain_attrs(combined_record), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: CombinedDownlinkRecord.t()
  def to_domain(%__MODULE__{} = row) do
    CombinedDownlinkRecord.new(%{
      merged_record_id: row.merged_record_id,
      mission_id: row.mission_id,
      realized_contact_id: row.realized_contact_id,
      observation_key: row.observation_key,
      source_endpoint_ref: row.source_endpoint_ref,
      selected_path_id: row.selected_path_id,
      selected_observation_id: row.selected_observation_id,
      payload: JsonDocument.unwrap_value(row.payload),
      selected_reason: String.to_existing_atom(row.selected_reason),
      observed_at: row.observed_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%CombinedDownlinkRecord{} = combined_record) do
    %{
      merged_record_id: combined_record.merged_record_id,
      mission_id: combined_record.mission_id,
      realized_contact_id: combined_record.realized_contact_id,
      observation_key: combined_record.observation_key,
      source_endpoint_ref: combined_record.source_endpoint_ref,
      selected_path_id: combined_record.selected_path_id,
      selected_observation_id: combined_record.selected_observation_id,
      payload: JsonDocument.wrap_value(combined_record.payload),
      selected_reason: Atom.to_string(combined_record.selected_reason),
      observed_at: combined_record.observed_at,
      metadata: JsonDocument.encode(combined_record.metadata)
    }
  end

  defp all_fields do
    [
      :merged_record_id,
      :mission_id,
      :realized_contact_id,
      :observation_key,
      :source_endpoint_ref,
      :selected_path_id,
      :selected_observation_id,
      :payload,
      :selected_reason,
      :observed_at,
      :metadata
    ]
  end
end
