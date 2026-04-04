defmodule Cadence.Persistence.Schemas.RawEvidenceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:evidence_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "ingress_raw_evidence" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:direction, :string)
    field(:raw, :binary)
    field(:source_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:source_ref, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :evidence_id,
    :mission_id,
    :protocol_family,
    :direction,
    :raw,
    :receipt_time
  ]

  @spec changeset(RawEvidence.t()) :: Ecto.Changeset.t()
  def changeset(%RawEvidence{} = raw_evidence) do
    %__MODULE__{}
    |> cast(domain_attrs(raw_evidence), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: RawEvidence.t()
  def to_domain(%__MODULE__{} = raw_evidence_row) do
    %RawEvidence{
      evidence_id: raw_evidence_row.evidence_id,
      mission_id: raw_evidence_row.mission_id,
      source_endpoint_ref: raw_evidence_row.source_endpoint_ref,
      spacecraft_id: raw_evidence_row.spacecraft_id,
      protocol_family: String.to_existing_atom(raw_evidence_row.protocol_family),
      direction: String.to_existing_atom(raw_evidence_row.direction),
      raw: raw_evidence_row.raw,
      source_time: raw_evidence_row.source_time,
      receipt_time: raw_evidence_row.receipt_time,
      source_ref: raw_evidence_row.source_ref,
      metadata: raw_evidence_row.metadata
    }
  end

  defp domain_attrs(%RawEvidence{} = raw_evidence) do
    %{
      evidence_id: raw_evidence.evidence_id,
      mission_id: raw_evidence.mission_id,
      source_endpoint_ref: raw_evidence.source_endpoint_ref,
      spacecraft_id: raw_evidence.spacecraft_id,
      protocol_family: Atom.to_string(raw_evidence.protocol_family),
      direction: Atom.to_string(raw_evidence.direction),
      raw: raw_evidence.raw,
      source_time: raw_evidence.source_time,
      receipt_time: raw_evidence.receipt_time,
      source_ref: raw_evidence.source_ref,
      metadata: JsonDocument.encode(raw_evidence.metadata)
    }
  end

  defp all_fields do
    [
      :evidence_id,
      :mission_id,
      :source_endpoint_ref,
      :spacecraft_id,
      :protocol_family,
      :direction,
      :raw,
      :source_time,
      :receipt_time,
      :source_ref,
      :metadata
    ]
  end
end
