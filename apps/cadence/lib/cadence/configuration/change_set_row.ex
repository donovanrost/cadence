defmodule Cadence.Configuration.ChangeSetRow do
  @moduledoc """
  A mission's staging area, in a lane (ADR-020 P3, #451; U108). A configuration set is the mission's
  one active set (open or in review). A monitoring set is the mission's one open monitoring set;
  any number of monitoring sets can be in review at once.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @states ~w(open in_review applied discarded)
  @lanes ~w(configuration monitoring)

  @primary_key {:change_set_id, :string, autogenerate: false}
  schema "mission_config_change_sets" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:state, :string)
    field(:lane, :string, default: "configuration")
    field(:version, :integer, default: 1)
    field(:base_revision_number, :integer)
    field(:opened_by, :map)
    field(:opened_at, :utc_datetime_usec)
    field(:submitted_by, :map)
    field(:submitted_at, :utc_datetime_usec)
    field(:reason, :string)
    field(:policy_document, :map)
    field(:failure_document, :map)
    # D3 (#544): what the submit selected, %{composition_id => revision_id | reason}.
    field(:selections, :map)
    field(:applied_revision_number, :integer)
    field(:closed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states
  def lanes, do: @lanes
end
