'use client'

/**
 * EAN-13 renderer — pure SVG, zero dependencies (design report §7.5).
 *
 * The bar pattern is deterministic: the 13th digit is a Mod-10 check, the
 * first digit selects the parity table of the six left-side digits (L/G
 * codes), the right side always uses R codes. Guards: 101 / 01010 / 101.
 *
 * The component renders nothing when the code is not a structurally valid
 * EAN-13 (13 digits + check digit) — a broken code must never reach paper
 * looking like a scannable one. Quiet zones (11 modules each side) are part
 * of the viewBox so shrinking the container never clips them (GS1 print
 * rule, review §7.4).
 */

const L_CODES = [
  '0001101', '0011001', '0010011', '0111101', '0100011',
  '0110001', '0101111', '0111011', '0110111', '0001011',
]
const G_CODES = [
  '0100111', '0110011', '0011011', '0100001', '0011101',
  '0111001', '0000101', '0010001', '0001001', '0010111',
]
const R_CODES = [
  '1110010', '1100110', '1101100', '1000010', '1011100',
  '1001110', '1010000', '1000100', '1001000', '1110100',
]
// Parity table: first digit → L/G pattern of the six left digits.
const PARITY = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL']

export function ean13IsValid(code: string): boolean {
  if (!/^\d{13}$/.test(code)) return false
  let sum = 0
  for (let i = 0; i < 12; i++) sum += Number(code[i]) * (i % 2 === 0 ? 1 : 3)
  return (10 - (sum % 10)) % 10 === Number(code[12])
}

function ean13Modules(code: string): string {
  const parity = PARITY[Number(code[0])]
  const left = code.slice(1, 7)
  const right = code.slice(7, 13)
  const leftBits = left.split('').map((d, i) => (parity[i] === 'L' ? L_CODES : G_CODES)[Number(d)]).join('')
  const rightBits = right.split('').map((d) => R_CODES[Number(d)]).join('')
  return `101${leftBits}01010${rightBits}101`
}

/**
 * 113 وحدة كاملة (بما فيها مناطق الهدوء 11+11). المكوّن لا ينزل عن 80% من
 * الحد الأدنى GS1 للتضخيم — أقل من ذلك لا يضمن القراءة.
 */
export const EAN13_MODULES = 113

export default function Ean13Svg({
  code,
  className,
  showText = true,
  color = '#111',
}: {
  code: string
  className?: string
  showText?: boolean
  color?: string
}) {
  if (!ean13IsValid(code)) return null
  const bits = ean13Modules(code)
  const bars: Array<{ x: number; w: number }> = []
  let run = 0
  for (let i = 0; i <= bits.length; i++) {
    const bit = bits[i] === '1'
    if (bit) run++
    else if (run > 0) {
      bars.push({ x: i - run, w: run })
      run = 0
    }
  }
  const guardStart = 11
  const leftBlockEnd = 11 + 42 + 7 // quiet + 6 codes left + middle guard
  const rightBlockStart = leftBlockEnd + 5
  const textY = 33

  return (
    <svg
      viewBox={`0 0 ${EAN13_MODULES} 36`}
      className={className}
      role="img"
      aria-label={`EAN-13 ${code}`}
      preserveAspectRatio="xMidYMid meet"
    >
      <rect x="0" y="0" width={EAN13_MODULES} height="36" fill="#fff" />
      {bars.map((bar, index) => (
        <rect key={index} x={bar.x} y="0" width={bar.w} height="28" fill={color} />
      ))}
      {showText && (
        <g fill={color} style={{ font: 'bold 7px monospace' }} textAnchor="middle">
          <text x={guardStart / 2} y={textY}>{code[0]}</text>
          <text x={(guardStart + leftBlockEnd) / 2} y={textY}>{code.slice(1, 7)}</text>
          <text x={(rightBlockStart + EAN13_MODULES - guardStart) / 2} y={textY}>{code.slice(7, 13)}</text>
        </g>
      )}
    </svg>
  )
}
