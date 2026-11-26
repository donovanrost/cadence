# Apogee QA mission (development only; #231, dev reset DECISIONS #112).
#
# Builds the two QA missions on a fresh dev database through the product's own store and context
# functions, the way dev/reflect_orbital/seed.exs builds Earendil (no Repo inserts):
#
#   - the mission qa-mission-23565 ("QA mission 23565") in the Reflect Orbital organization; it
#     inherits the organization's approval policy (no governance setting is written);
#   - the profile "QA L10 profile" and two spacecraft, QA MISSION 23565-1 and -2 (SCID 1 and 2),
#     each with a source endpoint and Telemetry Decom installed (Communications is a platform app,
#     on every mission already);
#   - the catalog "qa-l10 demo copy" (demo_spacecraft.yaml) imported under the seed's own system
#     actor, naming the administrator who ran it (#513): its mission model is a CANDIDATE that any
#     OTHER admin may approve (the runner counts as its importer);
#   - a QA provider on the dev simulator: credential (the env variable named, never its value),
#     account, grant to the QA mission, mission provider, then validate and sync;
#   - a local test station, direct TCP-client transport and extra downlink route to 23565-1,
#     submitted as a change set for independent review;
#   - QA mission 2, qa-mission-23566 ("QA mission 23566"; director's GO 11-18), for checks of a
#     decision under 'direct': the same organization and rules, also with NO approval override
#     (it reads 'independent' until lead saves 'direct' by hand in the console, reset slot); its
#     own profile, one spacecraft QA MISSION 23566-1 (SCID 601, clear of Earendil's 1-500) with a
#     source endpoint and Telemetry Decom, and its own copy of the catalog imported under the
#     seed's actor, so its model is a CANDIDATE. No provider, transport or route.
#
# The spacecraft's telemetry and commanding switches stay UNSET
# (off): qa's slot does the first start by hand (a change set, approved by a second admin), and a
# second admin approves the mission model in the console. No spacecraft configuration is saved.
#
# Rerunnable: every record has a fixed id, and what exists is left as it is.
#
# Run after the Reflect Orbital seed and the QA personas, with the dev secrets in the environment
# (mise), against a running development stack:
#
#   cd apps/cadence_web
#   mise exec -- mix run --no-start ../../dev/apogee_qa_mission.exs [--offline]
#
# --offline skips the provider's validate and sync (they call the simulator over HTTP), for a dry
# run where the simulator isn't up. See docs/dev-environment.md.
Code.require_file("reflect_orbital/fixture.exs", __DIR__)
Code.require_file("seed/route_changes.exs", __DIR__)
Code.require_file("apogee_qa_mission/provider.exs", __DIR__)

defmodule Cadence.Dev.ApogeeQaMission do
  @moduledoc false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.{Actor, Artifact}
  alias Cadence.Dev.ApogeeQaMission.Provider
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F

  alias Cadence.Missions.Mission
  alias Cadence.{Repo, Spacecraft, SpacecraftType}

  @organization_id F.organization_id()
  @mission_id Provider.mission_id()
  # What differs between the two QA missions; fixed ids, so a rerun leaves what exists.
  @qa1 %{
    mission_id: @mission_id,
    slug: "qa-mission-23565",
    display_name: "QA mission 23565",
    profile_id: "profile-qa-23565",
    profile_name: "QA L10 profile",
    craft: "23565",
    catalog_id: "catalog-qa-l10-demo-copy",
    catalog_name: "qa-l10 demo copy"
  }
  # QA mission 2 (director's GO 11-18): lead saves 'direct' on it in the console; never seeded.
  @qa2 %{
    mission_id: "mission-qa-23566",
    slug: "qa-mission-23566",
    display_name: "QA mission 23566",
    profile_id: "profile-qa-23566",
    profile_name: "QA mission 23566 profile",
    craft: "23566",
    catalog_id: "catalog-qa-23566-demo-copy",
    catalog_name: "qa-23566 demo copy"
  }
  # Earendil holds SCIDs 1-500 (Fixture.spacecraft/0); mission 2's craft stays clear of them.
  @qa2_scid 601
  @token_key Provider.token_key()
  @personas ~w(qa-operator@example.com qa-second@example.com qa-org-admin@example.com qa-org-admin-2@example.com)
  @metadata Provider.metadata()

  def run(argv) do
    unless Code.ensure_loaded?(Mix) and Mix.env() == :dev,
      do: raise("The QA mission seed is for the development database only")

    offline? = "--offline" in argv

    unless offline? or present?(System.get_env(@token_key)),
      do:
        raise(
          "#{@token_key} is not set: run `mise run dev-secrets`, then this seed with mise exec"
        )

    Logger.configure(level: :warning)
    {:ok, _apps} = Application.ensure_all_started(:cadence)

    scope = admin_scope!()
    ensure_personas!()

    mission = ensure_mission(@qa1)
    profile = ensure_profile(@qa1)
    craft = Enum.map([1, 2], &ensure_spacecraft(@qa1, &1, &1, profile))
    Enum.each(craft, &ensure_decom(scope, @qa1, &1))
    revision = ensure_catalog(@qa1, scope.user.user_id)
    provider = Provider.ensure_provider(scope, offline?)
    routing = Provider.seed_route(hd(craft), profile.spacecraft_type_id)

    IO.puts("""

    QA mission ready: #{mission.display_name} (#{mission.slug}, #{mission.mission_id}).
    Spacecraft: #{Enum.map_join(craft, ", ", &"#{&1.display_name} (SCID #{&1.scid})")}; switches unset.
    Catalog: qa-l10 demo copy, revision #{revision.catalog_revision_id}; its model is a candidate.
    Provider: #{provider.display_name} (#{provider.provider_id})#{if offline?, do: ", not validated (--offline)", else: ", validated and synced"}.
    Local test station, TCP client and extra downlink: #{routing}.
    By hand in qa's slot: the first start (switches change set) and the model approval, each
    approved by a second admin.
    """)

    ensure_direct_mission(scope)
  end

  # QA mission 2: no approval override (lead saves 'direct' in the console), no provider,
  # transport or route; only what a model decision under 'direct' needs.
  defp ensure_direct_mission(scope) do
    mission = ensure_mission(@qa2)
    profile = ensure_profile(@qa2)
    craft = ensure_spacecraft(@qa2, 1, @qa2_scid, profile)
    ensure_decom(scope, @qa2, craft)
    revision = ensure_catalog(@qa2, scope.user.user_id)

    IO.puts("""
    QA mission 2 ready: #{mission.display_name} (#{mission.slug}, #{mission.mission_id}).
    Spacecraft: #{craft.display_name} (SCID #{craft.scid}); switches unset.
    Catalog: #{@qa2.catalog_name}, revision #{revision.catalog_revision_id}; its model is a candidate.
    No approval override: it reads 'independent' until lead saves 'direct' in the console.
    No provider, transport or route.
    """)
  end

  defp ensure_decom(scope, m, craft),
    do:
      ensure_installed(
        scope,
        HostContext.spacecraft(m.mission_id, craft.spacecraft_id),
        "telemetry_decom"
      )

  defp present?(value), do: is_binary(value) and value != ""

  # The environment's administrator, as the Earendil seed acts: an ordinary actor for the
  # provider and installation writes, never an approval or decision.
  defp admin_scope! do
    email = System.get_env("CADENCE_ADMIN_EMAIL") || raise "CADENCE_ADMIN_EMAIL is not set"
    {:ok, user} = Cadence.Accounts.fetch_user_by_email(email)

    {:ok, organization} =
      case Cadence.Organizations.fetch_organization(@organization_id) do
        {:ok, _} = found -> found
        _ -> raise "Run the Reflect Orbital seed first (dev/reflect_orbital_demo.exs)"
      end

    {:ok, membership} = Cadence.Accounts.fetch_user_membership(user.user_id, @organization_id)
    Scope.new(%{user: user, organization: organization, organization_membership: membership})
  end

  defp ensure_personas! do
    missing = Enum.reject(@personas, &match?({:ok, _}, Cadence.Accounts.fetch_user_by_email(&1)))

    if missing != [],
      do: raise("Run dev/apogee_qa_personas.exs first; missing: #{Enum.join(missing, ", ")}")
  end

  defp ensure_mission(m) do
    case Cadence.Missions.fetch_mission(@organization_id, m.mission_id) do
      {:ok, mission} ->
        mission

      {:error, _not_found} ->
        {:ok, mission} =
          Cadence.Missions.persist_mission(
            Mission.new(%{
              mission_id: m.mission_id,
              organization_id: @organization_id,
              slug: m.slug,
              display_name: m.display_name,
              metadata: @metadata
            })
          )

        mission
    end
  end

  defp ensure_profile(m) do
    case Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
           @organization_id,
           m.mission_id,
           m.profile_id
         ) do
      {:ok, profile} ->
        profile

      {:error, _not_found} ->
        {:ok, profile} =
          Cadence.SpacecraftTypeStore.persist_spacecraft_type(
            @organization_id,
            SpacecraftType.new(%{
              spacecraft_type_id: m.profile_id,
              mission_id: m.mission_id,
              display_name: m.profile_name,
              downlink_protocol: :tm,
              uplink_protocol: :tc,
              frame_parameters: %{
                "frame_size" => F.frame_size(),
                "ocf_length" => 0,
                "fecf" => false
              },
              applications: %{"telemetry_decom" => %{}},
              metadata: @metadata
            })
          )

        profile
    end
  end

  # Store-created, as Earendil's craft: no change set and no approval, switches unset (domain,
  # #109; lead 11-18).
  defp ensure_spacecraft(m, index, scid, profile) do
    id = "spacecraft-qa-#{m.craft}-#{index}"

    case Cadence.SpacecraftStore.fetch_spacecraft(@organization_id, m.mission_id, id) do
      {:ok, craft} ->
        craft

      {:error, _not_found} ->
        {:ok, craft} =
          Repo.transaction(fn ->
            {:ok, craft} =
              Cadence.SpacecraftStore.persist_spacecraft(
                @organization_id,
                Spacecraft.new(%{
                  spacecraft_id: id,
                  mission_id: m.mission_id,
                  display_name: "QA MISSION #{m.craft}-#{index}",
                  scid: scid,
                  spacecraft_type_id: profile.spacecraft_type_id,
                  spacecraft_type_version: profile.version,
                  metadata: @metadata
                })
              )

            {:ok, _source} =
              Cadence.SourceEndpoints.create_source_endpoint(@organization_id, m.mission_id, %{
                spacecraft_id: id,
                source_ref: craft.display_name,
                display_name: "#{craft.display_name} TT&C",
                metadata: @metadata
              })

            craft
          end)

        craft
    end
  end

  defp ensure_installed(scope, host, key) do
    case ApplicationInstallations.fetch(scope, host, key) do
      {:ok, %{lifecycle_state: :installed}} ->
        :ok

      _missing_or_disabled ->
        case ApplicationInstallations.install(scope, host, key, metadata: @metadata) do
          {:ok, _installation} -> :ok
          {:error, reason} -> raise "Installing #{key}: #{inspect(reason)}"
        end
    end
  end

  # Imported under the seed's own system actor (Cadence itself, Catalog.Actor), naming the person
  # who ran it (#513, MM-2): the environment's administrator this seed acts as. They count as the
  # model's importer, so under 'independent' the server refuses their approval of it; a second
  # admin approves (DECISIONS #113(4)). The seed still writes no approval decision or setting (#250).
  defp seed_actor(run_by),
    do: Actor.system("seed:apogee-qa-mission-v1", "QA mission seed", run_by)

  defp ensure_catalog(m, run_by) do
    case Catalog.fetch_database(@organization_id, m.mission_id, m.catalog_id) do
      {:ok, _} ->
        :ok

      {:error, :catalog_database_not_found} ->
        {:ok, _} =
          Catalog.create_database(@organization_id, m.mission_id, %{
            catalog_database_id: m.catalog_id,
            name: m.catalog_name,
            catalog_family: :combined,
            default_importer_key: "cadence_yaml",
            created_by: seed_actor(run_by),
            description: "The repository's demo_spacecraft.yaml, for #{m.display_name}.",
            metadata: @metadata
          })
    end

    case Catalog.list_revisions(@organization_id, m.mission_id, m.catalog_id) do
      [revision | _] -> revision
      [] -> import_revision(m, run_by)
    end
  end

  defp import_revision(m, run_by) do
    source = File.read!(F.database_path())
    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-qa-#{m.craft}-#{digest}",
        mission_id: m.mission_id,
        catalog_family: :combined,
        artifact_name: "demo_spacecraft.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: source,
        uploaded_by: seed_actor(run_by),
        metadata: @metadata
      })

    {:ok, run} =
      Catalog.start_revision_import(
        @organization_id,
        m.mission_id,
        m.catalog_id,
        artifact,
        "cadence_yaml",
        requested_by: seed_actor(run_by)
      )

    await_import(m, run.import_run_id, 240)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(@organization_id, m.mission_id, run.import_run_id)

    revision
  end

  defp await_import(_m, _id, 0), do: raise("Timed out importing demo_spacecraft.yaml")

  defp await_import(m, id, remaining) do
    {:ok, run} = Catalog.fetch_import_run(@organization_id, m.mission_id, id)

    case run.status do
      :completed ->
        :ok

      :failed ->
        raise "Catalog import failed: #{inspect(run.failure_reason)}"

      _running ->
        Process.sleep(500)
        await_import(m, id, remaining - 1)
    end
  end
end

Cadence.Dev.ApogeeQaMission.run(System.argv())
