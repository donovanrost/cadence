defmodule Cadence.GroundNetworks.ProviderDeliveryCredentialIssuerTest do
  use ExUnit.Case, async: true

  alias Cadence.DeliveryCredentialFixtures, as: Fixtures
  alias Cadence.GroundNetworks.ProviderDeliveryCredentials.Issuer

  test "issues a bounded client-only certificate from the CSR public key and the server identity" do
    opts = Fixtures.issuer_options()
    assert {:ok, key} = Issuer.public_key(Fixtures.csr())
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    assert {:ok, issued} = Issuer.issue(key, "delivery_credential_test", now, opts)
    assert issued.expires_at == DateTime.add(now, 30, :day)
    [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(issued.certificate_pem)
    [{:Certificate, ca, :not_encrypted}] = :public_key.pem_decode(issued.issuer_certificate_pem)
    assert {:ok, _chain} = :public_key.pkix_path_validation(ca, [der], [])
    assert issued.fingerprint == Base.encode16(:crypto.hash(:sha256, der), case: :lower)
    {:OTPCertificate, tbs, _, _} = :public_key.pkix_decode_cert(der, :otp)

    assert elem(tbs, 6) ==
             {:rdnSequence,
              [
                [
                  {:AttributeTypeAndValue, {2, 5, 4, 3},
                   {:utf8String, "delivery_credential_test"}}
                ]
              ]}

    assert elem(tbs, 7) == key

    assert elem(tbs, 10) == [
             {:Extension, {2, 5, 29, 19}, true, {:BasicConstraints, false, :asn1_NOVALUE}},
             {:Extension, {2, 5, 29, 15}, true, [:digitalSignature]},
             {:Extension, {2, 5, 29, 37}, false, [{1, 3, 6, 1, 5, 5, 7, 3, 2}]}
           ]
  end

  test "enforces proof of possession and the key floor" do
    assert {:ok, _key} = Issuer.public_key(Fixtures.csr(key: {:rsa, 3072}))

    for csr <- [
          Fixtures.csr(key: {:rsa, 2048}),
          Fixtures.csr(key: :p224),
          Fixtures.csr(wrong_signature: true),
          "not a CSR"
        ] do
      assert Issuer.public_key(csr) == {:error, :invalid_delivery_csr}
    end
  end
end
