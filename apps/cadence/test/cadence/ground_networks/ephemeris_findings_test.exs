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

  alias Cadence.Control.Providers.{EphemerisUploads, MissionProviderWrites}
  alias Cadence.EphemerisUploadFixtures.UploadClient

  alias Cadence.GroundNetworks.{
    ElementSets,
    EphemerisFindings,
    EphemerisStateRow,
    EphemerisStates,
    ProviderError
  }

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

  test "failed groups by closed code, filters by it, and never stores the provider's text", c do
    upload_provider!(c)
    second = second_bound_spacecraft!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    submit_for!(c, second)
    clear_jobs!(c)

    unreachable = %ProviderError{category: :provider_unavailable, detail: "secret-evidence-123"}
    refused = %ProviderError{category: :invalid_request, detail: "secret-evidence-456"}
    {:ok, %{"failed" => 1}} = run(c, upload_result: {:error, unreachable})
    {:ok, %{"failed" => 1}} = run_for(c, [second], upload_result: {:error, refused})

    assert [
             %{cause: "failed", reason: "provider_invalid_request", spacecraft_ids: [^second]},
             %{cause: "failed", reason: "provider_unavailable", next_retry_at: %DateTime{}}
           ] = EphemerisFindings.groups(c.org, c.mission)

    provider = c.provider.provider_id

    assert [
             "#{provider}:failed:provider_invalid_request",
             "#{provider}:failed:provider_unavailable"
           ] ==
             c.org |> ProviderEphemerisAttention.items(c.mission) |> Enum.map(& &1.id)

    group = %{provider_id: provider, cause: "failed", reason: "provider_unavailable"}

    assert {:ok, %{members: [%{spacecraft_id: sc, reason: "provider_unavailable", attempts: 1}]}} =
             EphemerisFindings.members(c.org, c.mission, group, [])

    assert sc == c.sc

    # Without a reason: every failed member, across codes, by spacecraft id.
    assert {:ok, %{members: all}} =
             EphemerisFindings.members(c.org, c.mission, %{group | reason: nil}, [])

    assert Enum.map(all, & &1.spacecraft_id) == Enum.sort([c.sc, second])

    # The provider's own text is never stored, so no read can return it.
    stored = Repo.all(from(row in EphemerisStateRow, select: row.reason))
    assert Enum.sort(stored) == ["provider_invalid_request", "provider_unavailable"]
    refute inspect(ProviderEphemerisAttention.items(c.org, c.mission)) =~ "secret-evidence"

    {:ok, %{"uploaded" => 1}} = run(c)
    assert [%{reason: "provider_invalid_request"}] = EphemerisFindings.groups(c.org, c.mission)
  end

  test "since is when the pair entered its outcome: kept by a re-check, reset by a change", c do
    unvalidated!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)

    t0 = now()
    {:ok, %{"not_ready" => 1}} = run_for(c, [c.sc], now: t0)
    assert [%{since: ^t0}] = EphemerisFindings.groups(c.org, c.mission)

    # The hourly re-check records the same outcome: since stays, though updated_at moves.
    later = DateTime.add(t0, 3_600)
    {:ok, %{"not_ready" => 1}} = run_for(c, [c.sc], now: later)
    assert [%{since: ^t0}] = EphemerisFindings.groups(c.org, c.mission)
    assert %{outcome_since: ^t0, updated_at: ^later} = state(c)

    # The route becomes ready: a new outcome, a new since.
    validated!(c)
    ready_at = DateTime.add(t0, 7_200)
    {:ok, %{"lookup" => 1}} = run_for(c, [c.sc], now: ready_at)
    assert %{status: "lookup", outcome_since: ^ready_at} = state(c)
  end

  test "not_ready groups by refusal reason and pages its spacecraft", c do
    second = second_bound_spacecraft!(c)
    unvalidated!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    submit_for!(c, second)
    clear_jobs!(c)

    {:ok, %{"not_ready" => 2}} = run_for(c, [c.sc, second])

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

  test "two failed runs in a row both publish: attempts and the retry time are shown", c do
    ScopedReadUpdates.subscribe(:providers_changed, c.org, c.mission)
    ScopedReadUpdates.subscribe(:attention_changed, c.org, c.mission)
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)
    failure = {:error, %ProviderError{category: :provider_unavailable, detail: "down"}}

    {:ok, %{"failed" => 1}} = run_for(c, [c.sc], upload_result: failure)
    assert %{attempts: 1, next_retry_at: first} = state(c)
    assert_receive {:providers_changed, _org, _mission}
    assert_receive {:attention_changed, _org, _mission}

    {:ok, %{"failed" => 1}} = run_for(c, [c.sc], upload_result: failure)
    assert %{attempts: 2, next_retry_at: second} = state(c)
    assert DateTime.after?(second, first)
    assert_receive {:providers_changed, _org, _mission}
    assert_receive {:attention_changed, _org, _mission}
  end

  test "an archived provider leaves the findings, the counts and the reconcile", c do
    {:ok, _results} = submit(c, [])
    clear_jobs!(c)
    {:ok, %{"norad_id_missing" => 1}} = run(c)
    assert [_group] = EphemerisFindings.groups(c.org, c.mission)

    # A newer set makes the pair pending again, which the reconcile would stage.
    {:ok, _results} = submit(c, hours_ago: 0)
    clear_jobs!(c)
    assert Enum.any?(EphemerisStates.pending(5_000), &(elem(&1, 1) == c.mission))

    # Archiving adds a newer, archived version; the transport still pins the active one.
    {:ok, _archived} =
      MissionProviderWrites.archive(c.scope, c.mission, c.provider.provider_id, %{
        "reason" => "Retired"
      })

    assert EphemerisFindings.groups(c.org, c.mission) == []
    assert EphemerisStates.buckets(c.org, c.mission) == %{}
    refute Enum.any?(EphemerisStates.pending(5_000), &(elem(&1, 1) == c.mission))
  end

  test "archiving removes a failed pair's due retry, and a run sends nothing to it", c do
    upload_provider!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)
    failure = {:error, %ProviderError{category: :provider_unavailable, detail: "down"}}
    {:ok, %{"failed" => 1}} = run_for(c, [c.sc], upload_result: failure)
    assert %{status: "failed"} = state(c)
    # The test client reports the attempt even when it answers with a failure.
    assert_received {:uploaded, "SIM-001", _ephemeris}

    # The transport still pins the older, active version, which ProviderScheduling still
    # schedules; the archive must stop both the retry sweep and a direct run.
    {:ok, _archived} =
      MissionProviderWrites.archive(c.scope, c.mission, c.provider.provider_id, %{
        "reason" => "Retired"
      })

    assert state(c) == nil
    assert EphemerisUploads.retry_due(DateTime.add(now(), 7 * 86_400)) == 0

    assert {:ok, summary} = run_for(c, [c.sc])
    refute_received {:uploaded, _ref, _ephemeris}
    assert Map.values(summary) |> Enum.sum() == 0
    assert state(c) == nil
  end

  defp run_for(c, spacecraft_ids, opts \\ []) do
    opts = Keyword.merge([now: now(), client: UploadClient, test_pid: self()], opts)
    EphemerisUploads.run(c.org, c.mission, spacecraft_ids, opts)
  end

  defp validated!(c), do: set_validated!(c, now())
  defp unvalidated!(c), do: set_validated!(c, nil)

  defp set_validated!(c, at) do
    {1, _rows} =
      from(row in MissionProviderRow,
        where:
          row.organization_id == ^c.org and row.mission_id == ^c.mission and
            row.provider_id == ^c.provider.provider_id and row.version == ^c.provider.version
      )
      |> Repo.update_all(set: [last_validated_at: at])
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
