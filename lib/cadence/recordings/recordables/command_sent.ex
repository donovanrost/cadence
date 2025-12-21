defmodule Cadence.Recordings.Recordables.CommandSent do
  @moduledoc """
  Recordable for when a command is sent to an interface.

  This is a minimal recordable - just marks that transmission occurred.
  The timestamp in the recording captures when it was sent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_sents" do
    field :interface_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:interface_id])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandSent do
  def recording_type(_), do: "CommandSent"
  def aggregate_type(_), do: "Command"
  def title(_), do: "Command Sent"
  def status(_), do: "sent"
  def severity(_), do: nil
end
