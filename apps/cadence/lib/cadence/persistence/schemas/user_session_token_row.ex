defmodule Cadence.Persistence.Schemas.UserSessionTokenRow do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:session_token_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "user_session_tokens" do
    field(:user_id, :string)
    field(:context, :string)
    field(:token_digest, :string)
    field(:token_hint, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :session_token_id,
    :user_id,
    :context,
    :token_digest,
    :token_hint,
    :expires_at,
    :metadata
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:token_digest], name: :user_session_tokens_token_digest_index)
  end

  defp all_fields do
    [:session_token_id, :user_id, :context, :token_digest, :token_hint, :expires_at, :metadata]
  end
end
