defmodule Cadence.Persistence.Schemas.ReplayRunRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Replay.Run

  @primary_key {:replay_run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "replay_runs" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:status, :string)
    field(:replayed_evidence_count, :integer)
    field(:replayed_packet_count, :integer)
    field(:replayed_sample_count, :integer)
    field(:failure_reason, :map)
    field(:metadata, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :replay_run_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :status,
    :replayed_evidence_count,
    :replayed_packet_count,
    :replayed_sample_count,
    :started_at
  ]

  @spec changeset(Run.t()) :: Ecto.Changeset.t()
  def changeset(%Run{} = run) do
    changeset(%__MODULE__{}, run)
  end

  @spec changeset(struct(), Run.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = replay_run_row, %Run{} = run) do
    replay_run_row
    |> cast(domain_attrs(run), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Run.t()
  def to_domain(%__MODULE__{} = replay_run_row) do
    %Run{
      replay_run_id: replay_run_row.replay_run_id,
      mission_id: replay_run_row.mission_id,
      binding_set_id: replay_run_row.binding_set_id,
      binding_set_version: replay_run_row.binding_set_version,
      status: String.to_existing_atom(replay_run_row.status),
      replayed_evidence_count: replay_run_row.replayed_evidence_count,
      replayed_packet_count: replay_run_row.replayed_packet_count,
      replayed_sample_count: replay_run_row.replayed_sample_count,
      failure_reason: JsonDocument.unwrap_value(replay_run_row.failure_reason),
      started_at: replay_run_row.started_at,
      completed_at: replay_run_row.completed_at,
      metadata: replay_run_row.metadata
    }
  end

  defp domain_attrs(%Run{} = run) do
    %{
      replay_run_id: run.replay_run_id,
      mission_id: run.mission_id,
      binding_set_id: run.binding_set_id,
      binding_set_version: run.binding_set_version,
      status: Atom.to_string(run.status),
      replayed_evidence_count: run.replayed_evidence_count,
      replayed_packet_count: run.replayed_packet_count,
      replayed_sample_count: run.replayed_sample_count,
      failure_reason: maybe_wrap_failure_reason(run.failure_reason),
      metadata: JsonDocument.encode(run.metadata),
      started_at: run.started_at,
      completed_at: run.completed_at
    }
  end

  defp all_fields do
    [
      :replay_run_id,
      :mission_id,
      :binding_set_id,
      :binding_set_version,
      :status,
      :replayed_evidence_count,
      :replayed_packet_count,
      :replayed_sample_count,
      :failure_reason,
      :metadata,
      :started_at,
      :completed_at
    ]
  end

  defp maybe_wrap_failure_reason(nil), do: nil
  defp maybe_wrap_failure_reason(reason), do: JsonDocument.wrap_value(reason)
end
