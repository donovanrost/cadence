defmodule Cadence.GroundNetworks.EphemerisFindingsTest do
  @moduledoc """
  Ephemeris findings (#972): the `provider_ephemeris` attention items group a provider's
  spacecraft by cause (`norad_id_missing`, `failed`, `not_ready` by reason) from the same
  recorded outcomes as the providers read, page their spacecraft, clear by themselves, and an
  upload run publishes `providers` and `attention` only when an outcome changed.
  """
  use Cadence.DataCase, async: false

  import Cadence.EphemerisUploadFixtures
  import Ecto.Query

  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.EphemerisUploadFixtures.UploadClient
  alias Cadence.GroundNetworks.{ElementSets, EphemerisFindings}
  alias Cadence.GroundNetworks.MissionProviders.ProviderRow, as: MissionProviderRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Reads.ProviderEphemerisAttention
  alias Cadence.Repo

  setup do
    setup_ephemeris()
  end

  test "a lookup provider's set without a NORAD id is one group, gone once the set has one", c do
    {:ok, _results} = submit(c, [])
    clear_jobs!(c)
    {:ok, %{"norad_id_missing" => 1}} = run(c)

    provider = c.provider.provider_id

    assert [
             %{
               provider_id: ^provider,
               cause: "norad_id_missing",
               reason: nil,
               spacecraft_count: 1,
               spacecraft_ids: [sc]
             }
           ] = EphemerisFindings.groups(c.org, c.mission)

    assert sc == c.sc

    assert [%{id: id, source: "provider_ephemeris", conflict: "norad_id_missing"}] =
             ProviderEphemerisAttention.items(c.org, c.mission)

    assert id == "#{provider}:norad_id_missing"
    assert %{open: 1, acknowledged: 0} = ProviderEphemerisAttention.counts(c.org, c.mission)

    # A newer set with a NORAD id: the stored outcome is stale, so nothing is raised even before
    # the run records the new one, and after it the group stays gone.
    {:ok, _results} = submit(c, norad: 25_544, hours_ago: 0)
    assert EphemerisFindings.groups(c.org, c.mission) == []
    {:ok, %{"lookup" => 1}} = run(c)
    assert EphemerisFindings.groups(c.org, c.mission) == []
  end

  test "a failing upload is one group per provider with its retry; members carry the reason",
       c do
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)
    {:ok, %{"failed" => 1}} = run(c, upload_result: {:error, :econnrefused})

    assert [%{cause: "failed", spacecraft_count: 1, next_retry_at: %DateTime{} = retry}] =
             EphemerisFindings.groups(c.org, c.mission)

    group = %{provider_id: c.provider.provider_id, cause: "failed"}

    assert {:ok, %{members: [member], next_cursor: nil}} =
             EphemerisFindings.members(c.org, c.mission, group, [])

    assert %{reason: "econnrefused", attempts: 1, next_retry_at: ^retry} = member

    {:ok, %{"uploaded" => 1}} = run(c)
    assert EphemerisFindings.groups(c.org, c.mission) == []
  end

  test "not_ready groups by refusal reason and pages its spacecraft", c do
    second = second_bound_spacecraft!(c)
    unvalidated!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    submit_for!(c, second)
    clear_jobs!(c)

    {:ok, %{"not_ready" => 2}} =
      EphemerisUploads.run(c.org, c.mission, [c.sc, second],
        now: now(),
        client: UploadClient,
        test_pid: self()
      )

    assert [%{cause: "not_ready", reason: reason, spacecraft_count: 2, spacecraft_ids: ids}] =
             EphemerisFindings.groups(c.org, c.mission)

    assert reason == "mission_provider_not_validated"
    assert ids == Enum.sort([c.sc, second])

    assert [%{id: id}] = ProviderEphemerisAttention.items(c.org, c.mission)
    assert id == "#{c.provider.provider_id}:not_ready:mission_provider_not_validated"

    group = %{provider_id: c.provider.provider_id, cause: "not_ready", reason: reason}

    assert {:ok, %{members: [first], next_cursor: cursor}} =
             EphemerisFindings.members(c.org, c.mission, group, limit: 1)

    assert {:ok, %{members: [last], next_cursor: nil}} =
             EphemerisFindings.members(c.org, c.mission, group, limit: 1, after: cursor)

    assert [first.spacecraft_id, last.spacecraft_id] == ids

    assert {:ok, %{members: []}} =
             EphemerisFindings.members(c.org, c.mission, %{group | reason: "other"}, [])

    assert {:error, :unknown_cause} =
             EphemerisFindings.members(c.org, c.mission, %{group | cause: "lookup"}, [])
  end

  test "an upload run publishes providers and attention only when an outcome changed", c do
    ScopedReadUpdates.subscribe(:providers_changed, c.org, c.mission)
    ScopedReadUpdates.subscribe(:attention_changed, c.org, c.mission)
    {:ok, _results} = submit(c, [])
    clear_jobs!(c)

    {:ok, _summary} = run(c)
    assert_receive {:providers_changed, _org, _mission}
    assert_receive {:attention_changed, _org, _mission}

    {:ok, _summary} = run(c)
    refute_receive {:providers_changed, _org, _mission}, 50
    refute_receive {:attention_changed, _org, _mission}, 50
  end

  defp unvalidated!(c) do
    {1, _rows} =
      from(row in MissionProviderRow,
        where:
          row.organization_id == ^c.org and row.mission_id == ^c.mission and
            row.provider_id == ^c.provider.provider_id and row.version == ^c.provider.version
      )
      |> Repo.update_all(set: [last_validated_at: nil])
  end

  defp submit_for!(c, spacecraft_id) do
    omm = %{
      "OBJECT_NAME" => "SECOND",
      "EPOCH" =>
        now() |> DateTime.add(-3_600) |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
      "MEAN_MOTION" => 15.1,
      "ECCENTRICITY" => 0.0005,
      "INCLINATION" => 53.0,
      "RA_OF_ASC_NODE" => 20.0,
      "ARG_OF_PERICENTER" => 20.0,
      "MEAN_ANOMALY" => 40.0,
      "BSTAR" => 2.0e-5,
      "NORAD_CAT_ID" => 25_545
    }

    {:ok, _results} =
      ElementSets.submit(c.org, c.mission, [%{spacecraft_id: spacecraft_id, input: {:omm, omm}}],
        now: now(),
        actor: %{"actor_kind" => "user", "user_id" => "user-ephemeris"},
        source: "manual"
      )
  end
end
