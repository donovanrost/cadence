defmodule CadenceWeb.FrontendReleaseActivation.Control do
  @moduledoc "The singleton, one-way frontend catalog activation control row."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:control_id, :integer, autogenerate: false}

  schema "frontend_release_activation_controls" do
    field(:cutover_epoch, :integer)
    field(:cutover_at, :utc_datetime_usec)
    field(:legacy_catalog_publication_id, :string)
  end

  @fields [:control_id, :cutover_epoch, :cutover_at, :legacy_catalog_publication_id]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([:control_id, :cutover_epoch])
    |> check_constraint(:control_id,
      name: :frontend_release_activation_controls_singleton_check
    )
    |> check_constraint(:cutover_epoch,
      name: :frontend_release_activation_controls_cutover_check
    )
  end
end
