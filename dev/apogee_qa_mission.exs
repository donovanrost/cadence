# Apogee QA mission (development only; #231, dev reset DECISIONS #112).
#
# Builds the QA mission on a fresh dev database through the product's own store and context
# functions, the way dev/reflect_orbital/seed.exs builds Earendil (no Repo inserts):
#
#   - the mission qa-mission-23565 ("QA mission 23565") in the Reflect Orbital organization; it
#     inherits the organization's approval policy (no governance setting is written);
#   - the profile "QA L10 profile" and two spacecraft, QA MISSION 23565-1 and -2 (SCID 1 and 2),
#     each with a source endpoint and Telemetry Decom installed (Communications is a platform app,
#     on every mission already);
#   - the catalog "qa-l10 demo copy" (demo_spacecraft.yaml) imported under the seed's own system
#     actor, never a person, so its mission model is a CANDIDATE any admin may approve;
#   - a QA provider on the dev simulator: credential (the env variable named, never its value),
#     account, grant to the QA mission, mission provider, then validate and sync;
#   - one direct TCP-client transport and one downlink routing rule to 23565-1.
#
# Nothing here is a decision. The spacecraft's telemetry and commanding switches stay UNSET
# (off): qa's slot does the first start by hand (a change set, approved by a second admin), and a
# second admin approves the mission model in the console. No spacecraft configuration is saved.
#
# Rerunnable: every record has a fixed id, and what exists is left as it is.
#
# Run after the Reflect Orbital seed and the QA personas, with the dev secrets in the environment
# (mise), while :4011 is down or against a scratch database:
#
#   cd apps/cadence_web
#   mise exec -- mix run --no-start ../../dev/apogee_qa_mission.exs [--offline]
#
# --offline skips the provider's validate and sync (they call the simulator over HTTP), for a dry
# run where the simulator isn't up. See docs/apogee/qa/runbook.md.
Code.require_file("reflect_orbital/fixture.exs", __DIR__)
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
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.{Repo, Spacecraft, SpacecraftType}

  @organization_id F.organization_id()
  @mission_id Provider.mission_id()
  @profile_id "profile-qa-23565"
  @catalog_id "catalog-qa-l10-demo-copy"
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

    mission = ensure_mission()
    profile = ensure_profile()
    craft = Enum.map([1, 2], &ensure_spacecraft(&1, profile))

    Enum.each(craft, fn c ->
      ensure_installed(
        scope,
        HostContext.spacecraft(@mission_id, c.spacecraft_id),
        "telemetry_decom"
      )
    end)

    revision = ensure_catalog()
    provider = Provider.ensure_provider(scope, offline?)
    transport = Provider.ensure_direct_transport()
    Provider.ensure_route(hd(craft), transport)

    IO.puts("""

    QA mission ready: #{mission.display_name} (#{mission.slug}, #{mission.mission_id}).
    Spacecraft: #{Enum.map_join(craft, ", ", &"#{&1.display_name} (SCID #{&1.scid})")}; switches unset.
    Catalog: qa-l10 demo copy, revision #{revision.catalog_revision_id}; its model is a candidate.
    Provider: #{provider.display_name} (#{provider.provider_id})#{if offline?, do: ", not validated (--offline)", else: ", validated and synced"}.
    Direct transport #{transport.transport_id} and one routing rule to #{hd(craft).display_name}.
    By hand in qa's slot: the first start (switches change set) and the model approval, each
    approved by a second admin.
    """)
  end

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

  defp ensure_mission do
    case Cadence.Missions.fetch_mission(@organization_id, @mission_id) do
      {:ok, mission} ->
        mission

      {:error, _not_found} ->
        {:ok, mission} =
          Cadence.Missions.persist_mission(
            Mission.new(%{
              mission_id: @mission_id,
              organization_id: @organization_id,
              slug: "qa-mission-23565",
              display_name: "QA mission 23565",
              metadata: @metadata
            })
          )

        mission
    end
  end

  defp ensure_profile do
    case Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
           @organization_id,
           @mission_id,
           @profile_id
         ) do
      {:ok, profile} ->
        profile

      {:error, _not_found} ->
        {:ok, profile} =
          Cadence.SpacecraftTypeStore.persist_spacecraft_type(
            @organization_id,
            SpacecraftType.new(%{
              spacecraft_type_id: @profile_id,
              mission_id: @mission_id,
              display_name: "QA L10 profile",
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
  defp ensure_spacecraft(index, profile) do
    id = "spacecraft-qa-23565-#{index}"

    case Cadence.SpacecraftStore.fetch_spacecraft(@organization_id, @mission_id, id) do
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
                  mission_id: @mission_id,
                  display_name: "QA MISSION 23565-#{index}",
                  scid: index,
                  spacecraft_type_id: profile.spacecraft_type_id,
                  spacecraft_type_version: profile.version,
                  metadata: @metadata
                })
              )

            {:ok, _source} =
              Cadence.SourceEndpoints.persist_source_endpoint(
                @organization_id,
                SourceEndpoint.new(%{
                  source_endpoint_id: "source-#{id}",
                  mission_id: @mission_id,
                  spacecraft_id: id,
                  source_ref: craft.display_name,
                  display_name: "#{craft.display_name} TT&C",
                  metadata: @metadata
                })
              )

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

  # Imported under the seed's own system actor (Cadence itself, Catalog.Actor), never a person:
  # an importer can't approve the model under the independent policy, and no person ran this.
  defp seed_actor, do: Actor.system("seed:apogee-qa-mission-v1", "QA mission seed")

  defp ensure_catalog do
    case Catalog.fetch_database(@organization_id, @mission_id, @catalog_id) do
      {:ok, _} ->
        :ok

      {:error, :catalog_database_not_found} ->
        {:ok, _} =
          Catalog.create_database(@organization_id, @mission_id, %{
            catalog_database_id: @catalog_id,
            name: "qa-l10 demo copy",
            catalog_family: :combined,
            default_importer_key: "cadence_yaml",
            created_by: seed_actor(),
            description: "The repository's demo_spacecraft.yaml, for the QA mission.",
            metadata: @metadata
          })
    end

    case Catalog.list_revisions(@organization_id, @mission_id, @catalog_id) do
      [revision | _] -> revision
      [] -> import_revision()
    end
  end

  defp import_revision do
    source = File.read!(F.database_path())
    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-qa-23565-#{digest}",
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "demo_spacecraft.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: source,
        uploaded_by: seed_actor(),
        metadata: @metadata
      })

    {:ok, run} =
      Catalog.start_revision_import(
        @organization_id,
        @mission_id,
        @catalog_id,
        artifact,
        "cadence_yaml",
        requested_by: seed_actor()
      )

    await_import(run.import_run_id, 240)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(@organization_id, @mission_id, run.import_run_id)

    revision
  end

  defp await_import(_id, 0), do: raise("Timed out importing demo_spacecraft.yaml")

  defp await_import(id, remaining) do
    {:ok, run} = Catalog.fetch_import_run(@organization_id, @mission_id, id)

    case run.status do
      :completed ->
        :ok

      :failed ->
        raise "Catalog import failed: #{inspect(run.failure_reason)}"

      _running ->
        Process.sleep(500)
        await_import(id, remaining - 1)
    end
  end
end

Cadence.Dev.ApogeeQaMission.run(System.argv())
