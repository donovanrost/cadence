defmodule Cadence.Repo.Migrations.DropFederationTables do
  use Ecto.Migration

  # #672: the federated application host is deleted, so are its tables: the frontend-release
  # publication store (objects, staged objects, artifacts, releases, catalog publications,
  # generations, bindings, activation requests and the activation control) and the federated
  # action idempotency ledger. Nothing reads them; no data moves, and an existing database is
  # dropped and reseeded. Children go before their parents; the guard functions go with the
  # triggers that used them.
  @tables ~w(
    federated_application_action_idempotencies
    frontend_release_activation_controls
    frontend_release_activation_requests
    frontend_release_catalog_bindings
    frontend_release_catalog_generations
    frontend_release_artifacts
    frontend_release_object_chunks
    frontend_release_objects
    frontend_release_staged_object_chunks
    frontend_release_staged_objects
    frontend_release_publications
    frontend_release_catalog_publications
  )a

  @functions ~w(
    cadence_enforce_frontend_release_artifact_size_cap
    cadence_guard_frontend_release_activation_control
    cadence_reject_frontend_release_publication_mutation
    cadence_require_frontend_release_catalog_generation
  )

  def up do
    Enum.each(@tables, &drop(table(&1)))
    Enum.each(@functions, &execute("DROP FUNCTION #{&1}()"))
  end

  def down do
    raise Ecto.MigrationError,
          "the federated application host is deleted (#672); its tables cannot be restored"
  end
end
