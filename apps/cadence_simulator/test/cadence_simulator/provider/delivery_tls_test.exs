defmodule CadenceSimulator.Provider.DeliveryTLSTest do
  use ExUnit.Case, async: false

  alias CadenceSimulator.Provider.DeliveryTLS

  @curve {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}}
  @target {127, 0, 0, 1}
  @timeout 5_000
  @identity {"run_server_san", "delivery_credential_server_san"}

  test "verifies an IP target against the server's IP SAN" do
    ca =
      :public_key.pkix_test_root_cert(~c"Simulator delivery test CA",
        key: @curve,
        digest: :sha256
      )

    client = leaf(ca, dNSName: ~c"simulator.test")
    {key_type, key_der} = client[:key]

    configure_backend(%{
      certificate_pem: pem(:Certificate, client[:cert]),
      private_key_pem: pem(key_type, key_der),
      server_ca_pem: pem(:Certificate, ca.cert)
    })

    with_server(ca, <<127, 0, 0, 1>>, fn port ->
      assert {:ok, socket} = connect(port)
      :ok = :ssl.close(socket)
    end)

    with_server(ca, <<127, 0, 0, 2>>, fn port ->
      assert {:error, :delivery_tls_handshake_failed} = connect(port)
    end)
  end

  defp connect(port) do
    host = @target |> :inet.ntoa() |> List.to_string()
    DeliveryTLS.connect(@identity, host, port, [:binary, active: false], @timeout)
  end

  defp with_server(ca, advertised_ip, check) do
    server = leaf(ca, iPAddress: advertised_ip)

    {:ok, listener} =
      :ssl.listen(0, [
        :binary,
        ip: @target,
        active: false,
        cert: server[:cert],
        key: server[:key],
        log_level: :none
      ])

    try do
      {:ok, {@target, port}} = :ssl.sockname(listener)

      handshake =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, @timeout)

          case :ssl.handshake(socket, @timeout) do
            {:ok, connected} -> :ssl.close(connected)
            {:error, {:tls_alert, _alert}} -> :ok
          end
        end)

      check.(port)
      :ok = Task.await(handshake, @timeout)
    after
      :ssl.close(listener)
    end
  end

  defp leaf(ca, names) do
    :public_key.pkix_test_data(%{
      root: ca,
      peer: [
        key: @curve,
        digest: :sha256,
        extensions: [{:Extension, {2, 5, 29, 17}, false, names}]
      ]
    })
  end

  defp pem(type, der), do: :public_key.pem_encode([{type, der, :not_encrypted}])

  defp configure_backend(material) do
    previous = Application.fetch_env(:cadence_simulator, :delivery_tls_backend)

    Application.put_env(:cadence_simulator, :delivery_tls_backend, fn run, ref ->
      assert {run, ref} == @identity
      {:ok, material}
    end)

    on_exit(fn ->
      case previous do
        {:ok, backend} -> Application.put_env(:cadence_simulator, :delivery_tls_backend, backend)
        :error -> Application.delete_env(:cadence_simulator, :delivery_tls_backend)
      end
    end)
  end
end
