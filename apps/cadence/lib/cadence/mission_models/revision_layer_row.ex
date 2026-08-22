defmodule Cadence.MissionModels.RevisionLayerRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  schema "mission_model_revision_layers" do
    field(:revision_id, :string, primary_key: true)
    field(:layer_id, :string, primary_key: true)
    field(:position, :integer)
  end

  def changeset(revision_id, layer_id, position) do
    %__MODULE__{}
    |> cast(
      %{revision_id: revision_id, layer_id: layer_id, position: position},
      [:revision_id, :layer_id, :position]
    )
    |> validate_required([:revision_id, :layer_id, :position])
  end
end
