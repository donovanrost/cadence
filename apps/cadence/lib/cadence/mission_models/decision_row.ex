defmodule Cadence.MissionModels.DecisionRow do
  @moduledoc """
  A mission-model decision record (E2, #546): today only `withdrawn`, an approval taken back.
  Append-only (`DecisionRecord.tables/0`; database triggers refuse UPDATE, DELETE and TRUNCATE).
  Approvals and rejections join it later (#878).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:decision_id, :string, autogenerate: false}
  schema "mission_model_decisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:revision_id, :string)
    field(:composition_id, :string)
    field(:decision, :string)
    field(:actor, :map)
    field(:reason, :string)
    field(:subject, :map)
    field(:policy_document, :map)
    field(:admin_mode, :boolean)
    field(:operation_id, :string)
    field(:decided_at, :utc_datetime_usec)
  end
end
