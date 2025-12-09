defmodule Cadence.Settings.Definitions.Procedures do
  @moduledoc """
  Settings definitions for the Procedures feature.

  These settings control procedure approval workflows, including how many
  approvals are required and whether certain actions are allowed.
  """

  use Cadence.Settings.Definition

  @namespace :procedures

  setting(:required_approvals,
    type: :integer,
    default: 1,
    scope: :both,
    restrictiveness: :higher,
    validate: {:range, 1, 10},
    label: "Required Approvals",
    description: "Number of approvals needed before a procedure version is approved"
  )

  setting(:allow_self_approval,
    type: :boolean,
    default: true,
    scope: :both,
    restrictiveness: :false_is_stricter,
    label: "Allow Self-Approval",
    description: "Whether procedure authors can approve their own work"
  )

  setting(:allow_withdrawal,
    type: :boolean,
    default: true,
    scope: :both,
    restrictiveness: :none,
    label: "Allow Withdrawal",
    description: "Whether authors can withdraw submissions before approval"
  )
end
