import { describe, it, expect } from "vitest"
import { Terminal } from "@xterm/headless"
import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

function writeAndRead(content, cols = 120) {
  return new Promise((resolve) => {
    const term = new Terminal({ cols, rows: 50, scrollback: 5000, allowProposedApi: true })
    term.write(content, () => {
      const lines = []
      const buf = term.buffer.active
      for (let i = 0; i < buf.length; i++) {
        const line = buf.getLine(i)
        if (line) lines.push(line.translateToString(true))
      }
      term.dispose()
      resolve(lines)
    })
  })
}

const rawFixture = fs.readFileSync(
  path.join(__dirname, "fixtures/pane-2733-raw.txt"),
  "utf-8"
)

describe("tmux capture-pane rendering in xterm.js", () => {
  it("raw \\n-only output causes staircase effect (the bug)", async () => {
    const lines = await writeAndRead(rawFixture, 120)

    const claudeLineIdx = lines.findIndex((l) => l.includes("Claude Code"))
    expect(claudeLineIdx).toBeGreaterThanOrEqual(0)

    const opusLineIdx = lines.findIndex((l) => l.includes("Opus"))
    expect(opusLineIdx).toBeGreaterThan(claudeLineIdx)

    // In the staircase bug, "Opus" line has leading spaces from cursor not resetting
    const opusLine = lines[opusLineIdx]
    const leadingSpaces = opusLine.match(/^(\s*)/)[1].length
    expect(leadingSpaces).toBeGreaterThan(5)
  })

  it("\\r\\n-converted output renders lines starting at column 0", async () => {
    const fixed = rawFixture.replace(/\r?\n/g, "\r\n")
    const lines = await writeAndRead(fixed, 120)

    const claudeLineIdx = lines.findIndex((l) => l.includes("Claude Code"))
    const opusLineIdx = lines.findIndex((l) => l.includes("Opus"))
    expect(opusLineIdx).toBe(claudeLineIdx + 1)

    const opusLine = lines[opusLineIdx]
    const leadingSpaces = opusLine.match(/^(\s*)/)[1].length
    expect(leadingSpaces).toBeLessThan(5)
  })

  it("ANSI escape codes are preserved after conversion", async () => {
    const fixed = rawFixture.replace(/\r?\n/g, "\r\n")
    const lines = await writeAndRead(fixed, 120)
    const claudeLine = lines.find((l) => l.includes("Claude Code"))
    expect(claudeLine).toBeDefined()
    expect(claudeLine).toContain("v2.1")
  })

  it("fixed output has same line count as source lines", async () => {
    const fixed = rawFixture.replace(/\r?\n/g, "\r\n")
    const sourceLineCount = rawFixture.split("\n").length
    const lines = await writeAndRead(fixed, 120)

    let lastNonEmpty = lines.length - 1
    while (lastNonEmpty > 0 && lines[lastNonEmpty].trim() === "") lastNonEmpty--
    const renderedCount = lastNonEmpty + 1

    // Some lines with long ANSI sequences may wrap, so rendered count can exceed source.
    // But it should be in the same ballpark — not 2x+ like the staircase bug would cause.
    expect(renderedCount).toBeLessThan(sourceLineCount * 2)
    expect(renderedCount).toBeGreaterThanOrEqual(sourceLineCount - 5)
  })
})
