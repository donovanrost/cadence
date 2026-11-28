defmodule Cadence.CommandGroupFixtures do
  @moduledoc false

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.CommandReviewFixtures
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.ExactCommandAuthoringFixtures
  alias Cadence.Ids
  alias Cadence.Management.Transports
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo

  @doc "A mission with the exact-authoring catalog active and `count` commandable spacecraft."
  def setup!(count \\ 2) do
    c = CommandReviewFixtures.scope!()
    model = ExactCommandAuthoringFixtures.activate!(c.org, c.mission)

    spacecraft =
      for i <- 1..count do
        id = "sc-#{i}"

        {:ok, _} =
          Cadence.SpacecraftStore.persist_spacecraft(
            c.org,
            Cadence.Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: c.org,
              mission_id: c.mission,
              display_name: "SC-#{i}"
            })
          )

        CommandAuthoringFixtures.target!(c.org, c.mission, %{
          source_endpoint_id: Cadence.SourceEndpoints.managed_source_endpoint_id(id),
          spacecraft_id: id,
          display_name: "SC-#{i}"
        })

        id
      end

    Map.merge(c, %{
      ids: model.commands_by_name,
      revision_id: model.revision_id,
      spacecraft: spacecraft
    })
  end

  def command(c, name, args), do: %{command_id: c.ids[name], argument_values: args}

  @doc """
  A confirmed booking for `spacecraft_id` whose uplink leg the provider confirmed (it carries the
  command window), so preflight's `contact` check is GO (DECISIONS #60). `org`/`mission` are ids.
  """
  def commandable_pass!(org, mission, spacecraft_id, starts_at \\ nil, opts \\ []) do
    starts_at = starts_at || DateTime.add(DateTime.utc_now(), 1_800)
    suffix = System.unique_integer([:positive])
    provider = ProviderChangeFixtures.persist_provider!(org, mission, suffix, %{})

    {:ok, transport} =
      Transports.persist_transport(
        org,
        Transport.new(%{
          transport_id: "transport-pass-#{suffix}",
          mission_id: mission,
          display_name: "Provider uplink",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
        })
      )

    {:ok, profile} =
      Cadence.Contacts.fetch_provider_profile(
        org,
        mission,
        transport.materialized_provider_profile_id
      )

    id = "provider-reservation-pass-#{suffix}"

    %ProviderReservation{
      provider_reservation_id: id,
      organization_id: org,
      mission_id: mission,
      provider_id: provider.provider_id,
      provider_version: provider.version,
      provider_revision: 1,
      transport_id: transport.transport_id,
      transport_version: transport.version,
      service_profile_ref: transport.service_profile_ref,
      delivery_profile_ref: transport.delivery_profile_ref,
      provider_profile_id: profile.provider_profile_id,
      provider_profile_version: profile.version,
      scheduled_contact_id: "contact-" <> id,
      provider_contact_ref: "provider-contact-" <> id,
      provider_opportunity_ref: "opportunity-" <> id,
      idempotency_key: "key-" <> id,
      lifecycle_state: :confirmed,
      pass_phase: :scheduled,
      delivery_state: :pending,
      spacecraft_id: spacecraft_id,
      provider_spacecraft_ref: spacecraft_id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 600),
      request_document: %{"uplink" => %{"routing_rule_id" => "routing-rule-test"}},
      provider_confirmed_snapshot_document: %{
        "uplink" => %{"status" => "included"},
        "ground_station_ref" => Keyword.get(opts, :station_ref)
      }
    }
    |> ProviderReservationRow.changeset()
    |> Repo.insert!()
  end

  def draft(spacecraft_ids, commands, extra \\ %{}) do
    Map.merge(
      %{
        title: "Load shed",
        # The operator's explicit endpoint (an audited override); route-based resolution is
        # covered by Cadence.Comms.UplinkResolutionTest.
        targets:
          Enum.map(
            spacecraft_ids,
            &%{
              spacecraft_id: &1,
              source_endpoint_id: Cadence.SourceEndpoints.managed_source_endpoint_id(&1)
            }
          ),
        commands: commands,
        priority: 3
      },
      extra
    )
  end

  def actor(c), do: %{"actor_kind" => "user", "user_id" => c.scope.user.user_id}

  @doc "The digest a preflight would have shown for `draft`."
  def digest(c, draft) do
    {:ok, validated} = Validation.validate(c.org, c.mission, actor(c), draft)
    validated.digest
  end

  @doc "Another operator (a member of the same organization) with their own scope."
  def operator!(c, name \\ "Second Operator", role \\ :organization_admin) do
    id = Ids.new("operator")
    user = User.new(%{user_id: id, email: "#{id}@example.test", display_name: name})
    Repo.insert!(UserRow.changeset(user))

    member =
      OrganizationMembership.new(%{
        user_id: id,
        organization_id: c.org,
        role: role
      })

    Repo.insert!(OrganizationMembershipRow.changeset(member))
    {:ok, org} = Cadence.Organizations.fetch_organization(c.org)

    Scope.new(%{
      user: user,
      organization_id: c.org,
      organization: org,
      organization_membership: member
    })
  end
end
