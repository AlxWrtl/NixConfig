package main

// JavaScript string semantics the board.js port needs to give the same answers as node: JS
// whitespace (`\s`, trim), toLowerCase, UTF-16 ordering and slicing, Buffer's UTF-8 decoding,
// JSON.stringify output. Go's own versions differ at the edges (RE2 `\s` is ASCII, strings
// compare as bytes, encoding/json escapes `<` and U+2028).

import (
	"math"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

// jsSpaceClass is JS `\s` (WhiteSpace + LineTerminator) as the inside of an RE2 class.
const jsSpaceClass = `\t\n\x0B\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}`

// Regex atoms: JS `\s`, `\S`, and `.` without the s flag (no line terminator).
const (
	reS   = `[` + jsSpaceClass + `]`
	reNS  = `[^` + jsSpaceClass + `]`
	reDot = `[^\n\r\x{2028}\x{2029}]`
)

func isJSSpace(r rune) bool {
	switch r {
	case '\t', '\n', 0x0B, '\f', '\r', ' ', 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
		return true
	}
	return r >= 0x2000 && r <= 0x200A
}

// jsTrim is String.prototype.trim.
func jsTrim(s string) string { return strings.TrimFunc(s, isJSSpace) }

// jsLower is toLowerCase for matching: Go's simple mappings plus the one unconditional special
// case (U+0130 → i + U+0307) that changes what an ASCII pattern sees. Final sigma is not
// reproduced; no board pattern contains a sigma and lowered text is never shown.
func jsLower(s string) string {
	if strings.ContainsRune(s, 0x130) {
		s = strings.ReplaceAll(s, "İ", "i̇")
	}
	return strings.ToLower(s)
}

// jsCompare orders strings as JS `<` does: by UTF-16 code unit.
func jsCompare(a, b string) int {
	for a != "" && b != "" {
		ra, na := utf8.DecodeRuneInString(a)
		rb, nb := utf8.DecodeRuneInString(b)
		if ra != rb {
			ua, ub := firstUnit(ra), firstUnit(rb)
			if ua != ub {
				if ua < ub {
					return -1
				}
				return 1
			}
			// Same high surrogate: the low ones decide.
			if ra < rb {
				return -1
			}
			return 1
		}
		a, b = a[na:], b[nb:]
	}
	switch {
	case a == "" && b == "":
		return 0
	case a == "":
		return -1
	}
	return 1
}

func firstUnit(r rune) rune {
	if r >= 0x10000 {
		hi, _ := utf16.EncodeRune(r)
		return hi
	}
	return r
}

func jsLess(a, b string) bool { return jsCompare(a, b) < 0 }

// utf16Len is a JS string's length.
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		if r >= 0x10000 {
			n += 2
		} else {
			n++
		}
	}
	return n
}

// utf16Slice is s.slice(0, n). A pair cut in half leaves its high surrogate, kept as WTF-8 so
// jsonString can write it as JSON.stringify does (`\udXXX`).
func utf16Slice(s string, n int) string {
	units := 0
	for i, r := range s {
		w := 1
		if r >= 0x10000 {
			w = 2
		}
		if units+w > n {
			if units < n {
				hi, _ := utf16.EncodeRune(r)
				return s[:i] + wtf8(hi)
			}
			return s[:i]
		}
		units += w
	}
	return s
}

func wtf8(u rune) string {
	return string([]byte{byte(0xE0 | (u >> 12)), byte(0x80 | ((u >> 6) & 0x3F)), byte(0x80 | (u & 0x3F))})
}

// decodeUTF8 is node's buf.toString('utf8'): WHATWG decoding, one U+FFFD per maximal subpart
// of an invalid sequence (strings.ToValidUTF8 would merge a run into one).
func decodeUTF8(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	var sb strings.Builder
	sb.Grow(len(b) + 16)
	i := 0
	for i < len(b) {
		c := b[i]
		if c < 0x80 {
			sb.WriteByte(c)
			i++
			continue
		}
		need, lo, hi := 0, byte(0x80), byte(0xBF)
		switch {
		case c >= 0xC2 && c <= 0xDF:
			need = 1
		case c == 0xE0:
			need, lo = 2, 0xA0
		case c >= 0xE1 && c <= 0xEC, c == 0xEE, c == 0xEF:
			need = 2
		case c == 0xED:
			need, hi = 2, 0x9F
		case c == 0xF0:
			need, lo = 3, 0x90
		case c >= 0xF1 && c <= 0xF3:
			need = 3
		case c == 0xF4:
			need, hi = 3, 0x8F
		default:
			sb.WriteRune(utf8.RuneError)
			i++
			continue
		}
		j := i + 1
		ok := true
		for k := 0; k < need; k++ {
			if j >= len(b) || b[j] < lo || b[j] > hi {
				ok = false
				break
			}
			lo, hi = 0x80, 0xBF
			j++
		}
		if !ok {
			// The maximal subpart b[i:j] is one replacement; b[j] starts afresh.
			sb.WriteRune(utf8.RuneError)
			i = j
			continue
		}
		sb.Write(b[i:j])
		i = j
	}
	return sb.String()
}

// jsonString is JSON.stringify of a string: short escapes, other controls as \u00xx, lone
// surrogates (WTF-8) as \udxxx, everything else literal.
func jsonString(sb *strings.Builder, s string) {
	const hex = "0123456789abcdef"
	sb.WriteByte('"')
	for i := 0; i < len(s); {
		c := s[i]
		if c == 0xED && i+2 < len(s) && s[i+1] >= 0xA0 && s[i+1] <= 0xBF && s[i+2] >= 0x80 && s[i+2] <= 0xBF {
			u := 0xD000 | int(s[i+1]&0x3F)<<6 | int(s[i+2]&0x3F)
			sb.WriteString(`\u`)
			sb.WriteByte(hex[u>>12&0xF])
			sb.WriteByte(hex[u>>8&0xF])
			sb.WriteByte(hex[u>>4&0xF])
			sb.WriteByte(hex[u&0xF])
			i += 3
			continue
		}
		if c >= 0x80 {
			r, n := utf8.DecodeRuneInString(s[i:])
			if r == utf8.RuneError && n == 1 {
				sb.WriteString(`�`)
			} else {
				sb.WriteString(s[i : i+n])
			}
			i += n
			continue
		}
		switch c {
		case '"':
			sb.WriteString(`\"`)
		case '\\':
			sb.WriteString(`\\`)
		case '\b':
			sb.WriteString(`\b`)
		case '\f':
			sb.WriteString(`\f`)
		case '\n':
			sb.WriteString(`\n`)
		case '\r':
			sb.WriteString(`\r`)
		case '\t':
			sb.WriteString(`\t`)
		default:
			if c < 0x20 {
				sb.WriteString(`\u00`)
				sb.WriteByte(hex[c>>4])
				sb.WriteByte(hex[c&0xF])
			} else {
				sb.WriteByte(c)
			}
		}
		i++
	}
	sb.WriteByte('"')
}

// jsNumber is Number.prototype.toString for the values the board writes (counts, epoch ms).
func jsNumber(f float64) string {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return "null" // JSON.stringify writes non-finite numbers as null
	}
	if f == 0 {
		return "0"
	}
	a := math.Abs(f)
	if a >= 1e21 || a < 1e-6 {
		s := strconv.FormatFloat(f, 'e', -1, 64)
		// Go writes e+21 / e-07; JS writes e+21 / e-7.
		mant, exp, _ := strings.Cut(s, "e")
		sign := exp[0]
		exp = strings.TrimLeft(exp[1:], "0")
		return mant + "e" + string(sign) + exp
	}
	return strconv.FormatFloat(f, 'f', -1, 64)
}

// ---- JSON.stringify(value, null, 1) over an ordered value tree -------------------------

type jkv struct {
	k string
	v any
}

// jobj is an object with its keys in insertion order (no integer-like keys are used).
type jobj []jkv

func writeJSON(sb *strings.Builder, v any, depth int) {
	switch x := v.(type) {
	case nil:
		sb.WriteString("null")
	case bool:
		if x {
			sb.WriteString("true")
		} else {
			sb.WriteString("false")
		}
	case int:
		sb.WriteString(strconv.Itoa(x))
	case float64:
		sb.WriteString(jsNumber(x))
	case *float64:
		if x == nil {
			sb.WriteString("null")
		} else {
			sb.WriteString(jsNumber(*x))
		}
	case string:
		jsonString(sb, x)
	case *string:
		if x == nil {
			sb.WriteString("null")
		} else {
			jsonString(sb, *x)
		}
	case []string:
		arr := make([]any, len(x))
		for i, s := range x {
			arr[i] = s
		}
		writeJSON(sb, arr, depth)
	case []any:
		if len(x) == 0 {
			sb.WriteString("[]")
			return
		}
		sb.WriteString("[\n")
		for i, e := range x {
			if i > 0 {
				sb.WriteString(",\n")
			}
			sb.WriteString(strings.Repeat(" ", depth+1))
			writeJSON(sb, e, depth+1)
		}
		sb.WriteByte('\n')
		sb.WriteString(strings.Repeat(" ", depth))
		sb.WriteByte(']')
	case jobj:
		if len(x) == 0 {
			sb.WriteString("{}")
			return
		}
		sb.WriteString("{\n")
		for i, kv := range x {
			if i > 0 {
				sb.WriteString(",\n")
			}
			sb.WriteString(strings.Repeat(" ", depth+1))
			jsonString(sb, kv.k)
			sb.WriteString(": ")
			writeJSON(sb, kv.v, depth+1)
		}
		sb.WriteByte('\n')
		sb.WriteString(strings.Repeat(" ", depth))
		sb.WriteByte('}')
	default:
		panic("writeJSON: unsupported type")
	}
}
