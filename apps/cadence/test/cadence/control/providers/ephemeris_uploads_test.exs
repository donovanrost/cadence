defmodule Cadence.Control.Providers.EphemerisUploadsTest do
  @moduledoc """
  Ephemeris upload (#968): a new current element set stages one upload job for its batch; a run
  uploads it to each bound provider that accepts uploads, records lookup providers by whether
  the set carries a NORAD id, and retries a failed upload with backoff.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ContactScheduleFixtures
  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.GroundNetworks.{ElementSets, EphemerisStates, ProviderCapabilities}
  alias Cadence.GroundNetworks.MissionProviders.ProviderRow, as: MissionProviderRow
  alias Cadence.Jobs
  alias Cadence.Repo

  @now ~U[2026-11-28 12:00:00.000000Z]
  @opts [actor: %{"actor_kind" => "user", "user_id" => "user-ephemeris"}, source: "manual"]

  defmodule UploadClient do
    @moduledoc false
    def upload_ephemeris(_context, ref, ephemeris, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:uploaded, ref, ephemeris})
      Keyword.get(opts, :upload_result, {:ok, %{"spacecraft_ref" => ref}})
    end
  end

  setup do
    fx = ContactScheduleFixtures.setup_schedule()

    Map.merge(fx, %{
      org: fx.organization_id,
      mission: fx.mission_id,
      sc: fx.spacecraft.spacecraft_id
    })
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

  test "a spacecraft with no element set is left alone", c do
    assert {:ok, summary} = run(c)
    assert summary == %{}
  end

  defp run(c, extra \\ []),
    do:
      EphemerisUploads.run(
        c.org,
        c.mission,
        [c.sc],
        [now: @now, client: UploadClient, test_pid: self()] ++ extra
      )

  defp clear_jobs!(c),
    do: Repo.delete_all(from(job in "background_jobs", where: job.mission_id == ^c.mission))

  defp state(c),
    do:
      EphemerisStates.fetch_many(c.org, c.mission, [{c.provider.provider_id, c.sc}])[
        {c.provider.provider_id, c.sc}
      ]

  # The fixture's provider version gains a document that accepts uploads (as a sync would set).
  defp upload_provider!(c) do
    document = Map.put(capabilities(), "orbit", %{"source" => "accepts_ephemeris_upload"})

    {1, _rows} =
      from(row in MissionProviderRow,
        where:
          row.organization_id == ^c.org and row.mission_id == ^c.mission and
            row.provider_id == ^c.provider.provider_id and row.version == ^c.provider.version
      )
      |> Repo.update_all(set: [capabilities_document: document])
  end

  defp submit(c, opts) do
    epoch = DateTime.add(@now, -Keyword.get(opts, :hours_ago, 1) * 3_600)

    omm =
      %{
        "OBJECT_NAME" => "PRIMARY",
        "EPOCH" => epoch |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
        "MEAN_MOTION" => 15.2,
        "ECCENTRICITY" => 0.0005,
        "INCLINATION" => 53.0,
        "RA_OF_ASC_NODE" => 10.0,
        "ARG_OF_PERICENTER" => 20.0,
        "MEAN_ANOMALY" => 30.0,
        "BSTAR" => 2.0e-5
      }
      |> then(&if(opts[:norad], do: Map.put(&1, "NORAD_CAT_ID", opts[:norad]), else: &1))

    ElementSets.submit(c.org, c.mission, [%{spacecraft_id: c.sc, input: {:omm, omm}}], [
      {:now, @now} | @opts
    ])
  end

  defp capabilities do
    %{
      "contract_version" => "1.0",
      "provider" => %{"type" => "cadence_ground_network_simulator"},
      "operations" => %{
        "opportunity_search" => true,
        "contact_reservation" => true,
        "contact_modification" => true,
        "contact_cancellation" => true,
        "inventory_discovery" => true,
        "delivery_profile_provisioning" => true
      },
      "reservation" => %{
        "confirmation" => "asynchronous",
        "idempotency" => "native",
        "recovery" => "client_reference"
      },
      "events" => %{
        "polling" => true,
        "webhooks" => false,
        "delivery_semantics" => "at_least_once"
      },
      "search" => %{
        "spacecraft_batch_limit" => 100,
        "station_batch_limit" => 30,
        "page_size_limit" => 100
      },
      "delivery" => %{
        "kinds" => ["realtime_stream"],
        "protocols" => ["tcp"],
        "directions" => ["downlink"]
      }
    }
  end
end
