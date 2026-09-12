defmodule Cadence.Reads.ApplicationSurfaces.ContactRecordTest do
  use Cadence.DataCase, async: false
  import Ecto.Query
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}

  alias Cadence.Contacts.{
    ContactStore,
    ProviderChangeApprovals,
    ProviderReservationChanges,
    RealizedContact
  }

  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.Path, as: ContactPath
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @renderer Path.expand(
              "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
              __DIR__
            )

  setup do
    c = Fixtures.setup_contact()

    {:ok, scheduled} =
      ContactStore.fetch_scheduled(
        c.organization_id,
        c.mission_id,
        c.reservation.scheduled_contact_id
      )

    Map.put(c, :scheduled, scheduled)
  end

  test "scheduled and realized records render distinct scoped evidence through the public module",
       c do
    paths =
      Enum.map(
        1..27,
        &ContactPath.new(%{
          path_id: "actual-path-#{&1}",
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "actual-source-#{&1}",
          metadata: %{"secret" => "do-not-render"}
        })
      )

    realized =
      RealizedContact.new(%{
        realized_contact_id: "realized-record",
        organization_id: c.organization_id,
        mission_id: c.mission_id,
        scheduled_contact_id: c.scheduled.scheduled_contact_id,
        paths: paths,
        source_endpoint_refs: Enum.map(1..27, &"actual-source-#{&1}"),
        lifecycle_state: :completed,
        clock_mode: :replay,
        initial_time: ~U[2026-07-20 12:00:00Z],
        realized_at: ~U[2026-07-20 12:00:01Z],
        metadata: %{"credential" => "do-not-render"}
      })

    assert {:ok, _} = ContactStore.persist_realization(c.scheduled, realized)
    model = props(c, c.scheduled.scheduled_contact_id)
    r = model["record"]
    assert r["subject"]["kind"] == "scheduled"
    assert r["scheduled"]["lifecycle_state"] == "realized"
    assert r["review"]["lifecycle_state"] == "scheduled"
    assert r["realized"]["id"] == "realized-record"
    assert r["realized_paths"]["more"]
    assert length(r["realized_paths"]["entries"]) == 25
    refute Jason.encode!(model) =~ "do-not-render"
    render(model, ["contact-record-schedule", "contact-record-realized", "realized_paths-next"])
    next = props(c, "realized-record", %{"realized_paths_page" => "2", "sources_page" => "2"})
    assert next["record"]["subject"]["kind"] == "realized"

    assert Enum.map(next["record"]["realized_paths"]["entries"], & &1["id"]) == [
             "actual-path-26",
             "actual-path-27"
           ]

    render(next, ["realized_paths-previous", "sources-previous"])
  end

  test "immutable schedule reviews retain the approved provider origin without rewriting old evidence",
       c do
    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
             })

    [change] =
      ProviderReservationChanges.list_for_reservation(
        c.organization_id,
        c.reservation.provider_reservation_id
      )

    assert {:ok, _} =
             ProviderChangeApprovals.approve(
               c.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Reviewed change"
             )

    current = props(c, c.scheduled.scheduled_contact_id)["record"]
    assert current["review"]["revision"] == 2
    assert current["origin"]["change_id"] == change.provider_reservation_change_id
    assert current["origin"]["reservation_id"] == c.reservation.provider_reservation_id
    assert current["origin"]["proposal_hash"] == change.proposal_hash
    historical = props(c, c.scheduled.scheduled_contact_id, %{"revision" => "1"})
    assert historical["record"]["review"]["starts_at"] == c.baseline["starts_at"]
    assert historical["record"]["scheduled"]["starts_at"] != c.baseline["starts_at"]
    assert historical["record"]["origin"] == nil
    assert Enum.map(historical["record"]["revisions"]["entries"], & &1["revision"]) == [1]
    render(historical, ["contact-record-historical", "contact-record-current-revision"])
  end

  test "standalone realized contacts expose their evidence without inventing a schedule", c do
    r =
      RealizedContact.new(%{
        realized_contact_id: "standalone",
        organization_id: c.organization_id,
        mission_id: c.mission_id,
        paths: [],
        lifecycle_state: :stopped
      })

    assert {:ok, _} = ContactStore.persist_realized(r)
    model = props(c, "standalone")
    assert model["record"]["scheduled"] == nil
    assert model["record"]["review"] == nil
    render(model, ["contact-record-no-schedule", "contact-record-realized_paths-empty"])

    assert {:error, :unsupported_application_surface_query} =
             load(c, "standalone", %{"revision" => "1"})
  end

  test "invalid queries, foreign subjects, ambiguous identities and broken lineage remain unavailable",
       c do
    id = c.scheduled.scheduled_contact_id

    for q <- [
          %{"revision" => "2"},
          %{"revision" => "01"},
          %{"before_revision" => "0"},
          %{"sources_page" => "1000001"},
          %{"unexpected" => "1"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c, id, q)
    end

    assert {:error, :unsupported_application_surface_query} = load(c, "foreign", %{})
    scoped_elsewhere = %{c | admin_scope: %{c.admin_scope | mission_id: "different-mission"}}
    assert {:error, :unsupported_application_surface_query} = load(scoped_elsewhere, id, %{})
    revoked = %{c | admin_scope: %{c.admin_scope | organization_membership: nil}}
    assert {:error, :unsupported_application_surface_query} = load(revoked, id, %{})
    foreign = Fixtures.setup_contact()

    assert {:error, :unsupported_application_surface_query} =
             load(c, foreign.reservation.scheduled_contact_id, %{})

    from(r in ScheduledContactRow, where: r.scheduled_contact_id == ^id)
    |> Repo.update_all(set: [realized_contact_id: "missing-realized"])

    assert {:error, :unsupported_application_surface_query} = load(c, id, %{})

    assert {:ok, _} =
             ContactStore.persist_realized(
               RealizedContact.new(%{
                 realized_contact_id: id,
                 organization_id: c.organization_id,
                 mission_id: c.mission_id
               })
             )

    assert {:error, :unsupported_application_surface_query} = load(c, id, %{})
  end

  defp props(c, id, q \\ %{}) do
    assert {:ok,
            %{"data" => %{"presentation" => %{"component" => "OpsContactRecord", "props" => p}}}} =
             load(c, id, q)

    p
  end

  defp load(c, id, q),
    do:
      OpsConsole.load(c.admin_scope, HostContext.mission(c.mission_id), %SurfaceQueryRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "contact_record",
        surface_version: 1,
        query_id: "cadence.ops.contact_record",
        query_version: 1,
        params: Map.merge(%{"contact_id" => id}, q)
      })

  defp render(props, ids) do
    {output, status} =
      System.cmd(
        "node",
        [
          @renderer,
          Jason.encode!([
            %{component: "OpsContactRecord", props: props, expected: %{presentIds: ids}}
          ])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
