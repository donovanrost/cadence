defmodule Cadence.Recordings.Recordables.CommandVerified do
  @moduledoc """
  Recordable for when a command verification succeeds.

  Contains verification result details including which stages completed
  and the actual vs expected values.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_verifieds" do
    field :verification_item, :string
    field :verification_expected, :string
    field :verification_actual, :string
    field :verification_result, :map
    field :stages_completed, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [
      :verification_item,
      :verification_expected,
      :verification_actual,
      :verification_result,
      :stages_completed
    ])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandVerified do
  def recording_type(_), do: "CommandVerified"
  def aggregate_type(_), do: "Command"
  def title(_), do: "Command Verified"
  def status(_), do: "verified"
  def severity(_), do: nil
end
