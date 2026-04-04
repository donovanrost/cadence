defmodule Cadence.Persistence.Schemas.IngressArchiveEvidenceEntryRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:evidence_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "ingress_archive_evidence_entries" do
    field(:segment_id, :string)
    field(:object_key, :string)
    field(:archive_backend, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:direction, :string)
    field(:source_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:source_ref, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:provider_binding_id, :string)
    field(:raw_size_bytes, :integer)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :evidence_id,
    :segment_id,
    :object_key,
    :archive_backend,
    :mission_id,
    :protocol_family,
    :direction,
    :receipt_time,
    :raw_size_bytes
  ]

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, all_fields())
    |> validate_required(@required_fields)
  end

  def all_fields do
    [
      :evidence_id,
      :segment_id,
      :object_key,
      :archive_backend,
      :mission_id,
      :organization_id,
      :source_endpoint_ref,
      :spacecraft_id,
      :protocol_family,
      :direction,
      :source_time,
      :receipt_time,
      :source_ref,
      :realized_contact_id,
      :path_id,
      :provider_binding_id,
      :raw_size_bytes,
      :metadata
    ]
  end
end
