defmodule CadenceWeb.ControlPlaneCatalogApiTest do
  use CadenceWeb.ConnCase, async: true

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner

  test "authenticated mission API manages catalog artifacts and import runs", %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    importers_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/catalog/importers")

    assert %{"data" => importers} = json_response(importers_conn, 200)

    assert %{"catalog_family" => "combined", "importer_version" => 2} =
             Enum.find(importers, &(&1["importer_key"] == "cadence_yaml"))

    artifact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts",
        %{
          "catalog_artifact" => %{
            "artifact_id" => "artifact-alpha",
            "catalog_family" => "combined",
            "artifact_name" => "mission-alpha-command.yaml",
            "format_key" => "cadence_yaml",
            "media_type" => "application/yaml",
            "source_artifact" => %{
              "yaml" => """
              commands:
                - name: NOOP
                  opcode: 1
                - name: RESET
                  opcode: 2
              """
            }
          }
        }
      )

    assert %{
             "data" => %{
               "artifact_id" => "artifact-alpha",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "catalog_family" => "combined",
               "format_key" => "cadence_yaml",
               "content_sha256" => content_sha256,
               "uploaded_by" => %{
                 "service_identity_id" => "svc-bootstrap"
               }
             }
           } = json_response(artifact_conn, 201)

    assert is_binary(content_sha256)
    assert content_sha256 != ""

    listed_artifacts_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts?catalog_family=combined"
      )

    assert %{
             "data" => [
               %{
                 "artifact_id" => "artifact-alpha",
                 "catalog_family" => "combined"
               }
             ]
           } = json_response(listed_artifacts_conn, 200)

    import_run_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs",
        %{
          "catalog_import_run" => %{
            "artifact_id" => "artifact-alpha",
            "importer_key" => "cadence_yaml",
            "importer_version" => 2,
            "metadata" => %{"reason" => "bootstrap"}
          }
        }
      )

    assert %{
             "data" => %{
               "import_run_id" => import_run_id,
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "artifact_id" => "artifact-alpha",
               "importer_key" => "cadence_yaml",
               "importer_version" => 2,
               "status" => "running",
               "requested_by" => %{
                 "service_identity_id" => "svc-bootstrap"
               }
             }
           } = json_response(import_run_conn, 201)

    assert [{:ok, claimed_job}] =
             Jobs.claim_jobs(1)
             |> Enum.map(fn job -> {:ok, job} end)

    assert {:ok, _completed_job} = JobRunner.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "import_run_id" => ^import_run_id,
               "status" => "completed",
               "diagnostics" => [],
               "result_document" => %{
                 "mission_model" => %{
                   "revision_id" => mission_model_revision_id
                 },
                 "import_run_id" => ^import_run_id
               }
             }
           } = json_response(import_run_show_conn, 200)

    assert is_binary(mission_model_revision_id)

    listed_import_runs_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs?status=completed&artifact_id=artifact-alpha"
      )

    assert %{
             "data" => [
               %{
                 "import_run_id" => ^import_run_id,
                 "status" => "completed",
                 "artifact_id" => "artifact-alpha"
               }
             ]
           } = json_response(listed_import_runs_conn, 200)
  end
end
