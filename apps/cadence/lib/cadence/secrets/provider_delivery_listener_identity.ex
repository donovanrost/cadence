defmodule Cadence.Secrets.ProviderDeliveryListenerIdentity do
  @moduledoc false

  require Record
  alias Cadence.Secrets.Resolver

  for {name, type} <- [
        certificate: :OTPCertificate,
        tbs: :OTPTBSCertificate,
        subject_key: :OTPSubjectPublicKeyInfo,
        algorithm: :PublicKeyAlgorithm,
        point: :ECPoint
      ] do
    Record.defrecordp(
      name,
      type,
      Record.extract(type, from_lib: "public_key/include/public_key.hrl")
    )
  end

  def configured? do
    match?({:ok, _options}, socket_options())
  end

  def socket_options do
    opts = Application.get_env(:cadence, :provider_delivery_listener, [])

    with {:ok, reference} <- Keyword.fetch(opts, :secret_reference),
         {:ok, %{material: material}} <-
           Resolver.resolve(
             %{
               reference: reference,
               backend_key: reference,
               registry_version: 1,
               purpose: "provider_delivery_listener"
             },
             Keyword.put(opts, :allowed_material_keys, [
               :certificate_pem,
               :private_key_pem,
               :client_ca_pem
             ])
           ),
         [{:Certificate, certificate, :not_encrypted}] <-
           :public_key.pem_decode(material.certificate_pem),
         [{:Certificate, ca, :not_encrypted}] <- :public_key.pem_decode(material.client_ca_pem),
         [{type, key, :not_encrypted} = entry] <- :public_key.pem_decode(material.private_key_pem),
         true <- type in [:ECPrivateKey, :RSAPrivateKey, :PrivateKeyInfo],
         true <- matches_private_key?(certificate, entry),
         true <- :public_key.pkix_is_self_signed(ca) do
      {:ok,
       [
         cert: certificate,
         key: {type, key},
         cacerts: [ca],
         verify: :verify_peer,
         fail_if_no_peer_cert: true,
         depth: 0,
         versions: [:"tlsv1.3", :"tlsv1.2"],
         session_tickets: :disabled,
         reuse_sessions: false,
         client_renegotiation: false,
         log_level: :none
       ]}
    else
      _unavailable -> {:error, :delivery_tls_identity_unavailable}
    end
  rescue
    _error -> {:error, :delivery_tls_identity_unavailable}
  catch
    :exit, _reason -> {:error, :delivery_tls_identity_unavailable}
  end

  defp matches_private_key?(der, entry) do
    certificate(tbsCertificate: tbs(subjectPublicKeyInfo: key)) =
      :public_key.pkix_decode_cert(der, :otp)

    {public_key, digest} = verification_key(key)
    private_key = :public_key.pem_entry_decode(entry)
    message = "Cadence provider delivery listener key validation"
    signature = :public_key.sign(message, digest, private_key)
    :public_key.verify(message, digest, signature, public_key)
  end

  defp verification_key(
         subject_key(
           algorithm: algorithm(parameters: parameters),
           subjectPublicKey: point() = key
         )
       ) do
    digest =
      if parameters in [{:namedCurve, {1, 3, 101, 112}}, {:namedCurve, {1, 3, 101, 113}}],
        do: :none,
        else: :sha256

    {{key, parameters}, digest}
  end

  defp verification_key(subject_key(subjectPublicKey: key)), do: {key, :sha256}
end
