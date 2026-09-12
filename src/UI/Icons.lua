local Icons = {}

-- Keep symbols as code points so they cannot be corrupted by a source-file encoding change.
-- Every symbol is paired with a text label in the UI; the symbol is never the only cue.
Icons.CHECK = utf8.char(0x2713)
Icons.PLAY = utf8.char(0x25B6)
Icons.STOP = utf8.char(0x25A0)
Icons.ADD = utf8.char(0xFF0B)
Icons.HISTORY = utf8.char(0x21B6)
Icons.BASELINE = utf8.char(0x2691)
Icons.EXPORT = utf8.char(0x2193)
Icons.CLOSE = utf8.char(0x00D7)
Icons.DISTRIBUTION = utf8.char(0x25A5)
Icons.LINE = utf8.char(0x2197)
Icons.ERROR_BARS = utf8.char(0x2194)
Icons.RESET = utf8.char(0x21BB)
Icons.STOPWATCH = utf8.char(0x23F1)

function Icons.label(icon, text)
	return icon .. " " .. text
end

return Icons
