defmodule Cadence.Repo.Migrations.AddTmFrameProtocolType do
  use Ecto.Migration

  def change do
    drop constraint(:interface_protocols, :valid_protocol_type)

    create constraint(:interface_protocols, :valid_protocol_type,
             check:
               "protocol_type IN ('ccsds_133_0_b_2', 'ccsds_132_0_b_3_tm', 'ccsds_sdlp', 'length', 'template', 'terminated', 'fixed', 'crc')"
           )
  end
end
