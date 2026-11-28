defmodule Cadence.Reads.CatalogRevisionSpacecraftTest do
  @moduledoc """
  #678: the spacecraft that use a catalog revision, whose latest saved configuration names it,
  whose active generation runs it, or both, paged by name then id in a fixed number of queries.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Reads.CatalogRevisionSpacecraft

  setup do
    org = "org-rev-craft-#{System.unique_integer([:positive])}"
    mid = "mission-rev-craft-#{System.unique_integer([:positive])}"
    {craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    scope = Fixtures.user_scope(org, "admin")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{org: org, mid: mid, scope: scope, craft: craft, catalog: catalog.catalog_revision_id}
  end

  test "a configured craft uses the revision saved and active, with its saved version", c do
    configure!(c)
    {:ok, page} = CatalogRevisionSpacecraft.page(c.org, c.mid, c.catalog, nil, nil)

    assert %{spacecraft: [row], total: 1, next_cursor: nil} = page
    assert row.id == c.craft.spacecraft_id
    assert row.uses == ["saved", "active"]
    assert is_integer(row.configuration_version)
  end

  test "a craft saved on another revision is 'active' here and 'saved' there", c do
    configure!(c)
    other = insert_catalog_revision!(c)
    insert_saved!(c, c.craft.spacecraft_id, other, 99)

    {:ok, %{spacecraft: [here]}} =
      CatalogRevisionSpacecraft.page(c.org, c.mid, c.catalog, nil, nil)

    assert here.uses == ["active"]

    {:ok, %{spacecraft: [there]}} = CatalogRevisionSpacecraft.page(c.org, c.mid, other, nil, nil)
    assert there.uses == ["saved"]
    assert there.configuration_version == 99
  end

  test "an unknown revision is not found, and a foreign cursor is refused", c do
    assert {:error, :catalog_revision_not_found} =
             CatalogRevisionSpacecraft.page(c.org, c.mid, "catalog_revision:nope", nil, nil)

    assert {:error, :invalid_cursor} =
             CatalogRevisionSpacecraft.page(c.org, c.mid, c.catalog, "not-a-cursor", nil)
  end

  test "1,000 saved craft page by name in a fixed number of queries", c do
    now = DateTime.utc_now()

    ids =
      for n <- 1..1_000 do
        id = "sc-rev-#{String.pad_leading(Integer.to_string(n), 4, "0")}"

        Repo.insert_all("mission_spacecraft", [
          %{
            spacecraft_id: id,
            organization_id: c.org,
            mission_id: c.mid,
            display_name: "CRAFT-#{String.pad_leading(Integer.to_string(1_001 - n), 4, "0")}",
            metadata: %{},
            lifecycle_state: "active",
            inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
          }
        ])

        insert_saved!(c, id, c.catalog, 1, now)
        id
      end

    {first, queries} =
      count_queries(fn -> CatalogRevisionSpacecraft.page(c.org, c.mid, c.catalog, nil, 500) end)

    {:ok, %{spacecraft: page1, total: 1_000, next_cursor: cursor}} = first
    assert length(page1) == 500

    # The counter sees the queries (a wrong event name would read 0), and they don't grow per craft.
    assert queries > 0
    assert queries <= 12, "#{queries} queries for 1,000 craft"

    {:ok, %{spacecraft: page2, next_cursor: nil}} =
      CatalogRevisionSpacecraft.page(c.org, c.mid, c.catalog, cursor, 500)

    all = page1 ++ page2
    assert length(Enum.uniq_by(all, & &1.id)) == 1_000
    assert Enum.map(all, & &1.name) == Enum.sort(Enum.map(all, & &1.name))
    assert Enum.all?(all, &(&1.uses == ["saved"]))
    assert MapSet.new(all, & &1.id) == MapSet.new(ids)
  end

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()

    :telemetry.attach(
      inspect(ref),
      [:cadence, :repo, :query],
      fn _event, _measurements, _metadata, _config -> send(parent, {ref, :query}) end,
      nil
    )

    try do
      result = fun.()
      {result, drain(ref, 0)}
    after
      :telemetry.detach(inspect(ref))
    end
  end

  defp drain(ref, n) do
    receive do
      {^ref, :query} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end

  defp insert_catalog_revision!(c) do
    revision =
      Fixtures.persist_imported_revision!(c.org, c.mid,
        revision_label: "Rev 2",
        approve: false
      )

    revision.catalog_revision_id
  end

  defp insert_saved!(c, spacecraft_id, catalog, version, now \\ DateTime.utc_now()) do
    Repo.insert_all("spacecraft_configuration_revisions", [
      %{
        configuration_revision_id: "cfg-#{System.unique_integer([:positive])}",
        organization_id: c.org,
        mission_id: c.mid,
        spacecraft_id: spacecraft_id,
        version: version,
        catalog_revision_id: catalog,
        document: %{},
        content_sha256: String.duplicate("a", 64),
        application_basis: "basis",
        created_by: "test",
        inserted_at: now
      }
    ])
  end

  # An active generation for the fixture's craft on its catalog (as the withdrawal test does).
  defp configure!(c) do
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mid)
    current = Drafts.snapshot(mission, c.craft)

    endpoint =
      Cadence.SourceEndpoints.list_source_endpoints(c.org, c.mid)
      |> Enum.find(&(&1.spacecraft_id == c.craft.spacecraft_id))

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42],
        "telemetry_source_endpoint_id" => endpoint && endpoint.source_endpoint_id
      })

    :ok = Fixtures.change_set_switches!(c.org, c.mid, c.craft.spacecraft_id, document)
    {:ok, _} = Drafts.save(c.scope, c.mid, c.craft.spacecraft_id, current.token, document)
    token = Drafts.snapshot(mission, c.craft).token

    {:ok, request} = Review.request_many(c.scope, c.mid, %{c.craft.spacecraft_id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
