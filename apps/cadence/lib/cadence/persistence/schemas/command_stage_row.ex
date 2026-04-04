defmodule Cadence.Persistence.Schemas.CommandStageRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.CommandStage
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:command_stage_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_stages" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:stage_name, :string)
    field(:description, :string)
    field(:owner_document, :map, default: %{})
    field(:visibility, :string)
    field(:lifecycle_state, :string)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_stage_id,
    :mission_id,
    :stage_name,
    :owner_document,
    :visibility,
    :lifecycle_state,
    :metadata_document
  ]

  @spec changeset(CommandStage.t()) :: Ecto.Changeset.t()
  def changeset(%CommandStage{} = command_stage) do
    %__MODULE__{}
    |> cast(domain_attrs(command_stage), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :command_stage_id], name: :command_stages_scope_idx)
  end

  @spec update_changeset(struct(), CommandStage.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %CommandStage{} = command_stage) do
    row
    |> cast(domain_attrs(command_stage), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec lifecycle_changeset(struct(), atom()) :: Ecto.Changeset.t()
  def lifecycle_changeset(%__MODULE__{} = row, lifecycle_state) when is_atom(lifecycle_state) do
    change(row, %{lifecycle_state: Atom.to_string(lifecycle_state)})
  end

  @spec to_domain(struct()) :: CommandStage.t()
  def to_domain(%__MODULE__{} = row) do
    CommandStage.new(%{
      command_stage_id: row.command_stage_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      stage_name: row.stage_name,
      description: row.description,
      owner: JsonDocument.unwrap_value(row.owner_document),
      visibility: row.visibility,
      lifecycle_state: row.lifecycle_state,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandStage{} = command_stage) do
    %{
      command_stage_id: command_stage.command_stage_id,
      organization_id: command_stage.organization_id,
      mission_id: command_stage.mission_id,
      stage_name: command_stage.stage_name,
      description: command_stage.description,
      owner_document: JsonDocument.wrap_value(command_stage.owner),
      visibility: Atom.to_string(command_stage.visibility),
      lifecycle_state: Atom.to_string(command_stage.lifecycle_state),
      metadata_document: JsonDocument.wrap_value(command_stage.metadata)
    }
  end

  defp all_fields do
    [
      :command_stage_id,
      :organization_id,
      :mission_id,
      :stage_name,
      :description,
      :owner_document,
      :visibility,
      :lifecycle_state,
      :metadata_document
    ]
  end
end
