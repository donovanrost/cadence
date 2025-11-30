/**
 * Tokyo Night Theme for SciChart
 *
 * A custom theme that matches the Cadence application's dark mode aesthetic.
 * Based on the Tokyo Night color palette with vaporwave accents.
 */

import { SciChartJsNavyTheme } from "scichart"

/**
 * Tokyo Night color palette
 */
export const TokyoNightColors = {
  // Backgrounds
  background: "#16161e",      // Main background
  surface: "#1f2230",         // Cards, surfaces
  surfaceElevated: "#292d42", // Elevated surfaces
  border: "#3b4261",          // Borders

  // Text
  textPrimary: "#c0caf5",     // Primary text
  textSecondary: "#a9b1d6",   // Secondary text
  textMuted: "#565f89",       // Muted text

  // Accent colors
  cyan: "#7dcfff",            // Primary cyan
  purple: "#bb9af7",          // Secondary purple
  pink: "#ff007c",            // Accent pink
  blue: "#7aa2f7",            // Info blue
  teal: "#73daca",            // Success teal
  orange: "#ff9e64",          // Warning orange
  red: "#f7768e",             // Error red
  green: "#9ece6a",           // Alternative green
  yellow: "#e0af68",          // Alternative yellow

  // Chart series colors (for multiple data series)
  series: [
    "#7dcfff",  // Cyan
    "#bb9af7",  // Purple
    "#ff007c",  // Pink
    "#7aa2f7",  // Blue
    "#73daca",  // Teal
    "#ff9e64",  // Orange
    "#9ece6a",  // Green
    "#e0af68",  // Yellow
    "#f7768e",  // Red
    "#2ac3de",  // Light cyan
    "#9d7cd8",  // Light purple
    "#ff79c6",  // Light pink
  ]
}

/**
 * SciChart theme configuration for Tokyo Night
 */
export class TokyoNightTheme extends SciChartJsNavyTheme {
  constructor() {
    super()

    // Override base theme properties
    this.sciChartBackground = TokyoNightColors.background
    this.loadingAnimationBackground = TokyoNightColors.background
    this.loadingAnimationForeground = TokyoNightColors.cyan

    // Grid lines - subtle, not noisy
    this.majorGridLineColor = TokyoNightColors.border + "25"  // Very subtle
    this.minorGridLineColor = "transparent"  // Hide minor gridlines completely

    // Axis styling
    this.axisTitleColor = TokyoNightColors.textSecondary
    this.axisBandsFill = TokyoNightColors.surface + "30"
    this.axisBorder = TokyoNightColors.border
    this.tickTextBrush = TokyoNightColors.textMuted
    this.labelForeground = TokyoNightColors.textPrimary
    this.labelBorder = TokyoNightColors.border
    this.labelBackground = TokyoNightColors.surface

    // Cursor/Rollover styling
    this.cursorLineBrush = TokyoNightColors.cyan + "80"
    this.rolloverLineBrush = TokyoNightColors.cyan

    // Legend styling
    this.legendBackgroundBrush = TokyoNightColors.surface
    this.legendTextColor = TokyoNightColors.textPrimary
    this.legendBorder = TokyoNightColors.border

    // Scrollbar styling (if using chart scrollbars)
    this.scrollbarBackgroundBrush = TokyoNightColors.surface
    this.scrollbarBorderBrush = TokyoNightColors.border
    this.scrollbarGripsBackgroundBrush = TokyoNightColors.surfaceElevated
    this.scrollbarViewportBackgroundBrush = TokyoNightColors.cyan + "30"
    this.scrollbarViewportBorderBrush = TokyoNightColors.cyan

    // Annotation colors
    this.annotationsGripsBackroundBrush = TokyoNightColors.cyan
    this.annotationsGripsBorderBrush = TokyoNightColors.surfaceElevated

    // Default stroke palette for multiple series
    this.strokePalette = TokyoNightColors.series
    this.fillPalette = TokyoNightColors.series.map(c => c + "40")  // 25% opacity fills
  }

  /**
   * Get a color from the series palette by index (wraps around).
   *
   * @param {number} index - The series index
   * @returns {string} The hex color
   */
  getSeriesColor(index) {
    return TokyoNightColors.series[index % TokyoNightColors.series.length]
  }

  /**
   * Get a fill color (with transparency) for a series.
   *
   * @param {number} index - The series index
   * @param {number} opacity - Opacity from 0 to 1
   * @returns {string} The hex color with alpha
   */
  getSeriesFill(index, opacity = 0.25) {
    const color = this.getSeriesColor(index)
    const alpha = Math.round(opacity * 255).toString(16).padStart(2, '0')
    return color + alpha
  }
}

/**
 * Limits state colors for telemetry values
 */
export const LimitsColors = {
  green: TokyoNightColors.teal,
  yellow: TokyoNightColors.orange,
  yellow_low: TokyoNightColors.orange,
  yellow_high: TokyoNightColors.orange,
  red: TokyoNightColors.red,
  red_low: TokyoNightColors.red,
  red_high: TokyoNightColors.red,
  blue: TokyoNightColors.blue,  // Stale data
  unknown: TokyoNightColors.textMuted
}

/**
 * Get the color for a limits state.
 *
 * @param {string} state - The limits state
 * @returns {string} The hex color
 */
export function getLimitsColor(state) {
  return LimitsColors[state] || LimitsColors.unknown
}

export default TokyoNightTheme
