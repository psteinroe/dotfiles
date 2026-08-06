export type BackgroundWidgetColor = "warning" | "text" | "dim" | "accent";

export interface BackgroundWidgetTheme {
  fg(color: BackgroundWidgetColor, text: string): string;
}

export type TruncateLine = (text: string, width: number) => string;

/** Render the one-line running-terminal status shown above Pi's editor. */
export function renderBackgroundWidgetLine(
  running: number,
  width: number,
  theme: BackgroundWidgetTheme,
  truncateToWidth: TruncateLine,
): string {
  const line =
    theme.fg("warning", "■ ") +
    theme.fg(
      "text",
      `${running} background terminal${running === 1 ? "" : "s"} running`,
    ) +
    theme.fg("dim", " • ") +
    theme.fg("accent", "/ps") +
    theme.fg("dim", " to view");

  return truncateToWidth(line, Math.max(0, width));
}
