defmodule CadenceWeb.Console.ElementSetJSON do
  @moduledoc """
  Element sets as the REST API shows them (#889). Contract: docs/apogee/api/element-sets.md.
  The actor names a response needs are loaded once for all its rows (`ActorRef.names/2`).
  """

  alias Cadence.Control.ActorRef
  alias Cadence.GroundNetworks.ElementSet
  alias CadenceWeb.Console.Problem

  @doc "The actor names for `rows` of one organization, in one read."
  @spec names(binary(), [ElementSet.t()]) :: ActorRef.names()
  def names(organization_id, rows),
    do: ActorRef.names(organization_id, Enum.map(rows, & &1.created_by))

  @spec element_set(ElementSet.t(), ActorRef.names()) :: map()
  def element_set(%ElementSet{} = row, names) do
    %{
      id: row.element_set_id,
      spacecraft_id: row.spacecraft_id,
      format: row.format,
      source: row.source,
      epoch: row.epoch,
      object_name: row.object_name,
      norad_id: row.norad_id,
      element_set_number: row.element_set_number,
      elements: %{
        mean_motion_rev_per_day: row.mean_motion,
        eccentricity: row.eccentricity,
        inclination_deg: row.inclination_deg,
        raan_deg: row.raan_deg,
        arg_perigee_deg: row.arg_perigee_deg,
        mean_anomaly_deg: row.mean_anomaly_deg,
        bstar: row.bstar,
        mean_motion_dot: row.mean_motion_dot,
        mean_motion_ddot: row.mean_motion_ddot
      },
      content_sha256: row.content_sha256,
      raw: row.raw,
      received_at: row.received_at,
      created_by: ActorRef.document(row.created_by, names)
    }
  end

  @doc "A refusal as `{code, message, details}`, the error envelope's own shape."
  @spec refusal(atom(), map()) :: map()
  def refusal(reason, details) do
    {_status, code, message} = Problem.describe(problem(reason))
    %{code: code, message: message, details: details}
  end

  @doc "The Problem reason for a domain refusal."
  @spec problem(atom()) :: atom()
  def problem(:unparseable), do: :element_set_unparseable
  def problem(:bad_checksum), do: :element_set_bad_checksum
  def problem(:catalog_number_mismatch), do: :element_set_catalog_number_mismatch
  def problem(:non_physical), do: :element_set_non_physical
  def problem(:epoch_in_future), do: :element_set_epoch_in_future
  def problem(:unsupported_mean_element_theory), do: :element_set_unsupported_mean_element_theory
  def problem(:unsupported_reference), do: :element_set_unsupported_reference
  def problem(reason) when reason in [:spacecraft_not_found, :invalid_params], do: reason
end
