Code.require_file("/lab/reflect_orbital/fixture.exs")
Code.require_file("/lab/reflect_orbital/live_contacts.exs")

unless Cadence.Dev.ReflectOrbital.Fixture.chaos_lab?(), do: raise("Not the isolated chaos lab")

contacts = Cadence.Dev.ReflectOrbital.LiveContacts.run(28_800)
IO.puts(Jason.encode!(contacts))
