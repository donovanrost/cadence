defmodule Cadence.ContactPlanning.PlanSubmissions do
  @moduledoc """
  The rounds of a contact plan's review (U36, qa #40): one record per submit, with the version
  submitted, its actor, an optional note for the reviewer, whether the version was cut
  unchanged after a send back, and the gap acknowledgements the author gave. Append-only.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Repo

  @primary_key {:contact_plan_submission_id, :string, autogenerate: false}
  schema "contact_plan_submissions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:round, :integer)
    field(:actor_document, :map)
    field(:note, :string)
    field(:unchanged, :boolean, default: false)
    field(:acknowledgements_document, {:array, :map}, default: [])
    # The approval policy in force at submit (M2). Since #257 a submit never approves; the
    # approval is its own decision, which records the policy it was made under.
    field(:policy_document, :map)
    field(:submitted_at, :utc_datetime_usec)
  end

  @doc "Records the next round for the plan."
  @spec record(map()) :: {:ok, struct()} | {:error, term()}
  def record(attrs) do
    round = latest_round(attrs.organization_id, attrs.mission_id, attrs.contact_plan_id) + 1

    %__MODULE__{
      contact_plan_submission_id: Cadence.Ids.new("contact_plan_submission"),
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      contact_plan_id: attrs.contact_plan_id,
      contact_plan_version: attrs.contact_plan_version,
      round: round,
      actor_document: attrs.actor_document,
      note: attrs[:note],
      unchanged: attrs[:unchanged] || false,
      acknowledgements_document: attrs[:acknowledgements] || [],
      policy_document: ActivationPolicy.evidence(attrs.organization_id, attrs.mission_id),
      submitted_at: DateTime.utc_now()
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:round,
      name: :contact_plan_submissions_round_index
    )
    |> Repo.insert()
  end

  @doc "The plan's rounds, newest first."
  @spec list(binary(), binary(), binary()) :: [struct()]
  def list(organization_id, mission_id, plan_id) do
    __MODULE__
    |> where(
      [s],
      s.organization_id == ^organization_id and s.mission_id == ^mission_id and
        s.contact_plan_id == ^plan_id
    )
    |> order_by([s], desc: s.round)
    |> Repo.all()
  end

  defp latest_round(organization_id, mission_id, plan_id) do
    __MODULE__
    |> where(
      [s],
      s.organization_id == ^organization_id and s.mission_id == ^mission_id and
        s.contact_plan_id == ^plan_id
    )
    |> select([s], max(s.round))
    |> Repo.one()
    |> Kernel.||(0)
  end
end
