defmodule Cadence.Persistence.Schemas.DownlinkDiagnosticRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.DownlinkDiagnostic
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:diagnostic_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "downlink_diagnostics" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:realized_contact_id, :string)
    field(:observation_key, :string)
    field(:path_id, :string)
    field(:selected_path_id, :string)
    field(:observation_id, :string)
    field(:competing_observation_id, :string)
    field(:diagnostic_kind, :string)
    field(:recorded_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :diagnostic_id,
    :mission_id,
    :realized_contact_id,
    :observation_key,
    :path_id,
    :selected_path_id,
    :observation_id,
    :diagnostic_kind,
    :recorded_at,
    :metadata
  ]

  @spec changeset(DownlinkDiagnostic.t()) :: Ecto.Changeset.t()
  def changeset(%DownlinkDiagnostic{} = diagnostic) do
    %__MODULE__{}
    |> cast(domain_attrs(diagnostic), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: DownlinkDiagnostic.t()
  def to_domain(%__MODULE__{} = row) do
    DownlinkDiagnostic.new(%{
      diagnostic_id: row.diagnostic_id,
      mission_id: row.mission_id,
      realized_contact_id: row.realized_contact_id,
      observation_key: row.observation_key,
      path_id: row.path_id,
      selected_path_id: row.selected_path_id,
      observation_id: row.observation_id,
      competing_observation_id: row.competing_observation_id,
      diagnostic_kind: String.to_existing_atom(row.diagnostic_kind),
      recorded_at: row.recorded_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%DownlinkDiagnostic{} = diagnostic) do
    %{
      diagnostic_id: diagnostic.diagnostic_id,
      mission_id: diagnostic.mission_id,
      realized_contact_id: diagnostic.realized_contact_id,
      observation_key: diagnostic.observation_key,
      path_id: diagnostic.path_id,
      selected_path_id: diagnostic.selected_path_id,
      observation_id: diagnostic.observation_id,
      competing_observation_id: diagnostic.competing_observation_id,
      diagnostic_kind: Atom.to_string(diagnostic.diagnostic_kind),
      recorded_at: diagnostic.recorded_at,
      metadata: JsonDocument.encode(diagnostic.metadata)
    }
  end

  defp all_fields do
    [
      :diagnostic_id,
      :mission_id,
      :realized_contact_id,
      :observation_key,
      :path_id,
      :selected_path_id,
      :observation_id,
      :competing_observation_id,
      :diagnostic_kind,
      :recorded_at,
      :metadata
    ]
  end
end
