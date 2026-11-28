defmodule Cadence.GroundNetworks.ElementSets.ElementSetRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.GroundNetworks.ElementSet
  alias Cadence.GroundNetworks.ElementSets.Elements

  @primary_key {:element_set_id, :string, autogenerate: false}

  schema "orbit_element_sets" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:format, :string)
    field(:source, :string)
    field(:raw, :string)
    field(:object_name, :string)
    field(:norad_id, :integer)
    field(:element_set_number, :integer)
    field(:epoch, :utc_datetime_usec)
    field(:mean_motion, :float)
    field(:eccentricity, :float)
    field(:inclination_deg, :float)
    field(:raan_deg, :float)
    field(:arg_perigee_deg, :float)
    field(:mean_anomaly_deg, :float)
    field(:bstar, :float)
    field(:mean_motion_dot, :float)
    field(:mean_motion_ddot, :float)
    field(:content_sha256, :string)
    field(:received_at, :utc_datetime_usec)
    field(:created_by, :map)
  end

  @type t :: %__MODULE__{}

  @required ~w(element_set_id organization_id mission_id spacecraft_id format source raw epoch
               mean_motion eccentricity inclination_deg raan_deg arg_perigee_deg mean_anomaly_deg
               bstar mean_motion_dot mean_motion_ddot content_sha256 received_at created_by)a

  @doc "A new row for `elements` on `spacecraft_id`; `context` carries the ids, source and actor."
  @spec changeset(Elements.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Elements{} = elements, %{} = context) do
    attrs =
      elements
      |> Map.from_struct()
      |> Map.update!(:format, &Atom.to_string/1)
      |> Map.merge(%{content_sha256: Elements.content_sha256(elements)})
      |> Map.merge(context)

    %__MODULE__{}
    |> cast(attrs, __schema__(:fields))
    |> validate_required(@required)
    |> validate_inclusion(:format, ["omm", "tle"])
    |> validate_inclusion(:source, ["manual", "api"])
  end

  @spec to_domain(t()) :: ElementSet.t()
  def to_domain(%__MODULE__{} = row),
    do: struct!(ElementSet, Map.drop(Map.from_struct(row), [:__meta__]))
end
