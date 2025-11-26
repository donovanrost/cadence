# Update interface protocols to discard CCSDS sync pattern
# Run with: mix run priv/repo/seeds/update_interface_protocols.exs

import Ecto.Query
alias Cadence.Repo
alias Cadence.Interfaces.InterfaceProtocol

mission_id = "e4bc9d7a-43a4-42f7-9964-6ae3eadb7215"

IO.puts("Checking for interface protocols...")

# Find all template protocols for this mission
protocols =
  from(p in InterfaceProtocol,
    join: i in assoc(p, :interface),
    where: i.mission_id == ^mission_id,
    where: p.protocol_type == "template"
  )
  |> Repo.all()
  |> Repo.preload(:interface)
  |> Enum.filter(fn p -> Map.has_key?(p.protocol_config, "sync_pattern_hex") end)

if Enum.empty?(protocols) do
  IO.puts("No existing interface protocols found for this mission.")
  IO.puts("The system will use default CCSDS protocol configuration which has been updated.")
else
  IO.puts("Found #{length(protocols)} template protocol(s) to update:")

  Enum.each(protocols, fn protocol ->
    IO.puts("  - Interface: #{protocol.interface.name}, Protocol ID: #{protocol.id}")

    # Check if discard_leading_bytes is already set
    current_discard = get_in(protocol.protocol_config, ["discard_leading_bytes"])

    if current_discard == 4 do
      IO.puts("    Already configured with discard_leading_bytes=4, skipping")
    else
      # Update the protocol config
      new_config = Map.put(protocol.protocol_config, "discard_leading_bytes", 4)

      protocol
      |> Ecto.Changeset.change(protocol_config: new_config)
      |> Repo.update!()

      IO.puts("    ✓ Updated discard_leading_bytes from #{inspect(current_discard)} to 4")
    end
  end)
end

IO.puts("\n✓ Protocol configuration updated!")
