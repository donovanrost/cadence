# Run with: elixir --sname earendil_setup --cookie cadence dev/reflect_orbital_activate.exs --single-operator
# Executes in the existing named Cadence server so its runtime receives the activation.
Logger.configure(level: :warning)
{:ok, hostname} = :inet.gethostname()
peer = :"cadence@#{hostname}"
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
       ["--single-operator" in System.argv()],
       :infinity
     ) do
  %{spacecraft: 500} = result -> IO.inspect(result, label: "Verified active Earendil fleet")
  error -> raise "Earendil activation failed: #{inspect(error, limit: 20)}"
end
