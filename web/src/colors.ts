export const TAG_COLORS = [
  '#FF5733', // Red
  '#33FF57', // Green
  '#3357FF', // Blue
  '#FF33F5', // Purple
  '#FFD700', // Gold
  '#FF8C00', // Orange
  '#00CED1', // Turquoise
  '#FF69B4', // Hot Pink
]

export function getLuminance(hex: string): number {
  const rgb = parseInt(hex.slice(1), 16)
  const r = (rgb >> 16) & 255
  const g = (rgb >> 8) & 255
  const b = rgb & 255
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
}

export function getContrastColor(hex: string): string {
  return getLuminance(hex) > 0.5 ? '#000' : '#FFF'
}
