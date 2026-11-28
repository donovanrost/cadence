defmodule Cadence.DeliveryCredentialFixtures do
  @moduledoc false

  require Record

  Record.defrecordp(
    :ec_private_key,
    :ECPrivateKey,
    Record.extract(:ECPrivateKey, from_lib: "public_key/include/public_key.hrl")
  )

  @p256 {1, 2, 840, 10_045, 3, 1, 7}
  @p224 {1, 3, 132, 0, 33}
  @ec {1, 2, 840, 10_045, 2, 1}
  @ecdsa_sha256 {1, 2, 840, 10_045, 4, 3, 2}
  @rsa {1, 2, 840, 113_549, 1, 1, 1}
  @rsa_sha256 {1, 2, 840, 113_549, 1, 1, 11}

  def issuer_options(opts \\ []) do
    root_options = Keyword.put(opts, :key, {:namedCurve, @p256})

    %{cert: cert, key: key} =
      :public_key.pkix_test_root_cert(~c"Test delivery issuer", root_options)

    [
      issuer_reference: "test-delivery-issuer",
      secret_backend: fn %{reference: "test-delivery-issuer"} ->
        {:ok,
         %{
           material: %{
             certificate_pem: pem(:Certificate, cert),
             private_key_pem: pem(:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, key))
           }
         }}
      end
    ]
  end

  def csr(opts \\ []) do
    {algorithm, parameters, public, key, signature_algorithm, signature_parameters} =
      keypair(Keyword.get(opts, :key, :p256))

    # Deliberately request a CA leaf and an identity of the caller's choosing. Neither is granted.
    extensions = [
      {:Extension, {2, 5, 29, 19}, true,
       :public_key.der_encode(:BasicConstraints, {:BasicConstraints, true, 0})}
    ]

    info =
      {:CertificationRequestInfo, :v1,
       {:rdnSequence,
        [[{:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, "Other identity"}}]]},
       {:CertificationRequestInfo_subjectPKInfo,
        {:CertificationRequestInfo_subjectPKInfo_algorithm, algorithm, parameters}, public},
       [
         {:CertificationRequestInfo_attributes_SETOF, {1, 2, 840, 113_549, 1, 9, 14},
          [{:asn1_OPENTYPE, :public_key.der_encode(:Extensions, extensions)}]}
       ]}

    signature =
      :public_key.sign(:public_key.der_encode(:CertificationRequestInfo, info), :sha256, key)

    signature = if Keyword.get(opts, :wrong_signature, false), do: <<0, 0>>, else: signature

    request =
      {:CertificationRequest, info,
       {:CertificationRequest_signatureAlgorithm, signature_algorithm, signature_parameters},
       signature}

    pem(:CertificationRequest, :public_key.der_encode(:CertificationRequest, request))
  end

  defp keypair({:rsa, bits}) do
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} =
      key = :public_key.generate_key({:rsa, bits, 65_537})

    public = :public_key.der_encode(:RSAPublicKey, {:RSAPublicKey, modulus, exponent})
    {@rsa, {:asn1_OPENTYPE, <<5, 0>>}, public, key, @rsa_sha256, {:asn1_OPENTYPE, <<5, 0>>}}
  end

  defp keypair(curve) do
    curve = if curve == :p224, do: @p224, else: @p256
    key = :public_key.generate_key({:namedCurve, curve})
    public = ec_private_key(key, :publicKey)
    parameters = {:asn1_OPENTYPE, :public_key.der_encode(:EcpkParameters, {:namedCurve, curve})}
    {@ec, parameters, public, key, @ecdsa_sha256, :asn1_NOVALUE}
  end

  defp pem(type, der), do: :public_key.pem_encode([{type, der, :not_encrypted}])
end
