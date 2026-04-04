defmodule Cadence.Persistence.Schemas.UserLocalCredentialRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:local_credential_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "user_local_credentials" do
    field(:user_id, :string)
    field(:provider_key, :string)
    field(:password_hash, :string)
    field(:password_salt, :string)
    field(:password_iterations, :integer)
    field(:lifecycle_state, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :local_credential_id,
    :user_id,
    :provider_key,
    :password_hash,
    :password_salt,
    :password_iterations,
    :lifecycle_state,
    :metadata
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :provider_key],
      name: :user_local_credentials_user_id_provider_key_index
    )
  end

  @spec update_changeset(struct(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :password_hash,
      :password_salt,
      :password_iterations,
      :lifecycle_state,
      :metadata
    ])
    |> validate_required([
      :password_hash,
      :password_salt,
      :password_iterations,
      :lifecycle_state,
      :metadata
    ])
  end

  defp all_fields do
    [
      :local_credential_id,
      :user_id,
      :provider_key,
      :password_hash,
      :password_salt,
      :password_iterations,
      :lifecycle_state,
      :metadata
    ]
  end
end
