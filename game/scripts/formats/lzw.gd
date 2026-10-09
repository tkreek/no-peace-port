class_name Lzw
extends RefCounted
## LZW decoder for RDCHUNK payloads: MSB-first codes of 9..13 bits, 256 = clear,
## 257 = end, early code-width change (width grows when next_code + 1 hits the limit).

const CLEAR := 256
const END := 257
const MAX_BITS := 13
const MAX_CODES := 1 << MAX_BITS


static func decompress(data: PackedByteArray, expected_size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(expected_size)
	var prefix := PackedInt32Array()
	var suffix := PackedByteArray()
	var lengths := PackedInt32Array()
	prefix.resize(MAX_CODES)
	suffix.resize(MAX_CODES)
	lengths.resize(MAX_CODES)
	for i in 256:
		prefix[i] = -1
		suffix[i] = i
		lengths[i] = 1

	var next_code := 258
	var bits := 9
	var prev := -1
	var bit_buffer := 0
	var bit_count := 0
	var in_pos := 0
	var out_pos := 0
	var data_size := data.size()

	while out_pos < expected_size:
		while bit_count < bits and in_pos < data_size:
			bit_buffer = ((bit_buffer << 8) | data[in_pos]) & 0xFFFFFF
			in_pos += 1
			bit_count += 8
		if bit_count < bits:
			break
		bit_count -= bits
		var code := (bit_buffer >> bit_count) & ((1 << bits) - 1)

		if code == CLEAR:
			next_code = 258
			bits = 9
			prev = -1
			continue
		if code == END:
			break

		var start := out_pos
		if prev < 0:
			out[out_pos] = code
			out_pos += 1
		else:
			var source := code if code < next_code else prev
			var length := lengths[source]
			if out_pos + length > expected_size:
				break
			var c := source
			var pos := out_pos + length - 1
			while c >= 0:
				out[pos] = suffix[c]
				pos -= 1
				c = prefix[c]
			out_pos += length
			if code >= next_code:
				if out_pos >= expected_size:
					break
				out[out_pos] = out[start]  # KwKwK: prev + first byte of prev
				out_pos += 1
			if next_code < MAX_CODES:
				prefix[next_code] = prev
				suffix[next_code] = out[start]
				lengths[next_code] = lengths[prev] + 1
				next_code += 1
		prev = code
		if next_code + 1 >= (1 << bits) and bits < MAX_BITS:
			bits += 1

	out.resize(out_pos)
	return out
