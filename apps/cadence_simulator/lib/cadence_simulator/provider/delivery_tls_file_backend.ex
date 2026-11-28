defmodule CadenceSimulator.Provider.DeliveryTLSFileBackend do
  @moduledoc "Reads development delivery credentials from a private directory outside the simulator store."

  alias CadenceSimulator.Provider.DeliveryTLS

  def resolve(run_id, ref, root) do
    with true <- DeliveryTLS.valid_identifier?(run_id) and DeliveryTLS.valid_reference?(ref),
         {:ok, encoded} <- File.read(Path.join([root, run_id, ref <> ".json"])),
         {:ok, %{"certificate_pem" => leaf, "private_key_pem" => key, "server_ca_pem" => ca}} <-
           Jason.decode(encoded) do
      {:ok, %{certificate_pem: leaf, private_key_pem: key, server_ca_pem: ca}}
    else
      _unavailable -> {:error, :delivery_tls_credential_unavailable}
    end
  end
end
