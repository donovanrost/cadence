defmodule Cadence.Control.Providers.EphemerisUploadsTest do
  @moduledoc """
  Ephemeris upload (#968): a new current element set stages one upload job for its batch; a run
  uploads it to each bound provider that accepts uploads, records lookup providers by whether
  the set carries a NORAD id, and retries a failed upload with backoff.
  """
  use Cadence.DataCase, async: false

  import Cadence.EphemerisUploadFixtures

  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.GroundNetworks.{EphemerisStates, ProviderCapabilities}
  alias Cadence.Jobs

  @now ~U[2026-11-28 12:00:00.000000Z]

  setup do
    setup_ephemeris()
  end

  describe "capability" do
    test "a provider declares upload or lookup; one that doesn't is read as lookup" do
      for {document, source} <- [
            {%{"orbit" => %{"source" => "accepts_ephemeris_upload"}}, :accepts_ephemeris_upload},
            {%{"orbit" => %{"source" => "looks_up_by_norad_id"}}, :looks_up_by_norad_id},
            {%{}, :looks_up_by_norad_id}
          ] do
        {:ok, capabilities} =
          ProviderCapabilities.from_external(Map.merge(capabilities(), document))

        assert ProviderCapabilities.orbit_source(capabilities) == source
      end

      assert {:error, {:malformed_provider_response, "source"}} =
               ProviderCapabilities.from_external(
                 Map.put(capabilities(), "orbit", %{"source" => "telepathy"})
               )
    end
  end

  test "a new current element set stages one upload job for the batch", c do
    {:ok, _results} = submit(c, norad: 25_544)

    assert [%{payload: %{"spacecraft_ids" => [sc]}}] =
             Jobs.list_open_jobs(:ephemeris_upload, c.mission)

    assert sc == c.sc
  end

  test "an upload provider gets the current set as an OMM once, then holds it", c do
    upload_provider!(c)
    {:ok, [{:created, set}]} = submit(c, norad: 25_544)

    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert_received {:uploaded, "SIM-001", ephemeris}
    assert ephemeris["content_sha256"] == set.content_sha256
    assert ephemeris["epoch"] == DateTime.to_iso8601(set.epoch)

    assert %{"NORAD_CAT_ID" => 25_544, "MEAN_MOTION" => 15.2, "REF_FRAME" => "TEME"} =
             ephemeris["omm"]

    assert %{status: "uploaded", element_set_id: id} = state(c)
    assert id == set.element_set_id

    # The provider already holds that content: nothing is sent again.
    assert {:ok, %{"uploaded" => 1}} = run(c)
    refute_received {:uploaded, _ref, _ephemeris}
  end

  test "a failed upload is recorded, backs off, and the sweep retries it", c do
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    failure = {:error, :econnrefused}

    assert {:ok, %{"failed" => 1}} = run(c, upload_result: failure)

    assert %{status: "failed", attempts: 1, reason: "econnrefused", next_retry_at: first} =
             state(c)

    assert first == EphemerisUploads.next_retry_at(@now, 1)

    assert {:ok, %{"failed" => 1}} = run(c, upload_result: failure)
    assert %{attempts: 2, next_retry_at: second} = state(c)
    assert DateTime.compare(second, EphemerisUploads.next_retry_at(@now, 2)) == :eq

    clear_jobs!(c)
    assert EphemerisUploads.retry_due(DateTime.add(@now, -60)) == 0
    assert EphemerisUploads.retry_due(DateTime.add(second, 1)) == 1

    assert [%{payload: %{"spacecraft_ids" => [_sc]}}] =
             Jobs.list_open_jobs(:ephemeris_upload, c.mission)

    # Leased: the next sweep doesn't stage it again before the run records its outcome.
    assert EphemerisUploads.retry_due(DateTime.add(second, 2)) == 0

    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert %{status: "uploaded", attempts: 0, next_retry_at: nil} = state(c)
  end

  test "a lookup provider needs a NORAD id, and its absence is recorded", c do
    {:ok, _results} = submit(c, norad: nil)

    assert {:ok, %{"norad_id_missing" => 1}} = run(c)
    refute_received {:uploaded, _ref, _ephemeris}
    assert %{status: "norad_id_missing"} = state(c)

    {:ok, _results} = submit(c, norad: 25_544, hours_ago: 0)
    assert {:ok, %{"lookup" => 1}} = run(c)

    assert %{c.provider.provider_id => %{"lookup" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)
  end

  test "a run given pairs attempts only those", c do
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)

    assert {:ok, summary} = run(c, pairs: [{c.sc, "some-other-provider"}])
    assert summary == %{}
    refute_received {:uploaded, _ref, _ephemeris}

    assert {:ok, %{"uploaded" => 1}} = run(c, pairs: [{c.sc, c.provider.provider_id}])
  end

  test "a spacecraft with no element set is left alone", c do
    assert {:ok, summary} = run(c)
    assert summary == %{}
  end
end
