for file <- ~w(fixture configuration seed activation live_contacts) do
  Code.require_file("/lab/reflect_orbital/#{file}.exs")
end

unless Cadence.Dev.ReflectOrbital.Fixture.chaos_lab?(), do: raise("Not the isolated chaos lab")

case System.fetch_env!("LAB_ACTION") do
  "seed" ->
    Cadence.Dev.ReflectOrbital.Seed.run()

  "activate" ->
    # Explicitly synthetic mission; this changes only the lab Earendil policy.
    result = Cadence.Dev.ReflectOrbital.Activation.run(true)
    IO.puts("Fleet activation: " <> inspect(result, pretty: true))

  "contacts" ->
    contacts = Cadence.Dev.ReflectOrbital.LiveContacts.run(28_800)
    IO.puts(Jason.encode!(contacts))

  "questdb" ->
    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, result} = Cadence.Telemetry.Storage.QuestDB.SchemaMigrator.apply_pending()
    IO.puts(inspect(result, pretty: true))
end
