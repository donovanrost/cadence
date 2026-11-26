defmodule Cadence.Dev.ReflectOrbital.LiveContacts do
  @moduledoc "Continuous local rehearsal contacts; not provider-booked orbital passes."
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, ScheduledContact}
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.Runtime.MissionRuntime

  def run(duration_seconds, scids \\ Enum.to_list(1..10)) when duration_seconds in 60..28_800 do
    # Safe ETF recovery requires the persisted semantic types' atoms to exist.
    :ok =
      :cadence
      |> Application.spec(:modules)
      |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Cadence.SemanticRuntime"))
      |> Code.ensure_all_loaded()

    now = DateTime.utc_now()

    existing =
      F.organization_id()
      |> Cadence.Contacts.list_scheduled_contacts(F.mission_id())
      |> Enum.filter(fn contact ->
        contact.metadata["fixture"] == "earendil-live-dashboards" and
          contact.lifecycle_state in [:scheduled, :realized] and
          DateTime.after?(contact.ends_at, DateTime.add(now, 60, :second))
      end)
      |> Map.new(fn contact -> {List.first(contact.source_endpoint_refs), contact} end)

    sites = F.sites() |> List.to_tuple()
    selected = MapSet.new(scids)
    crafts = Enum.filter(F.spacecraft(), &MapSet.member?(selected, &1.scid))

    if length(crafts) != length(scids),
      do: raise("Requested craft exceed the seeded fixture fleet")

    contacts =
      for craft <- crafts do
        site = elem(sites, rem(craft.scid - 1, tuple_size(sites)))
        source = "spacecraft_runtime:#{craft.spacecraft_id}"
        port = rehearsal_port(craft.scid, site, tuple_size(sites))

        contact =
          Map.get_lazy(existing, source, fn ->
            create_contact(craft, site, source, port, now, duration_seconds)
          end)

        {craft, site, port, contact}
      end

    Enum.map(contacts, fn {craft, site, port, contact} ->
      realized = await_active(contact, 100)
      [path] = realized.paths

      # Recover the decoder before the short path-snapshot call. A coordinator
      # replaying saved telemetry cannot answer that call within five seconds.
      partition = %Cadence.Runtime.PartitionKey{
        affinity: :source_endpoint,
        value: "spacecraft_runtime:#{craft.spacecraft_id}"
      }

      {:ok, _partition} =
        GenServer.call(
          MissionRuntime.coordinator_name(F.mission_id()),
          {:partition_snapshot, partition},
          600_000
        )

      {:ok, snapshot} =
        Cadence.path_runtime_snapshot(
          F.organization_id(),
          F.mission_id(),
          realized.realized_contact_id,
          path.path_id
        )

      [provider] = snapshot.provider_runtimes
      true = provider.port == port

      %{
        spacecraft_id: craft.spacecraft_id,
        scid: craft.scid,
        port: provider.port,
        source_endpoint_id: "spacecraft_runtime:#{craft.spacecraft_id}",
        scheduled_contact_id: contact.scheduled_contact_id,
        realized_contact_id: realized.realized_contact_id,
        ground_site: site["name"],
        ends_at: contact.ends_at
      }
    end)
  end

  # The first craft at each site uses the demo gateway, while additional rehearsal
  # paths own individual Cadence listeners.
  defp rehearsal_port(scid, site, site_count) when scid <= site_count, do: site["ingress_port"]
  defp rehearsal_port(scid, _site, _site_count), do: 43_000 + scid

  defp create_contact(craft, site, source, port, now, duration_seconds) do
    id = "rehearsal-#{craft.spacecraft_id}-#{DateTime.to_unix(now)}"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: id,
        organization_id: F.organization_id(),
        mission_id: F.mission_id(),
        source_endpoint_refs: [source],
        contact_intents: [:telemetry_downlink],
        starts_at: DateTime.add(now, 2, :second),
        ends_at: DateTime.add(now, duration_seconds, :second),
        metadata: %{
          "fixture" => "earendil-live-dashboards",
          "synthetic" => true,
          "purpose" =>
            "Continuous dashboard rehearsal; not an orbital pass or provider reservation",
          "display_name" => "#{craft.display_name} — #{site["name"]} rehearsal",
          "ground_station_ref" => site["id"],
          "rate_hz" => 1.0
        },
        paths: [
          Path.new(%{
            path_id: "#{id}:downlink",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: source,
            metadata: %{"ground_station_ref" => site["id"], "synthetic" => true},
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: "#{id}:tcp",
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  host: F.bind_host(),
                  port: port,
                  ingress_protocol_family: :tm,
                  frame_size: F.frame_size(),
                  ingress_metadata: %{frame_size: F.frame_size(), ocf_length: 0}
                }
              })
            ]
          })
        ]
      })

    case Cadence.Contacts.persist_scheduled_contact(F.organization_id(), contact) do
      {:ok, saved} -> saved
      error -> raise "Contact #{id} failed: #{inspect(error)}"
    end
  end

  defp await_active(contact, attempts) when attempts > 0 do
    case Cadence.Contacts.fetch_realized_contact(
           F.organization_id(),
           F.mission_id(),
           contact.scheduled_contact_id <> "_run"
         ) do
      {:ok, %RealizedContact{lifecycle_state: :active} = realized} ->
        realized

      _ ->
        Process.sleep(200)
        await_active(contact, attempts - 1)
    end
  end

  defp await_active(contact, 0),
    do: raise("Contact did not become active: #{contact.scheduled_contact_id}")
end
