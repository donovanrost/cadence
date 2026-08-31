defmodule CadenceWeb.FrontendReleasePublication.ReleaseObject do
  @moduledoc "Immutable content-addressed frontend release bytes stored in PostgreSQL."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:sha256, :string, autogenerate: false}

  schema "frontend_release_objects" do
    field(:bytes, :binary)
    field(:size, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end

  @fields [:sha256, :bytes, :size, :inserted_at]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> check_constraint(:sha256, name: :frontend_release_objects_sha256_check)
    |> check_constraint(:size, name: :frontend_release_objects_size_check)
    |> check_constraint(:bytes, name: :frontend_release_objects_octet_length_check)
  end
end
