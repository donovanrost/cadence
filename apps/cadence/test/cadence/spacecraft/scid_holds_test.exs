defmodule Cadence.Spacecraft.ConfigKinds.ScidHoldsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Control.{Configuration, ScidSharing}

  alias Cadence.GroundNetworks.{
    MissionProvider,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Spacecraft
  alias Cadence.Spacecraft.ConfigKinds.ScidHolds
  alias Cadence.SpacecraftStore

  defmodule Sharing do
    @moduledoc false
    def shared_many(_org, _mission, scids),
      do:
        for(
          scid <- scids,
          shared = Process.get({:shared, scid}, []),
          shared != [],
          into: %{},
          do: {scid, shared}
        )
  end

  describe "holds/3 (the kind's folded item)" do
    setup do
      previous = Application.get_env(:cadence, :scid_sharing)
      Application.put_env(:cadence, :scid_sharing, Sharing)
      on_exit(fn -> Application.put_env(:cadence, :scid_sharing, previous) end)
    end

    test "a create whose SCID another mission flies through a shared account" do
      share(42, [{"m-b", [ksat()]}])

      assert [
               %{
                 kind: "spacecraft",
                 entity_id: "sc-new",
                 reason: :scid_shared_in_organization,
                 blocking: false,
                 sentence: sentence,
                 details: details
               }
             ] = ScidHolds.holds("org", "mission", [create("sc-new", 42)])

      assert sentence ==
               "Another mission in this organization also flies SCID 42 through KSAT. " <>
                 "KSAT's stations can't tell the two spacecraft's uplinks apart."

      assert details == %{
               scid: 42,
               provider_accounts: [%{id: "acct-ksat", name: "KSAT"}],
               mission: nil,
               mission_count: 1
             }
    end

    test "several missions fold into one counted item over the union of accounts" do
      share(42, [{"m-b", [ksat()]}, {"m-c", [aws(), ksat()]}])

      assert [%{sentence: sentence, details: details}] =
               ScidHolds.holds("org", "mission", [create("sc-new", 42)])

      assert sentence ==
               "2 other missions in this organization also fly SCID 42 through " <>
                 "AWS Ground Station and KSAT. Their stations can't tell the spacecraft's " <>
                 "uplinks apart."

      assert %{
               mission: nil,
               mission_count: 2,
               provider_accounts: [%{name: "AWS Ground Station"}, _]
             } =
               details
    end

    test "only a create or an update that changes the SCID raises it" do
      share(42, [{"m-b", [ksat()]}])

      same = %{create("sc-1", 42) | op: :update} |> Map.put(:previous, %{"scid" => 42})
      changed = %{create("sc-2", 42) | op: :update} |> Map.put(:previous, %{"scid" => 7})
      archive = %{kind: "spacecraft", op: :delete, entity_id: "sc-3", previous: %{"scid" => 42}}

      assert [%{entity_id: "sc-2"}] = ScidHolds.holds("org", "mission", [same, changed, archive])
      assert [] = ScidHolds.holds("org", "mission", [create("sc-4", 43)])
    end
  end

  describe "item/5 sentences (ux U81 §1)" do
    test "a named mission" do
      assert %{sentence: sentence, details: %{mission: %{id: "m-b", name: "Bravo"}}} =
               ScidHolds.item("sc", 42, [ksat()], %{id: "m-b", name: "Bravo"}, 1)

      assert sentence ==
               "Another mission in this organization, Bravo, also flies SCID 42 through KSAT. " <>
                 "KSAT's stations can't tell the two spacecraft's uplinks apart."
    end

    test "unnamed accounts are counted, never shown by id" do
      unnamed = &%{id: "acct-#{&1}", name: nil}

      assert sentence(ScidHolds.item("sc", 9, [ksat(), unnamed.(1)], nil, 1)) =~
               "through KSAT and 1 other provider account. Their stations"

      assert sentence(ScidHolds.item("sc", 9, [aws(), ksat(), unnamed.(1), unnamed.(2)], nil, 1)) =~
               "through AWS Ground Station, KSAT and 2 other provider accounts. Their stations"

      assert sentence(ScidHolds.item("sc", 9, [unnamed.(1)], nil, 1)) =~
               "through a provider account you share. Its stations can't"

      assert sentence(ScidHolds.item("sc", 9, [unnamed.(1), unnamed.(2)], nil, 3)) ==
               "3 other missions in this organization also fly SCID 9 through 2 provider " <>
                 "accounts you share. Their stations can't tell the spacecraft's uplinks apart."
    end
  end

  describe "organization sharing and the viewer (real rows)" do
    setup do
      %{organization_id: org, mission_id: alpha} = configuration_mission("scid-a")
      bravo = unique("mission-scid-b")
      charlie = unique("mission-scid-c")
      Cadence.DataCase.persist_mission_scope(org, bravo, mission_name: "Bravo")
      Cadence.DataCase.persist_mission_scope(org, charlie, mission_name: "Charlie")

      %{organization_id: other_org, mission_id: delta} = configuration_mission("scid-d")

      ksat = account!(org, "KSAT")
      lone = account!(org, "Lone")
      foreign = account!(other_org, "KSAT elsewhere")

      provider!(org, alpha, ksat)
      provider!(org, bravo, ksat)
      provider!(org, charlie, lone)
      provider!(other_org, delta, foreign)

      spacecraft!(org, bravo, 42)
      spacecraft!(org, charlie, 42)
      spacecraft!(other_org, delta, 42)

      %{org: org, alpha: alpha, bravo: bravo, ksat: ksat}
    end

    test "only another mission of the organization on a shared account counts", ctx do
      assert ScidSharing.shared_many(ctx.org, ctx.alpha, [42, 43]) == %{
               42 => [
                 %{mission_id: ctx.bravo, provider_accounts: [%{id: ctx.ksat, name: "KSAT"}]}
               ]
             }
    end

    test "a viewer who can open the other mission sees it named", ctx do
      alice = member_scope(ctx.org, :member, "Alice")

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(alice, ctx.alpha, {:ops, [new_spacecraft(42)]})

      assert [%{sentence: sentence, details: details}] = scid_items(checks)

      assert sentence ==
               "Another mission in this organization, Bravo, also flies SCID 42 through KSAT. " <>
                 "KSAT's stations can't tell the two spacecraft's uplinks apart."

      assert details == %{
               scid: 42,
               provider_accounts: [%{id: ctx.ksat, name: "KSAT"}],
               mission: %{id: ctx.bravo, name: "Bravo"},
               mission_count: 1
             }
    end

    test "a viewer who can't open it sees the folded item: no mission id or name", ctx do
      assert {:ok, %{checks: checks}} =
               Configuration.preview(
                 service_scope(ctx.org, ctx.alpha),
                 ctx.alpha,
                 {:ops, [new_spacecraft(42)]}
               )

      assert [%{sentence: sentence, details: %{mission: nil, mission_count: 1}} = item] =
               scid_items(checks)

      assert sentence ==
               "Another mission in this organization also flies SCID 42 through KSAT. " <>
                 "KSAT's stations can't tell the two spacecraft's uplinks apart."

      refute inspect(item) =~ ctx.bravo
      refute inspect(item) =~ "Bravo"
    end

    test "a SCID no other mission shares raises nothing", ctx do
      alice = member_scope(ctx.org, :member, "Alice")

      assert {:ok, %{checks: checks}} =
               Configuration.preview(alice, ctx.alpha, {:ops, [new_spacecraft(43)]})

      assert scid_items(checks) == []
    end
  end

  defp ksat, do: %{id: "acct-ksat", name: "KSAT"}
  defp aws, do: %{id: "acct-aws", name: "AWS Ground Station"}

  defp share(scid, missions),
    do:
      Process.put(
        {:shared, scid},
        Enum.map(missions, fn {id, accounts} -> %{mission_id: id, provider_accounts: accounts} end)
      )

  defp create(id, scid),
    do: %{
      kind: "spacecraft",
      op: :create,
      entity_id: id,
      previous: nil,
      proposed: %{"scid" => scid}
    }

  defp sentence(%{sentence: sentence}), do: sentence

  defp new_spacecraft(scid),
    do: %{kind: "spacecraft", action: :create, document: spacecraft_doc(unique("SC"), scid)}

  defp scid_items(checks),
    do:
      for(
        %{items: items} <- checks,
        %{reason: :scid_shared_in_organization} = item <- items,
        do: item
      )

  defp account!(org, name) do
    id = unique("acct")
    credential_ref = unique("credential")

    {:ok, _credential} =
      ProviderCredentials.create(
        org,
        id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/#{id}/control-plane",
          registered_at: DateTime.utc_now()
        },
        manage_backend?: false
      )

    {:ok, _account, _version} =
      ProviderAccounts.create_for_system(
        org,
        %{
          provider_account_id: id,
          display_name: name,
          provider_type: :simulator,
          base_url: "http://simulator.test",
          environment_ref: unique("env"),
          credential_ref: credential_ref
        },
        %{"kind" => "system", "id" => "scid-holds-test"},
        validate_credential?: false
      )

    id
  end

  defp provider!(org, mission, account_id) do
    actor = %{"kind" => "system", "id" => "scid-holds-test"}

    {:ok, grant} =
      ProviderAccountGrants.grant_for_system(
        org,
        mission,
        account_id,
        %{provider_account_grant_id: unique("grant")},
        actor
      )

    {:ok, _account, version} = ProviderAccounts.fetch_for_system(org, account_id)

    {:ok, _provider} =
      MissionProviders.persist_provider(
        org,
        MissionProvider.new(%{
          provider_id: unique("provider"),
          mission_id: mission,
          display_name: "Simulator",
          provider_account_id: account_id,
          provider_account_version: version.version,
          provider_account_grant_id: grant.provider_account_grant_id,
          provider_account_grant_version: grant.version,
          provider_type: version.provider_type,
          client_key: version.client_key,
          base_url: version.base_url,
          credential_ref: version.credential_ref,
          environment_ref: version.environment_ref
        })
      )
  end

  defp spacecraft!(org, mission, scid) do
    {:ok, _spacecraft} =
      SpacecraftStore.persist_spacecraft(
        org,
        Spacecraft.new(%{
          spacecraft_id: unique("spacecraft"),
          mission_id: mission,
          display_name: unique("SC"),
          scid: scid
        })
      )
  end

  defp service_scope(org, mission) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: unique("svc"),
        organization_id: org,
        mission_id: mission,
        display_name: "Mission service",
        capabilities: [:mission_admin]
      })

    %Scope{
      actor_kind: :service,
      organization_id: org,
      mission_id: mission,
      service_identity: identity,
      capabilities: MapSet.new([:mission_admin])
    }
  end
end
