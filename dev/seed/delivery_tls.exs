defmodule Cadence.Dev.Seed.DeliveryTLS do
  @moduledoc "Enrolls an opted-in local simulator binding using the operator enrollment action."

  alias Cadence.GroundNetworks.ProviderDeliveryCredentials

  def enroll!(scope, mission_id, provider_id, transport_id, run_id) do
    directory = System.fetch_env!("CADENCE_DEV_DELIVERY_TLS_DIRECTORY")
    enroll!(scope, mission_id, provider_id, transport_id, run_id, directory)
  end

  def enroll!(scope, mission_id, provider_id, transport_id, run_id, directory) do
    if !is_binary(run_id) or !Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, run_id) do
      raise ArgumentError, "Invalid simulator run identifier"
    end

    server_ca = File.read!(Path.join(directory, "server-ca.pem"))
    export_directory = Path.join([directory, "provider", run_id])
    File.mkdir_p!(export_directory)
    File.chmod!(export_directory, 0o700)
    scratch = Path.join(export_directory, Cadence.Ids.new("enrollment"))
    File.mkdir!(scratch)
    File.chmod!(scratch, 0o700)

    try do
      {csr, key} = request!(scratch)

      {:ok, signed} =
        ProviderDeliveryCredentials.issue(
          scope,
          mission_id,
          provider_id,
          transport_id,
          %{"reason" => "initial_enrollment", "csr_pem" => csr}
        )

      ref = signed.credential.credential_ref
      material = %{
        "certificate_pem" => signed.certificate_pem,
        "private_key_pem" => key,
        "server_ca_pem" => server_ca
      }

      case publish_material(scratch, export_directory, ref, material) do
        :ok -> ref
        {:error, _reason} -> revoke_unpublished!(scope, mission_id, provider_id, transport_id, signed)
      end
    after
      File.rm_rf!(scratch)
    end
  end

  defp request!(scratch) do
    key = Path.join(scratch, "key.pem")
    csr = Path.join(scratch, "request.pem")

    case System.cmd(
           "openssl",
           ["req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
            "-subj", "/CN=Cadence simulator delivery", "-keyout", key, "-out", csr],
           stderr_to_stdout: true
         ) do
      {_details, 0} -> {File.read!(csr), File.read!(key)}
      {_details, _status} -> raise "Could not generate the simulator delivery CSR"
    end
  end

  defp publish_material(scratch, directory, ref, material) do
    pending = Path.join(scratch, "material.json")

    with :ok <- File.write(pending, Jason.encode!(material)),
         :ok <- File.chmod(pending, 0o600) do
      File.rename(pending, Path.join(directory, ref <> ".json"))
    end
  end

  defp revoke_unpublished!(scope, mission, provider, binding, signed) do
    [%{fingerprint: fingerprint, state: :current} | _] = signed.credential.generations
    params = %{"fingerprint" => fingerprint, "reason" => "operator_requested"}

    case ProviderDeliveryCredentials.revoke(scope, mission, provider, binding, params) do
      {:ok, _credential} -> raise "Simulator credential export failed. The unpublished generation was revoked."
      {:error, _reason} -> raise "Simulator credential export failed. Revoke the unpublished generation."
    end
  end
end
