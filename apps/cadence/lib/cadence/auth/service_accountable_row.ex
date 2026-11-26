defmodule Cadence.Auth.ServiceAccountableRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:accountable_id, :string, autogenerate: false}
  @events ~w(issued rotated attributed)
  @actor_kinds ~w(user service)

  schema "service_identity_accountables" do
    field(:organization_id, :string)
    field(:service_identity_id, :string)
    field(:event, :string)
    field(:actor_kind, :string)
    field(:user_id, :string)
    field(:by_service_identity_id, :string)
    field(:recorded_by_user_id, :string)
    field(:recorded_at, :utc_datetime_usec)
  end

  @fields [
    :accountable_id,
    :organization_id,
    :service_identity_id,
    :event,
    :actor_kind,
    :user_id,
    :by_service_identity_id,
    :recorded_by_user_id,
    :recorded_at
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([
      :accountable_id,
      :organization_id,
      :service_identity_id,
      :event,
      :actor_kind,
      :recorded_at
    ])
    |> validate_inclusion(:event, @events)
    |> validate_inclusion(:actor_kind, @actor_kinds)
    |> check_constraint(:actor_kind, name: :service_identity_accountables_actor)
    |> foreign_key_constraint(:service_identity_id)
  end
end
