defmodule Cadence.Repo.Migrations.AddCcsdsProtocolType do
  use Ecto.Migration

  def change do
    # Drop the old constraint and create a new one with 'ccsds' included
    drop constraint(:interface_protocols, :valid_protocol_type)

    create constraint(:interface_protocols, :valid_protocol_type,
             check:
               "protocol_type IN ('ccsds', 'length', 'template', 'terminated', 'fixed', 'crc')"
           )
  end
end
