# Run with: mise exec -- env ERL_EPMD_ADDRESS=127.0.0.1 elixir --sname earendil_setup_$CADENCE_DEV_SLOT --cookie "$CADENCE_ERLANG_COOKIE" --erl '-kernel inet_dist_use_interface {127,0,0,1}' dev/reflect_orbital_activate.exs --single-operator
# Executes in the existing named Cadence server so its runtime receives the activation.
Logger.configure(level: :warning)
{:ok, hostname} = :inet.gethostname()
# EARENDIL_CADENCE_NODE targets another worktree's server.
peer_name =
  System.get_env("EARENDIL_CADENCE_NODE") || "cadence_#{System.fetch_env!("CADENCE_DEV_SLOT")}"

peer = :"#{peer_name}@#{hostname}"
# The fleet size comes from this shell's environment, not the server's.
Code.require_file("reflect_orbital/fixture.exs", __DIR__)
expected = Cadence.Dev.ReflectOrbital.Fixture.fleet_size()
true = Node.connect(peer)
:ok = :rpc.call(peer, Phoenix.CodeReloader, :reload, [CadenceWeb.Endpoint], 120_000)

for file <- ["reflect_orbital/fixture.exs", "reflect_orbital/activation.exs"] do
  result = :rpc.call(peer, Code, :compile_file, [Path.join(__DIR__, file)])
  if match?({:badrpc, _}, result), do: raise(inspect(result))
end

case :rpc.call(
       peer,
       Cadence.Dev.ReflectOrbital.Activation,
       :run,
       ["--single-operator" in System.argv(), expected],
       :infinity
     ) do
  %{spacecraft: ^expected} = result ->
    IO.puts("Verified active Earendil fleet: " <> inspect(result, pretty: true))

  error ->
    raise "Earendil activation failed: #{inspect(error, limit: 20)}"
end
