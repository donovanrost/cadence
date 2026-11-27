defmodule Cadence.Control.Providers.EphemerisReconcileTest do
  @moduledoc """
  The ephemeris reconcile and buckets (#968): pairs follow the provider version the transport
  pins and the current provider-side ref; a provider newly able to take uploads, or a changed
  ref, gets the unchanged set from the reconcile; the reconcile's limit bounds pairs.
  """
  use Cadence.DataCase, async: false

  import Cadence.EphemerisUploadFixtures
  import Ecto.Query

  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.GroundNetworks.EphemerisStates
  alias Cadence.Jobs
  alias Cadence.Repo

  setup do
    setup_ephemeris()
  end

  test "a provider newly able to take uploads gets the unchanged current set from the reconcile",
       c do
    # The set went current while the provider only looked orbits up; nothing was uploaded.
    {:ok, [{:created, set}]} = submit(c, norad: 25_544)
    clear_jobs!(c)

    assert %{c.provider.provider_id => %{"lookup" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    # Now it accepts uploads (as a newly bound upload provider would): the pair is pending.
    upload_provider!(c)

    assert %{c.provider.provider_id => %{"pending" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    assert EphemerisUploads.reconcile() == 1

    assert [%{payload: %{"spacecraft_ids" => [sc]}}] =
             Jobs.list_open_jobs(:ephemeris_upload, c.mission)

    assert sc == c.sc

    # While that job is open, the reconcile stages nothing more for the mission.
    assert EphemerisUploads.reconcile() == 0

    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert_received {:uploaded, "SIM-001", %{"content_sha256" => sha}}
    assert sha == set.content_sha256
    clear_jobs!(c)

    # Uploaded: the next reconcile doesn't stage it again.
    assert %{c.provider.provider_id => %{"uploaded" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    assert EphemerisUploads.reconcile() == 0
    assert Jobs.list_open_jobs(:ephemeris_upload, c.mission) == []
  end

  test "the buckets: failed stays failed, a newer set is pending until sent", c do
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    {:ok, _summary} = run(c, upload_result: {:error, :econnrefused})

    assert %{c.provider.provider_id => %{"failed" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    {:ok, _summary} = run(c)
    {:ok, _results} = submit(c, norad: 25_544, hours_ago: 0)

    assert %{c.provider.provider_id => %{"pending" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)
  end

  describe "the version the transport pins decides, not the provider's latest" do
    test "v1 lookup pinned, v2 upload: lookup, and the reconcile stages nothing", c do
      {:ok, _results} = submit(c, norad: 25_544)
      clear_jobs!(c)
      new_version!(c, Map.put(capabilities(), "orbit", %{"source" => "accepts_ephemeris_upload"}))

      assert %{c.provider.provider_id => %{"lookup" => 1}} ==
               EphemerisStates.buckets(c.org, c.mission)

      assert EphemerisUploads.reconcile() == 0
      assert {:ok, %{"lookup" => 1}} = run(c)
      refute_received {:uploaded, _ref, _ephemeris}
    end

    test "v1 upload pinned, v2 lookup: uploaded, and the reconcile stages nothing", c do
      upload_provider!(c)
      {:ok, _results} = submit(c, norad: 25_544)
      clear_jobs!(c)
      assert {:ok, %{"uploaded" => 1}} = run(c)
      new_version!(c, Map.put(capabilities(), "orbit", %{"source" => "looks_up_by_norad_id"}))

      assert %{c.provider.provider_id => %{"uploaded" => 1}} ==
               EphemerisStates.buckets(c.org, c.mission)

      assert EphemerisUploads.reconcile() == 0
    end
  end

  test "a changed provider-side ref re-sends the unchanged set to the new ref", c do
    upload_provider!(c)
    {:ok, [{:created, set}]} = submit(c, norad: 25_544)
    clear_jobs!(c)
    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert_received {:uploaded, "SIM-001", _ephemeris}

    {1, _rows} =
      from(row in "mission_source_endpoints",
        where:
          row.mission_id == ^c.mission and row.spacecraft_id == ^c.sc and
            row.source_ref == "SIM-001"
      )
      |> Repo.update_all(set: [source_ref: "SIM-777"])

    assert %{c.provider.provider_id => %{"pending" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    assert EphemerisUploads.reconcile() == 1
    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert_received {:uploaded, "SIM-777", %{"content_sha256" => sha}}
    assert sha == set.content_sha256
    assert %{status: "uploaded", provider_spacecraft_ref: "SIM-777"} = state(c)
  end

  test "the reconcile's limit bounds pairs, and the job carries exactly those pairs", c do
    second = second_bound_spacecraft!(c)
    upload_provider!(c)

    for sc <- [c.sc, second] do
      {:ok, _results} = submit(%{c | sc: sc}, norad: 25_544)
    end

    clear_jobs!(c)

    assert length(EphemerisStates.pending(5_000)) == 2
    assert [{_org, _mission, _sc, provider}] = EphemerisStates.pending(1)
    assert provider == c.provider.provider_id

    assert EphemerisUploads.reconcile(1) == 1

    assert [%{payload: %{"pairs" => [[_sc, ^provider]], "spacecraft_ids" => [_one]}}] =
             Jobs.list_open_jobs(:ephemeris_upload, c.mission)
  end
end
