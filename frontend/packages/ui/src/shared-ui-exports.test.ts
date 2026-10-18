import { describe, expect, it } from "vite-plus/test";
import * as ui from "./index";

const presentationExports = [
  "CadenceBadge",
  "CadenceBreadcrumbs",
  "CadenceButton",
  "CadenceLinkButton",
  "CadenceIcon",
  "CadenceDialog",
  "CadenceTextArea",
  "CadenceDateTimeRangeField",
  "CadenceIconButton",
  "CadenceCard",
  "CadenceCompactPageHeaderBodyFrame",
  "CadenceDashboardSettingsSectionFrame",
  "CadenceDataRow",
  "CadenceDefinitionListPanel",
  "CadenceDetailsFrame",
  "CadenceDiagnosticsSectionFrame",
  "CadenceEmptyState",
  "CadenceEmptyStateFrame",
  "CadenceField",
  "CadenceFormActions",
  "CadenceFormPageFrame",
  "CadenceFormSectionFrame",
  "CadenceFormSectionHeader",
  "CadenceHoverTableRow",
  "CadenceInlineWarning",
  "CadenceListToolbarFrame",
  "CadenceNarrowFormPageFrame",
  "CadenceNoticeFrame",
  "CadenceOpsListBodyFrame",
  "CadenceOpsListFrame",
  "CadenceOpsPageBodyFrame",
  "CadenceOpsViewport",
  "CadencePageHeader",
  "CadencePageHeaderFrame",
  "CadencePageTitle",
  "CadencePaginationFrame",
  "CadencePanel",
  "CadencePresentationNode",
  "CadenceStatTile",
  "CadenceTableFrame",
  "CadenceValidationMessage",
  "WidgetFormField",
  "AccountDropdownMenu",
  "CadenceCollapsible",
  "CadenceCollapsibleContent",
  "CadenceCollapsibleTrigger",
  "CadenceMenu",
  "CadenceMenuItem",
  "CadenceModalMenu",
  "CadencePopover",
  "CadenceToggle",
  "CadencePrimitiveChild",
] as const;

describe("shared UI package exports", () => {
  it("publishes the complete frozen presentation and Reka closure", () => {
    for (const exportName of presentationExports) {
      expect(ui[exportName]).toBeDefined();
    }
  });

  it("publishes the overlay compatibility helpers for legacy callers", () => {
    expect(ui.CADENCE_OVERLAY_OPENED_EVENT).toBe("cadence:overlay-opened");
    expect(ui.preservesPopoverOpenState(true, "one", "one")).toBe(true);
    expect(ui.preservesPopoverOpenState(true, "one", "two")).toBe(false);
  });
});
