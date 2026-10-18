const names: Record<number, string> = {
  0: "Urgent",
  1: "High",
  2: "Elevated",
  3: "Normal",
  4: "Low",
};
export const priorityLabel = (rank: number) => `${names[rank] ?? "Custom"} (rank ${rank})`;

export function priorityChoices(...preserved: (number | null | undefined)[]) {
  const ranks = new Set([0, 1, 2, 3, 4]);
  for (const rank of preserved)
    if (typeof rank === "number" && Number.isSafeInteger(rank) && rank >= 0 && rank <= 2147483647)
      ranks.add(rank);
  return [...ranks].sort((a, b) => a - b).map((rank) => ({ rank, label: priorityLabel(rank) }));
}
