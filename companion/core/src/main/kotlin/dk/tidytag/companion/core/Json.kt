package dk.tidytag.companion.core

/** Just enough JSON for this protocol: writing objects/arrays, and reading flat objects. */
object Json {
    fun str(s: String): String {
        val b = StringBuilder("\"")
        for (c in s) when {
            c == '"' -> b.append("\\\"")
            c == '\\' -> b.append("\\\\")
            c < ' ' -> b.append(String.format("\\u%04x", c.code))
            else -> b.append(c)
        }
        return b.append('"').toString()
    }

    fun obj(vararg fields: Pair<String, Any?>): String = fields.joinToString(",", "{", "}") { (k, v) ->
        str(k) + ":" + when (v) {
            null -> "null"
            is String -> str(v)
            is Boolean, is Number -> v.toString()
            is RawJson -> v.text
            else -> str(v.toString())
        }
    }

    fun arr(items: List<String>): String = items.joinToString(",", "[", "]")

    /** Parses a flat object whose values are strings, numbers or arrays of strings. */
    fun parse(text: String): Map<String, Any> {
        val p = Parser(text)
        return p.obj()
    }

    private class Parser(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun expect(c: Char) { ws(); require(i < s.length && s[i] == c) { "JSON: '$c' expected at $i" }; i++ }
        fun obj(): Map<String, Any> {
            val m = mutableMapOf<String, Any>()
            expect('{'); ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                val k = string(); expect(':'); m[k] = value(); ws()
                if (s[i] == ',') { i++; continue }
                expect('}'); return m
            }
        }
        fun value(): Any {
            ws()
            return when (s[i]) {
                '"' -> string()
                '[' -> { i++; val l = mutableListOf<String>(); ws()
                    if (s[i] == ']') { i++ } else while (true) { l += string(); ws(); if (s[i] == ',') i++ else { expect(']'); break } }
                    l }
                else -> { val st = i; while (i < s.length && (s[i].isDigit() || s[i] == '-')) i++; s.substring(st, i).toLong() }
            }
        }
        fun string(): String {
            ws(); expect('"')
            val b = StringBuilder()
            while (s[i] != '"') {
                if (s[i] == '\\') {
                    i++
                    when (s[i]) {
                        'u' -> { b.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                        'n' -> b.append('\n'); 't' -> b.append('\t'); 'r' -> b.append('\r')
                        else -> b.append(s[i])
                    }
                } else b.append(s[i])
                i++
            }
            i++
            return b.toString()
        }
    }
}

class RawJson(val text: String)
