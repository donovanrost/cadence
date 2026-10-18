defmodule Cadence.Reads.Catalog.Artifacts do
  @moduledoc false

  import Cadence.Reads.Catalog.Presentation

  alias Cadence.Catalog

  def catalog_artifact_show(organization_id, mission_id, params) do
    with {:ok, artifact_id} <- subject_id(params, "artifact_id"),
         {:ok, artifact} <- Catalog.fetch_artifact(organization_id, mission_id, artifact_id) do
      runs = Catalog.list_import_runs(organization_id, mission_id, artifact_id: artifact_id)

      {:ok,
       %{
         "presentation" => %{
           "root" => %{"attrs" => %{"id" => "catalog-artifact-show-page", "class" => "space-y-6"}},
           "header" => artifact_header(mission_id, artifact),
           "child_wrapper" => %{"attrs" => %{"id" => "catalog-artifact-show-component"}},
           "artifact_show" => %{
             "artifact" => %{
               "format_key" => artifact.format_key,
               "media_type" => artifact.media_type || "—",
               "content_sha256" => artifact.content_sha256,
               "uploaded_at" => format_datetime(artifact.uploaded_at),
               "download_href" =>
                 "/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
             },
             "runs" => Enum.map(runs, &artifact_run_row(&1, mission_id))
           }
         }
       }}
    end
  end

  defp artifact_run_row(run, mission_id),
    do: %{
      "id" => "catalog-artifact-run-#{run.import_run_id}",
      "actions_id" => "#{run.import_run_id}-actions",
      "status" => import_status_tone(run.status),
      "status_label" => import_status_label(run.status),
      "started_at" => format_short_datetime(run.started_at),
      "completed_at" => format_short_datetime(run.completed_at) || "—",
      "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }

  defp artifact_header(mission_id, artifact),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{}},
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => %{
        "attrs" => %{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        },
        "items" => [
          %{
            "key" => "mission",
            "separator" => nil,
            "link" => %{"attrs" => navigate_attrs(mission_href(mission_id)), "text" => "Mission"},
            "current" => nil
          },
          %{
            "key" => "catalog",
            "separator" => separator(),
            "link" => %{
              "attrs" => navigate_attrs("/missions/#{mission_id}/catalog"),
              "text" => "Catalog"
            },
            "current" => nil
          },
          %{
            "key" => "artifact",
            "separator" => separator(),
            "link" => nil,
            "current" => %{
              "attrs" => %{"class" => "text-primary/90"},
              "text" => artifact.artifact_name
            }
          }
        ]
      },
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => artifact.artifact_name
      }
    }
end
