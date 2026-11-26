defmodule Cadence.Management.Commanding.RequestReview do
  @moduledoc "Who may review a mission's command requests, and the digest of the request reviewed."
  alias Cadence.Management.Commanding.{ReviewAccess, ReviewPrecondition}

  defdelegate authorize(scope, mission), to: ReviewAccess
  defdelegate review_token(request), to: ReviewPrecondition, as: :digest
end
