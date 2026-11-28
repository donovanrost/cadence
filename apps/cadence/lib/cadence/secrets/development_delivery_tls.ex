defmodule Cadence.Secrets.DevelopmentDeliveryTLS do
  @moduledoc "Local-only TLS material for the development stack and transport tests."

  @p256 {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}}
  @files %{
    server_certificate_pem: "server.pem",
    server_key_pem: "server-key.pem",
    server_ca_pem: "server-ca.pem",
    client_ca_pem: "client-ca.pem",
    client_ca_key_pem: "client-ca-key.pem"
  }

  def generate do
    server_ca =
      :public_key.pkix_test_root_cert(~c"Cadence local server CA", key: @p256, digest: :sha256)

    client_ca =
      :public_key.pkix_test_root_cert(~c"Cadence local client CA", key: @p256, digest: :sha256)

    server =
      :public_key.pkix_test_data(%{
        root: server_ca,
        peer: [
          key: @p256,
          digest: :sha256,
          extensions: [
            {:Extension, {2, 5, 29, 17}, false,
             [iPAddress: <<127, 0, 0, 1>>, dNSName: ~c"localhost"]},
            {:Extension, {2, 5, 29, 37}, false, [{1, 3, 6, 1, 5, 5, 7, 3, 1}]}
          ]
        ]
      })

    %{
      server_certificate_pem: pem(:Certificate, server[:cert]),
      server_key_pem: key_pem(server[:key]),
      server_ca_pem: pem(:Certificate, server_ca.cert),
      client_ca_pem: pem(:Certificate, client_ca.cert),
      client_ca_key_pem: pem(:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, client_ca.key))
    }
  end

  def ensure!(directory) do
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)

    if Enum.any?(@files, fn {_key, file} -> not File.regular?(Path.join(directory, file)) end) do
      material = generate()

      Enum.each(@files, fn {key, file} ->
        path = Path.join(directory, file)
        File.write!(path, Map.fetch!(material, key))
        File.chmod!(path, 0o600)
      end)
    end

    :ok
  end

  def resolve(%{purpose: "provider_delivery_listener"}, opts) do
    read_material(opts, %{
      certificate_pem: :server_certificate_pem,
      private_key_pem: :server_key_pem,
      client_ca_pem: :client_ca_pem
    })
  end

  def resolve(%{purpose: "provider_delivery_issuer"}, opts) do
    read_material(opts, %{certificate_pem: :client_ca_pem, private_key_pem: :client_ca_key_pem})
  end

  defp read_material(opts, names) do
    directory = Keyword.fetch!(opts, :development_directory)

    material =
      Map.new(names, fn {key, file} ->
        {key, File.read!(Path.join(directory, Map.fetch!(@files, file)))}
      end)

    {:ok, %{material: material}}
  rescue
    File.Error -> {:error, :delivery_tls_identity_unavailable}
  end

  defp key_pem({type, der}), do: pem(type, der)
  defp pem(type, der), do: :public_key.pem_encode([{type, der, :not_encrypted}])
end
