defmodule Cadence.EphemerisUploadFixtures do
  @moduledoc """
  Shared setup for the ephemeris upload tests (#968): the contact-schedule fixture's mission,
  spacecraft and ready route, a test upload client, and helpers to submit element sets, make
  the bound provider accept uploads or pin a new version, add a second bound spacecraft, and
  run the upload job.
  """

  import Ecto.Query

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore}
  alias Cadence.ContactScheduleFixtures
  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.GroundNetworks.{ElementSets, EphemerisStates}
  alias Cadence.GroundNetworks.MissionProviders.ProviderRow, as: MissionProviderRow
  alias Cadence.Repo
  alias Cadence.SourceEndpointFixtures
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.{Spacecraft, SpacecraftStore}

  @now ~U[2026-11-28 12:00:00.000000Z]
  @opts [actor: %{"actor_kind" => "user", "user_id" => "user-ephemeris"}, source: "manual"]

  defmodule UploadClient do
    @moduledoc false
    def upload_ephemeris(_context, ref, ephemeris, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:uploaded, ref, ephemeris})
      Keyword.get(opts, :upload_result, {:ok, %{"spacecraft_ref" => ref}})
    end
  end

  def now, do: @now

  @doc "The fixture mission with the short keys the tests use."
  def setup_ephemeris do
    fx = ContactScheduleFixtures.setup_schedule()

    Map.merge(fx, %{
      org: fx.organization_id,
      mission: fx.mission_id,
      sc: fx.spacecraft.spacecraft_id
    })
  end

  def run(c, extra \\ []),
    do:
      EphemerisUploads.run(
        c.org,
        c.mission,
        [c.sc],
        [now: @now, client: UploadClient, test_pid: self()] ++ extra
      )

  # A newer provider version; the fixture's transport still pins the original one.
  def new_version!(c, document) do
    [row] =
      Repo.all(
        from(row in MissionProviderRow,
          where:
            row.organization_id == ^c.org and row.mission_id == ^c.mission and
              row.provider_id == ^c.provider.provider_id and row.version == ^c.provider.version
        )
      )

    Repo.insert!(%{row | version: row.version + 1, capabilities_document: document})
  end

  # Another spacecraft in the fixture's mission, mapped and bound to the same transport.
  def second_bound_spacecraft!(c) do
    id = c.sc <> "-second"

    {:ok, _spacecraft} =
      SpacecraftStore.persist_spacecraft(
        c.org,
        Spacecraft.new(%{spacecraft_id: id, mission_id: c.mission, display_name: "Second"})
      )

    {:ok, _endpoint} =
      SourceEndpointFixtures.persist(
        c.org,
        SourceEndpoint.new(%{
          source_endpoint_id: "mapping-" <> id,
          mission_id: c.mission,
          spacecraft_id: id,
          source_ref: "SIM-002",
          display_name: "Second provider identity"
        })
      )

    {:ok, _rule} =
      RoutingRuleStore.create_routing_rule(
        c.org,
        RoutingRule.new(%{
          routing_rule_id: "rule-" <> id,
          mission_id: c.mission,
          spacecraft_id: id,
          display_name: "Second downlink",
          purpose_label: "Telemetry",
          direction: :inbound,
          transport_id: c.transport.transport_id,
          transport_version: c.transport.version,
          role: :primary
        })
      )

    id
  end

  def clear_jobs!(c),
    do: Repo.delete_all(from(job in "background_jobs", where: job.mission_id == ^c.mission))

  def state(c),
    do:
      EphemerisStates.fetch_many(c.org, c.mission, [{c.provider.provider_id, c.sc}])[
        {c.provider.provider_id, c.sc}
      ]

  # The fixture's provider version gains a document that accepts uploads (as a sync would set).
  def upload_provider!(c) do
    document = Map.put(capabilities(), "orbit", %{"source" => "accepts_ephemeris_upload"})

    {1, _rows} =
      from(row in MissionProviderRow,
        where:
          row.organization_id == ^c.org and row.mission_id == ^c.mission and
            row.provider_id == ^c.provider.provider_id and row.version == ^c.provider.version
      )
      |> Repo.update_all(set: [capabilities_document: document])
  end

  def submit(c, opts) do
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

  def capabilities do
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
