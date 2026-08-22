defmodule Cadence.Links.ProtocolConfig do
  @moduledoc """
  Link-owned protocol configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "protocol_configs" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :link, Cadence.Links.Link

    field :config, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a protocol config.
  """
  def changeset(protocol_config, attrs, organization_id, mission_id) do
    protocol_config
    |> cast(attrs, [:link_id, :config])
    |> put_change(:organization_id, organization_id)
    |> put_change(:mission_id, mission_id)
    |> validate_required([:organization_id, :mission_id, :link_id])
    |> unique_constraint([:link_id], name: :protocol_configs_link_index)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:link_id)
  end

  @doc """
  Changeset for updating a protocol config.
  """
  def update_changeset(protocol_config, attrs) do
    protocol_config
    |> cast(attrs, [:config])
  end
end
