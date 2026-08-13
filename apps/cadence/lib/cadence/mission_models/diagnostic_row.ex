defmodule Cadence.MissionModels.DiagnosticRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.{Canonical, Diagnostic}
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:diagnostic_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_diagnostics" do
    field(:revision_id, :string)
    field(:plan_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:code, :string)
    field(:severity, :string)
    field(:stage, :string)
    field(:target, :string)
    field(:semantic_id, :string)
    field(:support, :string)
    field(:diagnostic_document, :map)

    timestamps()
  end

  def changeset(revision, %Diagnostic{} = diagnostic, opts \\ []) do
    basis = {revision.revision_id, Keyword.get(opts, :plan_id), diagnostic}

    attrs = %{
      diagnostic_id: Canonical.content_id("mission_model_diagnostic", basis),
      revision_id: revision.revision_id,
      plan_id: Keyword.get(opts, :plan_id),
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      code: diagnostic.code,
      severity: Atom.to_string(diagnostic.severity),
      stage: Atom.to_string(diagnostic.stage),
      target: atom_string(diagnostic.target),
      semantic_id: diagnostic.semantic_id,
      support: atom_string(diagnostic.support),
      diagnostic_document: JsonDocument.wrap_value(diagnostic)
    }

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required([
      :diagnostic_id,
      :revision_id,
      :mission_id,
      :code,
      :severity,
      :stage,
      :diagnostic_document
    ])
  end

  defp atom_string(nil), do: nil
  defp atom_string(value), do: Atom.to_string(value)
end
