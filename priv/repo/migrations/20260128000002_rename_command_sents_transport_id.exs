defmodule Cadence.Repo.Migrations.RenameCommandSentsTransportId do
  use Ecto.Migration

  def change do
    rename table(:command_sents), :interface_id, to: :transport_id
  end
end
