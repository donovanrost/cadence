defmodule Cadence.Commanding.Groups.CommandGroupRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.Groups.CommandGroup
  alias Cadence.Persistence.JsonDocument

  @primary_key {:command_group_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  @documents ~w(requested_by target_query targets commands release basis policy preflight
                decided_by decision aborted_by abort_result)a

  schema "command_groups" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:state, :string)
    field(:title, :string)
    field(:log_entry, :string)
    field(:requested_by_document, :map, default: %{})
    field(:requested_at, :utc_datetime_usec)
    field(:requested_approver_user_id, :string)
    field(:operation_id, :string)
    field(:sent_back_from, :string)
    field(:target_query_document, :map, default: %{})
    field(:targets_document, :map, default: %{})
    field(:resolved_at, :utc_datetime_usec)
    field(:commands_document, :map, default: %{})
    field(:release_document, :map, default: %{})
    field(:basis_document, :map, default: %{})
    field(:policy_document, :map, default: %{})
    field(:preflight_document, :map, default: %{})
    field(:member_count, :integer)
    field(:decided_by_document, :map)
    field(:decided_at, :utc_datetime_usec)
    field(:decision_document, :map)
    field(:aborted_by_document, :map)
    field(:aborted_at, :utc_datetime_usec)
    field(:abort_reason, :string)
    field(:abort_result_document, :map)

    timestamps()
  end

  @required ~w(command_group_id mission_id state title requested_by_document requested_at
               resolved_at member_count)a

  @spec changeset(CommandGroup.t()) :: Ecto.Changeset.t()
  def changeset(%CommandGroup{} = group) do
    %__MODULE__{}
    |> cast(attrs(group), __schema__(:fields) -- [:inserted_at, :updated_at])
    |> validate_required(@required)
    |> unique_constraint([:mission_id, :operation_id], name: :command_groups_operation_idx)
  end

  @spec update_changeset(struct(), CommandGroup.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %CommandGroup{} = group) do
    row
    |> cast(attrs(group), __schema__(:fields) -- [:command_group_id, :inserted_at, :updated_at])
    |> validate_required(@required -- [:command_group_id])
  end

  @spec to_domain(struct()) :: CommandGroup.t()
  def to_domain(%__MODULE__{} = row) do
    documents =
      Map.new(@documents, fn key ->
        {key, row |> Map.fetch!(:"#{key}_document") |> unwrap()}
      end)

    row
    |> Map.from_struct()
    |> Map.drop([:__meta__, :inserted_at, :updated_at | Enum.map(@documents, &:"#{&1}_document")])
    |> Map.merge(documents)
    |> CommandGroup.new()
  end

  defp attrs(%CommandGroup{} = group) do
    documents = Map.new(@documents, &{:"#{&1}_document", wrap(Map.fetch!(group, &1))})

    group
    |> Map.from_struct()
    |> Map.drop(@documents)
    |> Map.update!(:state, &Atom.to_string/1)
    |> Map.merge(documents)
  end

  defp wrap(nil), do: nil
  defp wrap(value), do: JsonDocument.wrap_value(value)

  defp unwrap(nil), do: nil
  defp unwrap(document), do: JsonDocument.unwrap_value(document)
end
