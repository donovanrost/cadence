defmodule Cadence.Recordings.Recordables.ContactActionFailed do
  @moduledoc """
  Recordable for when a contact action fails.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_action_faileds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :contact_action_id, :binary_id
    field :error_code, :string
    field :error_message, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:mission_id, :contact_id, :contact_action_id, :error_code]
  @optional_fields [:error_message, :details]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactActionFailed do
  def recording_type(_), do: "ContactActionFailed"
  def aggregate_type(_), do: "ContactAction"
  def title(_), do: "Contact Action Failed"
  def status(_), do: "failed"
  def severity(_), do: "warning"
end
