defmodule Cadence.MissionModels.LayerRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:layer_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_layers" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:layer_kind, :string)
    field(:status, :string)
    field(:version, :integer)
    field(:name, :string)
    field(:content_sha256, :string)
    field(:declaration_count, :integer)
    field(:source_document, :map)
    field(:layer_document, :map)

    timestamps()
  end

  @spec changeset(Layer.t()) :: Ecto.Changeset.t()
  def changeset(%Layer{} = layer) do
    %__MODULE__{}
    |> cast(attrs(layer), fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(fields() -- [:organization_id])
    |> unique_constraint([:mission_id, :content_sha256])
  end

  @spec to_domain(struct()) :: Layer.t()
  def to_domain(%__MODULE__{} = row) do
    row.layer_document
    |> JsonDocument.unwrap_value()
    |> Map.merge(%{
      "layer_id" => row.layer_id,
      "organization_id" => row.organization_id,
      "mission_id" => row.mission_id,
      "layer_kind" => row.layer_kind,
      "status" => row.status,
      "version" => row.version,
      "name" => row.name,
      "content_sha256" => row.content_sha256
    })
    |> Layer.new()
  end

  defp attrs(layer) do
    %{
      layer_id: layer.layer_id,
      organization_id: layer.organization_id,
      mission_id: layer.mission_id,
      layer_kind: Atom.to_string(layer.layer_kind),
      status: Atom.to_string(layer.status),
      version: layer.version,
      name: layer.name,
      content_sha256: layer.content_sha256,
      declaration_count: length(layer.declarations),
      source_document: JsonDocument.wrap_value(layer.source),
      layer_document: JsonDocument.wrap_value(layer)
    }
  end

  defp fields do
    [
      :layer_id,
      :organization_id,
      :mission_id,
      :layer_kind,
      :status,
      :version,
      :name,
      :content_sha256,
      :declaration_count,
      :source_document,
      :layer_document
    ]
  end
end
