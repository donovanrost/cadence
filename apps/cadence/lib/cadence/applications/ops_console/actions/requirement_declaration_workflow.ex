defmodule Cadence.Applications.OpsConsole.Actions.RequirementDeclarationWorkflow do
  @moduledoc "Governed declaration validation, creation and bounded choice reads."
  alias Cadence.Applications.OpsConsole.Actions.RequirementDeclarationInput, as: Input
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Reads.ApplicationSurfaces.Planning.RequirementDeclaration
  @actions ~w(validate save spacecraft-page)
  def actions, do: @actions

  def execute(scope, mission, "spacecraft-page", %{"page" => page} = input)
      when map_size(input) == 1 do
    case RequirementDeclaration.choices(scope, mission, page) do
      {:ok, spacecraft} -> {:ok, %{spacecraft: spacecraft}}
      {:error, _} -> {:rejected, ["invalid_page"]}
    end
  end

  def execute(scope, mission, "validate", input) do
    case prepare(scope, mission, input) do
      {:ok, _} -> {:ok, %{valid: true, feedback: []}}
      {:error, reason} -> {:ok, %{valid: false, feedback: [feedback(reason)]}}
    end
  end

  def execute(scope, mission, "save", input) do
    with {:ok, form} <- Input.admit(input),
         {:ok, attrs} <- Input.parse(form),
         {:ok, requirement, version} <- ContactRequirements.create(scope, mission, attrs) do
      {:ok,
       %{
         contract_version: 1,
         organization_id: scope.organization_id,
         mission_id: mission,
         actor_id: scope.user.user_id,
         requirement_id: requirement.contact_requirement_id,
         requirement_version: version.version,
         content_sha256: version.content_sha256
       }}
    else
      {:error, reason} -> {:rejected, [feedback(reason)]}
    end
  end

  def execute(_, _, _, _), do: {:rejected, ["invalid_input"]}

  defp prepare(scope, mission, input) do
    with {:ok, form} <- Input.admit(input),
         {:ok, attrs} <- Input.parse(form),
         {:ok, _, _} <- ContactRequirements.prepare_create(scope, mission, attrs) do
      {:ok, attrs}
    end
  end

  defp feedback(:invalid_datetime), do: "invalid_datetime"

  defp feedback(reason) when reason in [:invalid_positive_integer, :invalid_nonnegative_integer],
    do: "invalid_number"

  defp feedback(:contact_requirement_spacecraft_not_found), do: "spacecraft_unavailable"

  defp feedback(reason)
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required], do: "forbidden"

  defp feedback({:contact_requirement_field_too_large, _, _}), do: "text_too_long"
  defp feedback(:conflicting_contact_requirement_constraints), do: "conflicting_constraints"

  defp feedback({:invalid_contact_requirement, "latest_end must be after earliest_start"}),
    do: "horizon_order"

  defp feedback(
         {:invalid_contact_requirement,
          "preferred_duration_seconds must not be below the minimum"}
       ),
       do: "duration_order"

  defp feedback({:invalid_contact_requirement, "minimum_duration_seconds is required"}),
    do: "duration_required"

  defp feedback({:invalid_contact_requirement, "minimum_data_volume_bytes is required"}),
    do: "volume_required"

  defp feedback(:required_fields), do: "required_fields"
  defp feedback(:malformed_input), do: "invalid_input"
  defp feedback(_), do: "invalid_requirement"
end
