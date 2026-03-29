defmodule Cadence.Persistence.Schemas.UserRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Persistence.JsonDocument

  @primary_key {:user_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "users" do
    field(:email, :string)
    field(:display_name, :string)
    field(:capabilities, {:array, :string}, default: [])
    field(:lifecycle_state, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [:user_id, :email, :display_name, :capabilities, :lifecycle_state, :metadata]

  @spec changeset(User.t()) :: Ecto.Changeset.t()
  def changeset(%User{} = user) do
    %__MODULE__{}
    |> cast(domain_attrs(user), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:email], name: :users_email_index)
  end

  @spec update_changeset(struct(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [:email, :display_name, :capabilities, :lifecycle_state, :metadata])
    |> validate_required(@required_fields -- [:user_id])
    |> unique_constraint([:email], name: :users_email_index)
  end

  @spec to_domain(struct()) :: User.t()
  def to_domain(%__MODULE__{} = row) do
    User.new(%{
      user_id: row.user_id,
      email: row.email,
      display_name: row.display_name,
      capabilities: Enum.map(row.capabilities, &User.normalize_capability/1),
      lifecycle_state: row.lifecycle_state,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%User{} = user) do
    %{
      user_id: user.user_id,
      email: user.email,
      display_name: user.display_name,
      capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(user.lifecycle_state),
      metadata: JsonDocument.wrap_value(user.metadata)
    }
  end

  defp all_fields do
    [:user_id, :email, :display_name, :capabilities, :lifecycle_state, :metadata]
  end
end
