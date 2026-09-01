defmodule CadenceWeb.FrontendReleaseCatalogTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.FrontendReleaseCatalog

  @fixture Path.expand("../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @opts [now: "2026-08-30T18:30:00Z", allowed_origins: ["https://cdn.example.com"]]
  @envelope_required_string_fields [
    {"schema", :invalid_type},
    {"keyId", :invalid_type},
    {"algorithm", :invalid_type},
    {"signingRole", :invalid_role},
    {"payloadEncoding", :invalid_type},
    {"payload", :invalid_base64},
    {"signature", :invalid_base64}
  ]

  test "shared RFC8032 fixtures verify exactly in OTP and preserve exact payload bytes" do
    unicode = @corpus["unicodeCanonical"]
    unicode_canonical = canonical(%{"value" => unicode["value"]})
    assert unicode_canonical == unicode["canonical"]
    assert byte_size(unicode_canonical) == unicode["bytes"]

    release = @corpus["release"]
    catalog = @corpus["catalog"]

    assert {:ok, release_result} =
             FrontendReleaseCatalog.verify_release(release["envelope"], @corpus["keys"], @opts)

    assert release_result.release["releaseId"] ==
             "sha256:1c1bd2f62ada2a7e6b9ab35f4e0f36d3bb4c46995221a1c5d7eb8f7f9f6a4470"

    assert release_result.payload_bytes == release["payload"]
    assert release_result.digest == sha256(release["payload"])

    assert sign_fixture(release["payload"], "fixture-release-key", "release", @release_seed)[
             "signature"
           ] ==
             release["envelope"]["signature"]

    assert sign_fixture(catalog["payload"], "fixture-promotion-key", "promotion", @promotion_seed)[
             "signature"
           ] ==
             catalog["envelope"]["signature"]
  end

  test "the bounded v2 adversarial corpus is consumed in order with exact outcomes" do
    assert @corpus["version"] == 2
    assert @corpus["corpusSchema"] == "cadence.frontend-release-contract.adversarial.v2"
    assert @corpus["caseCount"] == length(@corpus["cases"])
    assert length(@corpus["cases"]) <= @corpus["maxCases"]
    ids = Enum.map(@corpus["cases"], & &1["id"])
    assert length(ids) == length(Enum.uniq(ids))

    assert {:ok, baseline} =
             FrontendReleaseCatalog.verify_catalog(
               @corpus["catalog"]["envelope"],
               @corpus["keys"],
               @opts
             )

    Enum.each(@corpus["cases"], fn corpus_case ->
      actual = run_corpus_case(corpus_case, baseline.accepted_state)
      expected = corpus_case["expected"]

      assert corpus_projection(actual, expected) == expected,
             "#{corpus_case["id"]}: expected #{inspect(expected)}, got #{inspect(actual)}"
    end)
  end

  test "keeps every required envelope string field in the bounded type inventory" do
    Enum.each(@envelope_required_string_fields, fn {field, code} ->
      path = "$." <> field
      envelope = Map.put(@corpus["release"]["envelope"], field, 1)

      assert {:error, %{code: ^code, path: ^path}} =
               FrontendReleaseCatalog.verify(envelope, @corpus["keys"], @opts)
    end)
  end

  test "catalog verifies nested release envelopes and exposes an accepted-state digest" do
    assert {:ok, result} =
             FrontendReleaseCatalog.verify_catalog(
               @corpus["catalog"]["envelope"],
               @corpus["keys"],
               @opts
             )

    assert result.signing_role == "promotion"
    assert result.digest == sha256(@corpus["catalog"]["payload"])
    assert [%{current: current, fallback: fallback}] = result.entries

    assert current["releaseId"] ==
             "sha256:8afe661d6cba541a26667f12b18bbc0ef527fe64181db127270dc54030c4acfa"

    assert fallback["releaseId"] ==
             "sha256:1c1bd2f62ada2a7e6b9ab35f4e0f36d3bb4c46995221a1c5d7eb8f7f9f6a4470"

    assert result.accepted_state["digest"] == result.digest
  end

  test "catalog admission is time-aware, replay-safe, monotonic, and supports rollback swaps" do
    catalog = @corpus["catalog"]["envelope"]

    assert {:ok, accepted} =
             FrontendReleaseCatalog.verify_catalog(catalog, @corpus["keys"], @opts)

    assert {:ok, identical} =
             FrontendReleaseCatalog.verify_catalog(
               catalog,
               @corpus["keys"],
               Keyword.merge(@opts,
                 now: "2026-08-30T19:00:00Z",
                 accepted_state: accepted.accepted_state
               )
             )

    assert identical.acceptance == :identical

    assert {:ok, _} =
             FrontendReleaseCatalog.verify_catalog(
               @corpus["rolloutCatalog"]["envelope"],
               @corpus["keys"],
               Keyword.merge(@opts,
                 now: "2026-08-30T19:00:00Z",
                 accepted_state: accepted.accepted_state
               )
             )

    assert {:ok, rollback} =
             FrontendReleaseCatalog.verify_catalog(
               @corpus["rollbackCatalog"]["envelope"],
               @corpus["keys"],
               Keyword.merge(@opts,
                 now: "2026-08-30T19:00:00Z",
                 accepted_state: accepted.accepted_state
               )
             )

    assert rollback.entries |> hd() |> Map.fetch!(:current) |> Map.fetch!("releaseId") ==
             accepted.entries |> hd() |> Map.fetch!(:fallback) |> Map.fetch!("releaseId")

    lower = mutate_catalog(@corpus["catalog"]["payload"], &Map.put(&1, "sequence", 9))
    assert_error(:lower_sequence, lower, accepted.accepted_state)

    fork =
      mutate_catalog(
        @corpus["catalog"]["payload"],
        &Map.put(&1, "expiresAt", "2026-08-31T17:00:00Z")
      )

    assert_error(:same_sequence_fork, fork, accepted.accepted_state)

    non_monotonic = mutate_catalog(@corpus["catalog"]["payload"], &Map.put(&1, "sequence", 11))
    assert_error(:non_monotonic_publication, non_monotonic, accepted.accepted_state)

    assert_catalog_error(
      :not_yet_published,
      catalog,
      Keyword.put(@opts, :now, "2026-08-30T17:59:59Z")
    )

    assert_catalog_error(
      :expired_catalog,
      catalog,
      Keyword.put(@opts, :now, "2026-08-31T18:00:00Z")
    )
  end

  test "a promotion key cannot synthesize release metadata" do
    release = Jason.decode!(@corpus["release"]["payload"])

    forged =
      sign_fixture(
        @corpus["release"]["payload"],
        "fixture-promotion-key",
        "release",
        @promotion_seed
      )

    entry = catalog_entry(release, nil) |> Map.put("current", forged)
    payload = catalog_payload([entry], 20, "2026-08-30T19:00:00Z")

    assert {:error, %{code: :role_not_allowed}} =
             FrontendReleaseCatalog.verify_catalog(
               catalog_envelope(payload),
               @corpus["keys"],
               @opts
             )
  end

  test "catalog identity includes every version and enforces catalog-wide names" do
    release = Jason.decode!(@corpus["release"]["payload"])

    wrong_identity =
      Map.put(@corpus["identity"], "application", %{"id" => "telemetry_decom", "version" => 2})

    wrong_entry = %{"identity" => wrong_identity, "current" => @corpus["release"]["envelope"]}
    wrong_catalog = catalog_payload([wrong_entry], 21, "2026-08-30T19:00:00Z")

    assert {:error, %{code: :identity_mismatch}} =
             FrontendReleaseCatalog.verify_catalog(
               catalog_envelope(wrong_catalog),
               @corpus["keys"],
               @opts
             )

    second =
      release
      |> put_in(["application", "id"], "telemetry_z")
      |> with_release_id()

    duplicate_remote =
      catalog_payload(
        [catalog_entry(release, nil), catalog_entry(second, nil)],
        22,
        "2026-08-30T19:00:00Z"
      )

    assert {:error, %{code: :duplicate_remote_or_exposed_module}} =
             FrontendReleaseCatalog.verify_catalog(
               catalog_envelope(duplicate_remote),
               @corpus["keys"],
               @opts
             )

    duplicate_exposed =
      second
      |> Map.put("remoteName", "cadence_telemetry_other")
      |> with_release_id()
      |> then(
        &catalog_payload(
          [catalog_entry(release, nil), catalog_entry(&1, nil)],
          23,
          "2026-08-30T19:00:00Z"
        )
      )

    assert {:error, %{code: :duplicate_remote_or_exposed_module}} =
             FrontendReleaseCatalog.verify_catalog(
               catalog_envelope(duplicate_exposed),
               @corpus["keys"],
               @opts
             )
  end

  test "canonical JSON, array order, paths, URLs, compatibility, and key trust are closed-world" do
    release = Jason.decode!(@corpus["release"]["payload"])

    reversed = Map.put(release, "artifacts", Enum.reverse(release["artifacts"]))
    assert_error(:unsorted_artifacts, release_envelope(with_release_id(reversed)), @opts)

    mutable =
      release
      |> with_release_id()
      |> Map.put(
        "artifactBaseUrl",
        "https://cdn.example.com/releases/telemetry_decom/current/artifacts/"
      )

    assert_error(:invalid_base_url, release_envelope(mutable), @opts)

    circular =
      Map.put(
        release,
        "artifactBaseUrl",
        "https://cdn.example.com/releases/telemetry_decom/sha256:0000000000000000000000000000000000000000000000000000000000000000/artifacts/"
      )

    assert_error(:invalid_base_url, release_envelope(circular), @opts)

    mismatch =
      put_in(release, ["hostCompatibility", "compatibility", "cadenceThemeContract"], 2)
      |> with_release_id()

    assert_error(:invalid_value, release_envelope(mismatch), @opts)

    noncanonical =
      "{\"schema\":\"cadence.first-party-frontend-release.v1\",\"schema\":\"cadence.first-party-frontend-release.v1\"}"

    assert_error(
      :duplicate_json_key,
      sign_fixture(noncanonical, "fixture-release-key", "release", @release_seed),
      @opts
    )

    unicode_boundary =
      put_in(release, ["provenance", "buildId"], String.duplicate("é", 256)) |> with_release_id()

    assert {:ok, _} =
             FrontendReleaseCatalog.verify_release(
               release_envelope(unicode_boundary),
               @corpus["keys"],
               @opts
             )

    unicode_over =
      put_in(release, ["provenance", "buildId"], String.duplicate("é", 257)) |> with_release_id()

    assert_error(:unbounded_value, release_envelope(unicode_over), @opts)

    assert {:error, %{code: :invalid_key_record}} =
             FrontendReleaseCatalog.verify_release(
               @corpus["release"]["envelope"],
               %{"wrong" => @corpus["keys"] |> hd()},
               @opts
             )

    assert_error(
      :invalid_base_url,
      @corpus["release"]["envelope"],
      Keyword.delete(@opts, :allowed_origins)
    )

    refute function_exported?(FrontendReleaseCatalog, :sign, 4)
  end

  test "large decoded payload and malformed untrusted values return deterministic errors" do
    large = build_large_release()
    assert byte_size(large.payload) == @corpus["largeRelease"]["payloadBytes"]

    assert {:ok, result} =
             FrontendReleaseCatalog.verify_release(large.envelope, @corpus["keys"], @opts)

    assert result.release["releaseId"] == @corpus["largeRelease"]["releaseId"]

    assert_error(
      :invalid_base64,
      Map.put(@corpus["release"]["envelope"], "signature", "A"),
      @opts
    )

    assert {:error, %{code: :invalid_key_record}} =
             FrontendReleaseCatalog.verify_release(
               @corpus["release"]["envelope"],
               [%{"keyId" => "broken"}],
               @opts
             )

    assert {:error, %{code: :incomplete_required_fields}} =
             FrontendReleaseCatalog.verify_release(%{"schema" => nil}, @corpus["keys"], @opts)
  end

  test "verifier boundaries preserve explicit malformed errors and propagate misuse" do
    malformed_tree = Map.put(@corpus["release"]["envelope"], "untrusted", [1 | :tail])

    assert {:error, %{code: :invalid_type, path: "$.untrusted"}} =
             FrontendReleaseCatalog.verify_release(malformed_tree, @corpus["keys"], @opts)

    assert {:error, %{code: :invalid_key_record, path: "$.keys"}} =
             FrontendReleaseCatalog.verify_release(
               @corpus["release"]["envelope"],
               [hd(@corpus["keys"]) | :tail],
               @opts
             )

    improper_roles = Map.put(hd(@corpus["keys"]), "allowedRoles", ["release" | :tail])

    assert {:error, %{code: :invalid_key_record, path: "$.keys[0].allowedRoles"}} =
             FrontendReleaseCatalog.verify_release(
               @corpus["release"]["envelope"],
               [improper_roles | tl(@corpus["keys"])],
               @opts
             )

    assert {:error, %{code: :invalid_base_url, path: "$.allowedOrigins"}} =
             FrontendReleaseCatalog.verify_release(
               @corpus["release"]["envelope"],
               @corpus["keys"],
               Keyword.put(@opts, :allowed_origins, ["https://cdn.example.com" | :tail])
             )

    assert_raise FunctionClauseError, fn ->
      FrontendReleaseCatalog.verify_release(@corpus["release"]["envelope"], @corpus["keys"], nil)
    end

    assert_raise FunctionClauseError, fn ->
      FrontendReleaseCatalog.verify_catalog(@corpus["catalog"]["envelope"], @corpus["keys"], nil)
    end
  end

  defp build_large_release do
    release = Jason.decode!(@corpus["release"]["payload"])

    artifacts =
      Enum.map(0..(@corpus["largeRelease"]["artifactCount"] - 1), fn index ->
        %{
          "path" =>
            "assets/" <>
              String.pad_leading(Integer.to_string(index), 4, "0") <>
              "-" <> String.duplicate("x", @corpus["largeRelease"]["pathPadding"]) <> ".js",
          "sha256" => String.duplicate("e", 64),
          "size" => 5000,
          "mediaType" => "application/javascript"
        }
      end)

    release
    |> Map.put("manifest", hd(artifacts))
    |> Map.put("artifacts", artifacts)
    |> put_in(["provenance", "buildId"], "fixture-build-4")
    |> put_in(["releasedAt"], "2026-08-30T17:45:00Z")
    |> with_release_id()
    |> then(fn value ->
      %{
        payload: canonical(value),
        envelope: sign_fixture(canonical(value), "fixture-release-key", "release", @release_seed)
      }
    end)
  end

  defp mutate_catalog(payload, fun),
    do: payload |> Jason.decode!() |> fun.() |> then(&catalog_envelope(&1))

  defp catalog_payload(entries, sequence, published_at) do
    %{
      "schema" => "cadence.first-party-frontend-release-catalog.v1",
      "sequence" => sequence,
      "publishedAt" => published_at,
      "expiresAt" => "2026-08-31T18:00:00Z",
      "entries" => entries
    }
    |> canonical()
  end

  defp catalog_entry(release, fallback) do
    entry = %{
      "identity" => %{
        "application" => release["application"],
        "package" => release["package"],
        "surface" => release["surface"]
      },
      "current" => release_envelope(release)
    }

    if fallback, do: Map.put(entry, "fallback", fallback), else: entry
  end

  defp release_envelope(release),
    do: sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)

  defp catalog_envelope(payload) when is_binary(payload),
    do: sign_fixture(payload, "fixture-promotion-key", "promotion", @promotion_seed)

  defp catalog_envelope(payload), do: catalog_envelope(canonical(payload))

  defp with_release_id(release), do: with_release_id(release, false)

  defp with_release_id(release, preserve_artifact_base_url) do
    logical = release |> Map.delete("releaseId") |> Map.delete("artifactBaseUrl")
    id = sha256(canonical(logical))
    updated = Map.put(release, "releaseId", id)

    if preserve_artifact_base_url do
      updated
    else
      Map.put(
        updated,
        "artifactBaseUrl",
        "https://cdn.example.com/releases/" <>
          release["application"]["id"] <> "/" <> id <> "/artifacts/"
      )
    end
  end

  defp sign_fixture(payload, key_id, role, seed_hex) do
    private_key = Base.decode16!(seed_hex, case: :lower)
    signature = :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])

    %{
      "schema" => "cadence.signed-frontend-document.v1",
      "keyId" => key_id,
      "algorithm" => "ed25519",
      "signingRole" => role,
      "payloadEncoding" => "base64url-json",
      "payload" => Base.url_encode64(payload, padding: false),
      "signature" => Base.url_encode64(signature, padding: false)
    }
  end

  defp assert_error(code, document, opts) when is_list(opts) do
    assert {:error, %{code: ^code}} =
             FrontendReleaseCatalog.verify_release(document, @corpus["keys"], opts)
  end

  defp assert_error(code, envelope, state_or_opts) when is_map(state_or_opts) do
    assert {:error, %{code: ^code}} =
             FrontendReleaseCatalog.verify_catalog(
               envelope,
               @corpus["keys"],
               @opts ++ [accepted_state: state_or_opts]
             )
  end

  defp assert_catalog_error(code, envelope, opts) do
    assert {:error, %{code: ^code}} =
             FrontendReleaseCatalog.verify_catalog(envelope, @corpus["keys"], opts)
  end

  defp run_corpus_case(corpus_case, baseline_state) do
    opts =
      @opts
      |> Keyword.put(:now, Map.get(corpus_case, "now", @corpus["now"]))
      |> Keyword.put(
        :allowed_origins,
        Map.get(corpus_case, "allowedOrigins", [@corpus["origin"]])
      )
      |> put_corpus_state(corpus_case, baseline_state)

    document = corpus_document(corpus_case)
    keys = corpus_keys(corpus_case)

    case corpus_case["operation"] do
      "document" -> FrontendReleaseCatalog.verify(document, keys, opts)
      "release" -> FrontendReleaseCatalog.verify_release(document, keys, opts)
      "catalog" -> FrontendReleaseCatalog.verify_catalog(document, keys, opts)
    end
  end

  defp put_corpus_state(opts, %{"acceptedState" => "catalog"} = corpus_case, baseline_state) do
    state =
      case Map.get(corpus_case, "acceptedStatePublishedAt") do
        nil -> baseline_state
        published_at -> Map.put(baseline_state, "publishedAt", published_at)
      end

    Keyword.put(opts, :accepted_state, state)
  end

  defp put_corpus_state(opts, _corpus_case, _baseline_state), do: opts

  defp corpus_document(%{"source" => "release"} = corpus_case) do
    @corpus["release"]["envelope"]
    |> put_corpus_payload(corpus_case)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "catalog"} = corpus_case) do
    @corpus["catalog"]["envelope"]
    |> put_corpus_payload(corpus_case)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "rolloutCatalog"} = corpus_case) do
    @corpus["rolloutCatalog"]["envelope"]
    |> put_corpus_payload(corpus_case)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "rollbackCatalog"} = corpus_case) do
    @corpus["rollbackCatalog"]["envelope"]
    |> put_corpus_payload(corpus_case)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "release_payload"} = corpus_case) do
    release =
      @corpus["release"]["payload"]
      |> Jason.decode!()
      |> apply_operations(Map.get(corpus_case, "payloadPatches", []))
      |> maybe_recompute_release_id(corpus_case)

    sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "catalog_payload"} = corpus_case) do
    payload =
      @corpus["catalog"]["payload"]
      |> Jason.decode!()
      |> apply_operations(Map.get(corpus_case, "payloadPatches", []))

    sign_fixture(canonical(payload), "fixture-promotion-key", "promotion", @promotion_seed)
    |> apply_operations(Map.get(corpus_case, "envelopePatches", []))
  end

  defp corpus_document(%{"source" => "generated", "generated" => generated}) do
    generated_document(generated)
  end

  defp put_corpus_payload(envelope, %{"payloadText" => payload}) do
    Map.put(envelope, "payload", Base.url_encode64(payload, padding: false))
  end

  defp put_corpus_payload(envelope, %{"payloadTextRef" => "release-space"}) do
    Map.put(
      envelope,
      "payload",
      Base.url_encode64(@corpus["release"]["payload"] <> " ", padding: false)
    )
  end

  defp put_corpus_payload(envelope, %{"payloadBytesBase64" => bytes}) do
    Map.put(envelope, "payload", bytes)
  end

  defp put_corpus_payload(envelope, _corpus_case), do: envelope

  defp corpus_keys(%{"keys" => "empty"}), do: []

  defp corpus_keys(%{"keys" => "wrong-trust-map"}) do
    %{"wrong" => hd(@corpus["keys"])}
  end

  defp corpus_keys(%{"keys" => "duplicate"}) do
    @corpus["keys"] ++ [Enum.at(@corpus["keys"], 1)]
  end

  defp corpus_keys(corpus_case) do
    @corpus["keys"]
    |> apply_operations(Map.get(corpus_case, "keyPatches", []))
  end

  defp maybe_recompute_release_id(release, %{"recomputeReleaseId" => true} = corpus_case),
    do: with_release_id(release, Map.get(corpus_case, "preserveArtifactBaseUrl", false))

  defp maybe_recompute_release_id(release, _corpus_case), do: release

  defp generated_document("depth") do
    release = @corpus["release"]["payload"] |> Jason.decode!() |> Map.put("x", nested_map(16))
    sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)
  end

  defp generated_document("members") do
    release =
      Enum.reduce(0..50, Jason.decode!(@corpus["release"]["payload"]), fn index, release ->
        Map.put(release, "x#{index}", 0)
      end)

    sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)
  end

  defp generated_document("duplicate-names") do
    release = Jason.decode!(@corpus["release"]["payload"])
    second = release |> put_in(["application", "id"], "telemetry_z") |> with_release_id()

    catalog_payload(
      [catalog_entry(release, nil), catalog_entry(second, nil)],
      20,
      "2026-08-30T19:00:00Z"
    )
    |> catalog_envelope()
  end

  defp generated_document("duplicate-identity") do
    release = Jason.decode!(@corpus["release"]["payload"])

    catalog_payload(
      [catalog_entry(release, nil), catalog_entry(release, nil)],
      20,
      "2026-08-30T19:00:00Z"
    )
    |> catalog_envelope()
  end

  defp nested_map(0), do: %{}
  defp nested_map(levels), do: %{"x" => nested_map(levels - 1)}

  defp apply_operations(value, operations) do
    Enum.reduce(operations, value, fn operation, current ->
      path = pointer_path(operation["path"])
      operation_value = resolve_case_value(Map.get(operation, "value"))

      case operation["op"] do
        "add" -> put_pointer(current, path, operation_value)
        "replace" -> put_pointer(current, path, operation_value)
        "remove" -> delete_pointer(current, path)
      end
    end)
  end

  defp pointer_path(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&String.replace(&1, "~1", "/"))
    |> Enum.map(&String.replace(&1, "~0", "~"))
  end

  defp put_pointer(value, [key], replacement) when is_map(value),
    do: Map.put(value, key, replacement)

  defp put_pointer(value, [index], replacement) when is_list(value),
    do: List.replace_at(value, String.to_integer(index), replacement)

  defp put_pointer(value, [key | rest], replacement) when is_map(value),
    do: Map.put(value, key, put_pointer(Map.fetch!(value, key), rest, replacement))

  defp put_pointer(value, [index | rest], replacement) when is_list(value),
    do:
      List.replace_at(
        value,
        String.to_integer(index),
        put_pointer(Enum.at(value, String.to_integer(index)), rest, replacement)
      )

  defp delete_pointer(value, [key]) when is_map(value), do: Map.delete(value, key)

  defp delete_pointer(value, [index]) when is_list(value),
    do: List.delete_at(value, String.to_integer(index))

  defp delete_pointer(value, [key | rest]) when is_map(value),
    do: Map.put(value, key, delete_pointer(Map.fetch!(value, key), rest))

  defp delete_pointer(value, [index | rest]) when is_list(value),
    do:
      List.replace_at(
        value,
        String.to_integer(index),
        delete_pointer(Enum.at(value, String.to_integer(index)), rest)
      )

  defp resolve_case_value(%{"$repeat" => %{"value" => value, "count" => count}}),
    do: String.duplicate(value, count)

  defp resolve_case_value(%{"$artifacts" => count}), do: generated_artifacts(count)
  defp resolve_case_value(value), do: value

  defp generated_artifacts(count) do
    Enum.map(0..(count - 1), fn index ->
      %{
        "path" => "assets/" <> String.pad_leading(Integer.to_string(index), 4, "0") <> ".js",
        "sha256" => String.duplicate("e", 64),
        "size" => 5000,
        "mediaType" => "application/javascript"
      }
    end)
  end

  defp corpus_projection({:ok, result}, expected) do
    value = %{"ok" => true}

    if Map.has_key?(expected, "acceptance"),
      do: Map.put(value, "acceptance", Atom.to_string(result.acceptance)),
      else: value
  end

  defp corpus_projection({:error, %{code: code, path: path}}, _expected),
    do: %{"ok" => false, "error" => %{"code" => Atom.to_string(code), "path" => path}}

  defp sha256(value),
    do: "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))

  defp canonical(value) when is_map(value),
    do:
      "{" <>
        (value
         |> Map.keys()
         |> Enum.sort()
         |> Enum.map_join(",", fn key ->
           Jason.encode!(key) <> ":" <> canonical(Map.fetch!(value, key))
         end)) <>
        "}"

  defp canonical(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical/1) <> "]"

  defp canonical(value) when is_binary(value), do: Jason.encode!(value)
  defp canonical(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical(true), do: "true"
  defp canonical(false), do: "false"
  defp canonical(nil), do: "null"
end
