defmodule Mix.Tasks.Cadence.Repairs.BackfillPairing do
  @shortdoc "Persists the replaces pairing on repairs applied before it existed (qa #30)"
  @moduledoc """
  One-time, per mission: `mix cadence.repairs.backfill_pairing ORGANIZATION_ID MISSION_ID`.

  Repairs applied before the repair-chain model (qa #30) have no persisted pairing, so the lost
  bookings they re-booked still read as lost. This pairs them the same way a repair does at
  creation (`Cadence.ContactPlanning.RepairChain.backfill/2`) and prints the runs it filled.
  It only touches runs without a pairing, so a rerun does nothing.
  """

  use Mix.Task

  alias Cadence.ContactPlanning.RepairChain

  @impl Mix.Task
  def run([organization_id, mission_id]) do
    Mix.Task.run("app.start")
    filled = RepairChain.backfill(organization_id, mission_id)
    Mix.shell().info("Filled #{length(filled)} repair run(s): #{Enum.join(filled, ", ")}")
  end

  def run(_args),
    do: Mix.raise("usage: mix cadence.repairs.backfill_pairing ORGANIZATION_ID MISSION_ID")
end
