defmodule Cadence.Recordings.Recordables.CommandVerificationFailed do
  @moduledoc """
  Recordable for when command verification fails.

  Captures the reason for failure and the actual vs expected values
  that caused the mismatch.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_verification_faileds" do
    field :error_reason, :string
    field :verification_actual, :string
    field :verification_expected, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:error_reason, :verification_actual, :verification_expected])
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.CommandVerificationFailed do
  def recording_type(_), do: "CommandVerificationFailed"
  def aggregate_type(_), do: "Command"
  def title(_), do: "Verification Failed"
  def status(_), do: "verification_failed"
  def severity(_), do: "warning"
end
