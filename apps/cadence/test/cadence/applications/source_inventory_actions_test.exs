defmodule Cadence.Applications.SourceInventoryActionsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.OpsConsole.Actions.SourceInventoryActions, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Jobs
  alias Cadence.Management.DataSources, as: Definitions
  alias Cadence.Management.DataSources.Credentials
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.Sources, as: Read
  @org "org-native-sources"
  @mission "mission-native-sources"

  setup do
    %{organization: org} = persist_mission_scope(@org, @mission)
    %{reader: scope(org, :member), admin: scope(org, :organization_admin)}
  end

  test "registration validates without writes, requires confirmation and returns persisted identities",
       c do
    capture = capture(c.admin, "registration")

    input = %{
      "params" => %{"source" => registration("new-source")},
      "review" => %{},
      "confirmed" => false
    }

    assert {:ok, %{valid: true}} =
             execute(c.admin, "registration", capture, "validate-registration", input)

    assert {:error, :data_source_not_found} = Definitions.fetch_data_source("new-source")

    assert {:rejected, ["confirmation_required"]} =
             execute(c.admin, "registration", capture, "register-source", input)

    assert {:ok, receipt} =
             execute(c.admin, "registration", capture, "register-source", %{
               input
               | "confirmed" => true
             })

    assert receipt.source_id == "new-source"
    assert receipt.actor_id == c.admin.user.user_id
    assert receipt.result["dataSourceId"] == "new-source"
    assert {:ok, source} = Definitions.fetch_data_source("new-source")
    assert receipt.event_ids == [source.current_event_id]

    [event] =
      Definitions.list_data_source_events(@org, @mission, data_source_id: source.data_source_id)

    assert event.actor_id == c.admin.user.user_id
    assert event.payload["idempotency_key"] == receipt.operation_id

    assert {:rejected, _} =
             execute(c.admin, "registration", capture, "register-source", %{
               input
               | "confirmed" => true
             })

    assert length(
             Definitions.list_data_source_events(@org, @mission,
               data_source_id: source.data_source_id
             )
           ) == 1
  end

  test "source controls bind administrator mode, subject and current descriptor", c do
    source("first")
    source("other")
    old = capture(c.admin, "settings", "first")
    input = source_input(old, "first")
    assert {:ok, receipt} = execute(c.admin, "settings", old, "disable-source", input)
    assert receipt.result["status"] == "disabled"
    assert {:rejected, _} = execute(c.admin, "settings", old, "enable-source", input)
    fresh = capture(c.admin, "settings", "first")

    assert {:rejected, _} =
             execute(c.admin, "settings", fresh, "disable-source", source_input(fresh, "other"))

    reader = capture(c.reader, "reader", "first")

    assert {:rejected, _} =
             execute(c.reader, "reader", reader, "enable-source", source_input(reader, "first"))

    assert {:ok, _} =
             execute(c.admin, "settings", fresh, "enable-source", source_input(fresh, "first"))

    assert {:ok, %{status: :active}} = Definitions.fetch_data_source("first")
    assert {:ok, %{status: :active}} = Definitions.fetch_data_source("other")
  end

  test "binding changes pin both reviewed binding and destination source", c do
    source("origin")
    target = source("target")

    assert {:ok, binding} =
             Definitions.persist_data_binding(%DataBinding{
               binding_id: "binding",
               organization_id: @org,
               mission_id: @mission,
               logical_source: :telemetry,
               realm: :flight,
               data_source_id: "origin"
             })

    old = capture(c.admin, "settings", "origin")

    input = %{
      "params" => %{
        "binding" => %{"binding_id" => binding.binding_id, "data_source_id" => "target"}
      },
      "review" => %{
        "source" => old.model.selected.source.evidence,
        "binding" => hd(old.model.bindings.entries).evidence,
        "target_source" => Read.source_evidence(target)
      },
      "confirmed" => true
    }

    assert {:ok, result} = execute(c.admin, "settings", old, "change-binding", input)
    assert result.result["bindingId"] == binding.binding_id
    assert {:ok, changed} = Definitions.fetch_data_binding(binding.binding_id)
    assert changed.data_source_id == "target"
    assert changed.binding_version > binding.binding_version
    assert result.event_ids == [changed.current_event_id]
    assert {:rejected, _} = execute(c.admin, "settings", old, "change-binding", input)
  end

  test "credential rotation changes source evidence and rejects a stale second rotation", c do
    assert {:ok, _, _} =
             Credentials.register_reference(%{
               credentials_ref: "source-credential",
               organization_id: @org,
               mission_id: @mission,
               data_source_id: "secured",
               owner: :cadence,
               kind: :managed_tsdb_connection,
               provider: "questdb"
             })

    source("secured", credentials_ref: "source-credential")
    old = capture(c.admin, "settings", "secured")

    input =
      source_input(old, "secured") |> put_in(["params", "credentials-ref"], "source-credential")

    assert {:ok, receipt} = execute(c.admin, "settings", old, "rotate-source-credential", input)
    assert {:ok, reference} = Credentials.fetch_reference("source-credential")
    assert reference.credential_version == 2
    assert receipt.event_ids == [reference.current_event_id]
    assert {:rejected, _} = execute(c.admin, "settings", old, "rotate-source-credential", input)
    assert {:ok, %{credential_version: 2}} = Credentials.fetch_reference("source-credential")
  end

  test "deployment retry returns the actual reviewed job and cannot reuse stale state", c do
    source("deployment")

    assert {:ok, job} =
             Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "source-deployment", %{
               organization_id: @org,
               mission_id: @mission,
               data_source_id: "deployment",
               operation: "provision"
             })

    assert [_] = Jobs.claim_jobs(1)
    assert {:ok, _} = Jobs.fail_worker_start(job.job_id, :provision_failed)
    old = capture(c.admin, "settings", "deployment")

    input = %{
      "params" => %{"job-id" => job.job_id},
      "review" => %{
        "source" => old.model.selected.source.evidence,
        "job" => hd(old.model.selected.jobs.entries).evidence
      },
      "confirmed" => true
    }

    assert {:ok, receipt} = execute(c.admin, "settings", old, "retry-deployment-run", input)
    assert receipt.result["jobId"] == job.job_id
    assert receipt.result["runId"] == job.run_id
    assert {:ok, %{status: :queued}} = Jobs.fetch_job(job.job_id)
    assert {:rejected, _} = execute(c.admin, "settings", old, "retry-deployment-run", input)
  end

  test "read pages preserve scoped context and malformed authority never writes", c do
    source("visible")
    old = capture(c.admin, "settings", "visible")

    assert {:page, model, _, _} =
             execute(c.admin, "settings", old, "read-page", %{
               "query" => %{"data_source_id" => "visible", "events_page" => "2"}
             })

    assert model.selected.events.page == 2
    assert model.context == %{organization_id: @org, mission_id: @mission}

    for input <- [
          source_input(old, "visible") |> put_in(["review", "source"], "forged"),
          source_input(old, "visible") |> put_in(["params", "organization_id"], "foreign"),
          source_input(old, "visible") |> Map.put("confirmed", "true")
        ] do
      assert {:rejected, _} = execute(c.admin, "settings", old, "disable-source", input)
    end

    assert {:ok, %{status: :active}} = Definitions.fetch_data_source("visible")

    bad_registration = %{
      "params" => %{"source" => registration(String.duplicate("x", 241))},
      "review" => %{},
      "confirmed" => true
    }

    assert {:rejected, _} =
             execute(
               c.admin,
               "registration",
               capture(c.admin, "registration"),
               "register-source",
               bad_registration
             )
  end

  test "unsupported backend lifecycle operations are rejected before any effect", c do
    source = source("managed")
    old = capture(c.admin, "settings", source.data_source_id)

    for action <- ["provision-tsdb-backend", "reconcile-tsdb-backend", "deprovision-tsdb-backend"] do
      assert {:rejected, _} =
               execute(c.admin, "settings", old, action, source_input(old, source.data_source_id))
    end

    assert {:ok, unchanged} = Definitions.fetch_data_source(source.data_source_id)
    assert unchanged.current_event_id == source.current_event_id
    assert Jobs.source_deployment_page(@org, @mission, source.data_source_id, 1).entries == []
  end

  test "requeue requires a running reviewed job and returns its persisted queued identity", c do
    source("requeue")

    assert {:ok, job} =
             Jobs.enqueue(:tsdb_backend_lifecycle, @mission, "source-requeue", %{
               organization_id: @org,
               mission_id: @mission,
               data_source_id: "requeue",
               operation: "provision"
             })

    queued = capture(c.admin, "settings", "requeue")

    assert {:rejected, _} =
             execute(
               c.admin,
               "settings",
               queued,
               "requeue-deployment-run",
               job_input(queued, job.job_id)
             )

    assert [_] = Jobs.claim_jobs(1)
    running = capture(c.admin, "settings", "requeue")
    input = job_input(running, job.job_id)
    assert {:rejected, _} = execute(c.admin, "settings", running, "retry-deployment-run", input)
    assert {:ok, receipt} = execute(c.admin, "settings", running, "requeue-deployment-run", input)
    assert receipt.result["jobId"] == job.job_id
    assert receipt.result["runId"] == job.run_id
    assert {:ok, %{status: :queued}} = Jobs.fetch_job(job.job_id)
    assert {:rejected, _} = execute(c.admin, "settings", running, "requeue-deployment-run", input)
  end

  defp job_input(capture, job_id),
    do: %{
      "params" => %{"job-id" => job_id},
      "review" => %{
        "source" => capture.model.selected.source.evidence,
        "job" => hd(capture.model.selected.jobs.entries).evidence
      },
      "confirmed" => true
    }

  defp source_input(capture, id),
    do: %{
      "params" => %{"data-source-id" => id},
      "review" => %{"source" => capture.model.selected.source.evidence},
      "confirmed" => true
    }

  defp execute(scope, mode, capture, action, input),
    do: Actions.execute(scope, @mission, mode, capture, action, input, Ecto.UUID.generate())

  defp capture(scope, mode, source \\ nil) do
    assert {:ok, model, review} = Read.load(scope, @mission, mode, %{"data_source_id" => source})
    %{model: model, review: review}
  end

  defp source(id, attrs \\ []) do
    assert {:ok, source} =
             Definitions.persist_data_source(
               struct!(
                 %DataSource{
                   data_source_id: id,
                   organization_id: @org,
                   mission_id: @mission,
                   isolation_level: :mission_isolated,
                   adapter: :telemetry
                 },
                 attrs
               )
             )

    source
  end

  defp registration(id),
    do: %{
      "data_source_id" => id,
      "logical_source" => "telemetry",
      "kind" => "managed_tsdb",
      "isolation_level" => "mission_isolated",
      "credentials_ref" => "",
      "credential_provider" => "",
      "endpoint_ref" => "",
      "material_env_profile" => "",
      "http_endpoint_env" => "",
      "storage" => "questdb"
    }

  defp scope(org, role) do
    user =
      User.new(%{
        user_id: "source-action-user-#{role}",
        email: "#{role}@example.test",
        display_name: "Source operator"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization: org,
      organization_id: org.organization_id,
      organization_membership: membership
    })
  end
end
