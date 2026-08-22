defmodule Cadence.Notifications.NotificationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Notifications.Notification
  alias Cadence.Persistence.JsonDocument

  @primary_key {:notification_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "notifications" do
    field(:user_id, :string)
    field(:kind, :string)
    field(:title, :string)
    field(:body, :string)
    field(:action_url, :string)
    field(:metadata, :map, default: %{})
    field(:read_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [:notification_id, :user_id, :kind, :title, :metadata]

  @spec changeset(Notification.t()) :: Ecto.Changeset.t()
  def changeset(%Notification{} = notification) do
    %__MODULE__{}
    |> cast(row_attrs(notification), all_fields())
    |> validate_required(@required_fields)
  end

  @spec mark_read_changeset(struct(), DateTime.t()) :: Ecto.Changeset.t()
  def mark_read_changeset(%__MODULE__{} = row, %DateTime{} = read_at) do
    cast(row, %{read_at: read_at}, [:read_at])
  end

  @spec to_domain(struct()) :: Notification.t()
  def to_domain(%__MODULE__{} = row) do
    %Notification{
      notification_id: row.notification_id,
      user_id: row.user_id,
      kind: String.to_existing_atom(row.kind),
      title: row.title,
      body: row.body,
      action_url: row.action_url,
      metadata: JsonDocument.unwrap_value(row.metadata),
      read_at: row.read_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    }
  end

  defp row_attrs(%Notification{} = n) do
    %{
      notification_id: n.notification_id,
      user_id: n.user_id,
      kind: Atom.to_string(n.kind),
      title: n.title,
      body: n.body,
      action_url: n.action_url,
      metadata: JsonDocument.wrap_value(n.metadata),
      read_at: n.read_at
    }
  end

  defp all_fields do
    [:notification_id, :user_id, :kind, :title, :body, :action_url, :metadata, :read_at]
  end
end
