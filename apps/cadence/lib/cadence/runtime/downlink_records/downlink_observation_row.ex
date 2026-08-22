defmodule Cadence.Runtime.DownlinkRecords.DownlinkObservationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.DownlinkObservation
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:observation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "downlink_observations" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:source_endpoint_ref, :string)
    field(:observation_key, :string)
    field(:payload, :map, default: %{})
    field(:quality_score, :integer)
    field(:observed_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :observation_id,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :observation_key,
    :payload,
    :quality_score,
    :observed_at,
    :metadata
  ]

  @spec changeset(DownlinkObservation.t()) :: Ecto.Changeset.t()
  def changeset(%DownlinkObservation{} = observation) do
    %__MODULE__{}
    |> cast(domain_attrs(observation), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  defp domain_attrs(%DownlinkObservation{} = observation) do
    %{
      observation_id: observation.observation_id,
      mission_id: observation.mission_id,
      realized_contact_id: observation.realized_contact_id,
      path_id: observation.path_id,
      source_endpoint_ref: observation.source_endpoint_ref,
      observation_key: observation.observation_key,
      payload: JsonDocument.wrap_value(observation.payload),
      quality_score: observation.quality_score,
      observed_at: observation.observed_at,
      metadata: JsonDocument.encode(observation.metadata)
    }
  end

  defp all_fields do
    [
      :observation_id,
      :mission_id,
      :realized_contact_id,
      :path_id,
      :source_endpoint_ref,
      :observation_key,
      :payload,
      :quality_score,
      :observed_at,
      :metadata
    ]
  end
end
