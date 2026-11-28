defmodule Cadence.GroundNetworks.ProviderDeliveryCredentials.Issuer do
  @moduledoc false

  require Record
  import Bitwise

  alias Cadence.Secrets.Resolver

  for {name, type} <- [
        request: :CertificationRequest,
        request_info: :CertificationRequestInfo,
        request_key: :CertificationRequestInfo_subjectPKInfo,
        request_key_algorithm: :CertificationRequestInfo_subjectPKInfo_algorithm,
        request_signature_algorithm: :CertificationRequest_signatureAlgorithm,
        rsa_public_key: :RSAPublicKey,
        ec_point: :ECPoint,
        certificate: :OTPCertificate,
        tbs_certificate: :OTPTBSCertificate,
        validity: :Validity,
        attribute: :AttributeTypeAndValue,
        extension: :Extension,
        constraints: :BasicConstraints,
        spki: :OTPSubjectPublicKeyInfo,
        key_algorithm: :PublicKeyAlgorithm,
        signature_algorithm: :SignatureAlgorithm
      ] do
    Record.defrecordp(
      name,
      type,
      Record.extract(type, from_lib: "public_key/include/public_key.hrl")
    )
  end

  @max_csr_bytes 16_384
  @leaf_lifetime_days 30
  @ec {1, 2, 840, 10_045, 2, 1}
  @rsa {1, 2, 840, 113_549, 1, 1, 1}
  @curves [{1, 2, 840, 10_045, 3, 1, 7}, {1, 3, 132, 0, 34}, {1, 3, 132, 0, 35}]
  @signature_schemes %{
    {1, 2, 840, 10_045, 4, 3, 2} => {:ec, :sha256},
    {1, 2, 840, 10_045, 4, 3, 3} => {:ec, :sha384},
    {1, 2, 840, 10_045, 4, 3, 4} => {:ec, :sha512},
    {1, 2, 840, 113_549, 1, 1, 11} => {:rsa, :sha256},
    {1, 2, 840, 113_549, 1, 1, 12} => {:rsa, :sha384},
    {1, 2, 840, 113_549, 1, 1, 13} => {:rsa, :sha512}
  }

  def public_key(pem) when is_binary(pem) and byte_size(pem) <= @max_csr_bytes do
    with [{:CertificationRequest, der, :not_encrypted}] <- :public_key.pem_decode(pem),
         request(
           certificationRequestInfo: info,
           signatureAlgorithm: algorithm,
           signature: signature
         ) <-
           :public_key.der_decode(:CertificationRequest, der),
         request_info(version: :v1, subjectPKInfo: key) <- info,
         request_signature_algorithm(algorithm: oid) <- algorithm,
         {family, digest} <- Map.get(@signature_schemes, oid),
         {:ok, verification_key, subject_key} <- decode_key(key, family),
         true <-
           :public_key.verify(
             :public_key.der_encode(:CertificationRequestInfo, info),
             digest,
             signature,
             verification_key
           ) do
      {:ok, subject_key}
    else
      _invalid -> {:error, :invalid_delivery_csr}
    end
  rescue
    _error -> {:error, :invalid_delivery_csr}
  catch
    :exit, _reason -> {:error, :invalid_delivery_csr}
  end

  def public_key(_pem), do: {:error, :invalid_delivery_csr}

  def key_fingerprint(subject_key) do
    der = :public_key.pkix_encode(:OTPSubjectPublicKeyInfo, subject_key, :otp)
    Base.encode16(:crypto.hash(:sha256, der), case: :lower)
  end

  def issue(subject_key, credential_ref, now, opts) do
    with {:ok, ca, ca_key} <- issuer_material(opts),
         {:ok, signature} <- issuer_signature(ca_key),
         certificate(tbsCertificate: tbs_certificate(subject: issuer)) <-
           :public_key.pkix_decode_cert(ca, :otp) do
      expires_at = now |> DateTime.add(@leaf_lifetime_days, :day) |> DateTime.truncate(:second)

      leaf =
        tbs_certificate(
          version: :v3,
          serialNumber: :binary.decode_unsigned(:crypto.strong_rand_bytes(16)) + 1,
          issuer: issuer,
          signature: signature,
          subject:
            {:rdnSequence,
             [[attribute(type: {2, 5, 4, 3}, value: {:utf8String, credential_ref})]]},
          subjectPublicKeyInfo: subject_key,
          validity: validity(notBefore: pkix_time(now), notAfter: pkix_time(expires_at)),
          extensions: [
            extension(extnID: {2, 5, 29, 19}, critical: true, extnValue: constraints(cA: false)),
            extension(extnID: {2, 5, 29, 15}, critical: true, extnValue: [:digitalSignature]),
            extension(
              extnID: {2, 5, 29, 37},
              critical: false,
              extnValue: [{1, 3, 6, 1, 5, 5, 7, 3, 2}]
            )
          ]
        )
        |> :public_key.pkix_sign(ca_key)

      case :public_key.pkix_path_validation(ca, [leaf], []) do
        {:ok, _chain} ->
          {:ok,
           %{
             certificate_pem: pem(leaf),
             issuer_certificate_pem: pem(ca),
             fingerprint: Base.encode16(:crypto.hash(:sha256, leaf), case: :lower),
             expires_at: expires_at
           }}

        _invalid ->
          {:error, :delivery_issuer_unavailable}
      end
    else
      _unavailable -> {:error, :delivery_issuer_unavailable}
    end
  rescue
    _error -> {:error, :delivery_issuer_unavailable}
  catch
    :exit, _reason -> {:error, :delivery_issuer_unavailable}
  end

  defp decode_key(
         request_key(
           algorithm: request_key_algorithm(algorithm: @ec, parameters: {:asn1_OPENTYPE, params}),
           subjectPublicKey: point
         ),
         :ec
       ) do
    case :public_key.der_decode(:EcpkParameters, params) do
      {:namedCurve, curve} = parameters when curve in @curves ->
        ec = ec_point(point: point)

        {:ok, {ec, parameters},
         spki(
           algorithm: key_algorithm(algorithm: @ec, parameters: parameters),
           subjectPublicKey: ec
         )}

      _weak ->
        {:error, :invalid_delivery_csr}
    end
  end

  defp decode_key(
         request_key(algorithm: request_key_algorithm(algorithm: @rsa), subjectPublicKey: der),
         :rsa
       ) do
    case :public_key.der_decode(:RSAPublicKey, der) do
      rsa_public_key(modulus: modulus, publicExponent: exponent) = rsa
      when modulus >= 1 <<< 3071 and exponent >= 65_537 ->
        {:ok, rsa,
         spki(algorithm: key_algorithm(algorithm: @rsa, parameters: :NULL), subjectPublicKey: rsa)}

      _weak ->
        {:error, :invalid_delivery_csr}
    end
  end

  defp decode_key(_key, _family), do: {:error, :invalid_delivery_csr}

  defp issuer_material(opts) do
    with {:ok, reference} <- Keyword.fetch(opts, :issuer_reference),
         {:ok, %{material: material}} <-
           Resolver.resolve(
             %{
               reference: reference,
               backend_key: reference,
               registry_version: 1,
               purpose: "provider_delivery_issuer"
             },
             Keyword.put(opts, :allowed_material_keys, [:certificate_pem, :private_key_pem])
           ),
         [{:Certificate, ca, :not_encrypted}] <- :public_key.pem_decode(material.certificate_pem),
         [key] <- :public_key.pem_decode(material.private_key_pem) do
      {:ok, ca, :public_key.pem_entry_decode(key)}
    end
  end

  defp issuer_signature(key) when elem(key, 0) == :ECPrivateKey,
    do: {:ok, signature_algorithm(algorithm: {1, 2, 840, 10_045, 4, 3, 2})}

  defp issuer_signature(key) when elem(key, 0) == :RSAPrivateKey,
    do: {:ok, signature_algorithm(algorithm: {1, 2, 840, 113_549, 1, 1, 11}, parameters: :NULL)}

  defp issuer_signature(_key), do: {:error, :delivery_issuer_unavailable}

  defp pkix_time(%DateTime{year: year} = time) when year < 2050,
    do: {:utcTime, time |> Calendar.strftime("%y%m%d%H%M%SZ") |> String.to_charlist()}

  defp pkix_time(time),
    do: {:generalTime, time |> Calendar.strftime("%Y%m%d%H%M%SZ") |> String.to_charlist()}

  defp pem(der), do: :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
end
