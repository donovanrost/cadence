defmodule Cadence.GroupReleaseFixtures do
  @moduledoc """
  A mission whose targets can really be released to (SCID'd spacecraft, a NOOP catalog, their own
  uplink path and gateway), and armed command groups on it (U46 group release).
  """

  alias Cadence.Catalog.Artifact

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.CommandMemberFixtures
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Ids
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @org "org-group-release"
  @mission "mission-group-release"
  @at ~U[2026-11-14 07:20:00Z]

  def org, do: @org
  def mission, do: @mission
  def at, do: @at

  # A queued group (approved; members queued in order) with one NOOP member per target listed.
  def armed_group!(c, targets) do
    id = Ids.new("command_group_release")

    {:ok, _group} =
      GroupStore.insert_group(
        CommandGroup.new(%{
          command_group_id: id,
          organization_id: @org,
          mission_id: @mission,
          state: :queued,
          title: "Release test",
          requested_by: %{"actor_kind" => "user", "user_id" => "requester"},
          requested_at: @at,
          resolved_at: @at,
          member_count: length(targets)
        })
      )

    entries =
      targets
      |> Enum.with_index()
      |> Enum.map(fn {endpoint, index} ->
        target_index = Enum.find_index(Enum.uniq(targets), &(&1 == endpoint))
        position = Enum.count(Enum.take(targets, index), &(&1 == endpoint))

        %{queue_entry: entry} =
          CommandMemberFixtures.queued!(
            @org,
            @mission,
            CommandRequest.new(%{
              mission_id: @mission,
              source_endpoint_ref: endpoint.source_endpoint_id,
              mission_model_revision_id: c.model.revision_id,
              command_id: Cadence.MissionModelFixtures.command_id!(c.model, "NOOP"),
              priority: 3,
              requested_by: %{"user_id" => "requester"}
            }),
            group: id,
            target_index: target_index,
            position: position,
            enqueued_by: %{"user_id" => "approver"}
          )

        entry.command_queue_entry_id
      end)

    %{id: id, entries: entries}
  end

  def persist_target!(name, scid) do
    spacecraft_id = "spacecraft-" <> name

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{
          spacecraft_id: spacecraft_id,
          mission_id: @mission,
          display_name: name,
          scid: scid
        })
      )

    {:ok, endpoint} =
      Cadence.SourceEndpointFixtures.persist(
        @org,
        SourceEndpoint.new(%{
          source_endpoint_id: "source-endpoint-" <> name,
          mission_id: @mission,
          spacecraft_id: spacecraft_id,
          source_ref: String.upcase(name),
          display_name: name
        })
      )

    Map.put(endpoint, :scid, scid)
  end

  # The target's own uplink (its path, its gateway SCID), started. With a window it's a booked
  # pass; without one, a hand-started contact.
  def uplink_contact!(endpoint, window \\ nil) do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    paths = [
      Path.new(%{
        path_id: "uplink-path-" <> suffix,
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: endpoint.source_endpoint_id,
        transport_bindings: [
          TransportBinding.new(%{
            transport_binding_id: "uplink-gateway-" <> suffix,
            family_key: :uplink_gateway,
            target_scope: :path,
            configuration: %{"service_name" => "gateway", "scid" => endpoint.scid}
          })
        ]
      })
    ]

    contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-contact-group-" <> suffix,
        organization_id: @org,
        mission_id: @mission,
        scheduled_contact_id: scheduled!(endpoint, paths, window, suffix),
        source_endpoint_refs: [endpoint.source_endpoint_id],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_400_000, :second),
        paths: paths
      })

    {:ok, _} = Cadence.Contacts.persist_realized_contact(@org, contact)

    {:ok, _pid} =
      Cadence.Contacts.start_realized_contact(@org, @mission, contact.realized_contact_id)

    contact
  end

  defp scheduled!(_endpoint, _paths, nil, _suffix), do: nil

  defp scheduled!(endpoint, paths, {starts_at, ends_at}, suffix) do
    id = "scheduled-group-" <> suffix

    {:ok, _} =
      Cadence.Contacts.persist_scheduled_contact(
        @org,
        ScheduledContact.new(%{
          scheduled_contact_id: id,
          mission_id: @mission,
          source_endpoint_refs: [endpoint.source_endpoint_id],
          starts_at: starts_at,
          ends_at: ends_at,
          paths: paths
        })
      )

    id
  end

  def import_noop_model! do
    {:ok, artifact} =
      Cadence.Catalog.persist_artifact(
        @org,
        Artifact.new(%{
          artifact_id: "artifact-group-release",
          organization_id: @org,
          mission_id: @mission,
          catalog_family: :combined,
          artifact_name: "group-release.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: """
          version: "1.0.0"

          commands:
            - name: NOOP
              opcode: 0x01
              parameters: []
          """,
          uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
        })
      )

    {:ok, run} =
      Cadence.Catalog.start_import_run(@org, @mission, artifact.artifact_id, "cadence_yaml",
        requested_by: %{"service_identity_id" => "svc-bootstrap"}
      )

    {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, run.import_run_id)
    _claimed = Cadence.Jobs.claim_jobs(1)
    {:ok, %{status: :completed}} = JobRunner.run_job(job.job_id)
    {:ok, completed} = Cadence.Catalog.fetch_import_run(@org, @mission, run.import_run_id)

    Cadence.MissionModelFixtures.activate_imported_model!(
      @org,
      @mission,
      completed.result_document
    )
  end
end
