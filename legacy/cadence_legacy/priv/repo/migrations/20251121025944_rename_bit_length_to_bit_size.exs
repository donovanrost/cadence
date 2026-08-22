defmodule Cadence.Repo.Migrations.RenameBitLengthToBitSize do
  use Ecto.Migration

  def change do
    rename table(:packet_items), :bit_length, to: :bit_size
  end
end
