# KI native functions (engine API)

From `tools/ki/kinatives.py` (see [ki.md](ki.md)); usage counts are `call` instructions in
the 745 base-game modules (`kimodules/`) and the 566 expansion modules (`kimodules2/`).
Addresses are AmericaAddOn.exe's. "Handler" is the case in the dispatcher 0x43a250;
"in" = arguments in push order (the last one is on top of the stack), "out" = pushed results.
`ME` = the KI player's own number (CKIPlayer+0x828). `h` = object handle (VM.md section 7).
Orders are queued in the engine order queue 0x80b278 and executed by 0x456450 like a
human player's orders (code 0x1000000x = building orders, 0x2000000x = unit orders,
0x4000000x = player-level orders).

296 ids are implemented (by 240 handlers); 220 of them are used by the shipped modules (114776 calls in total).

## By usage

| # | id | name | base | exp. | total |
| --- | --- | --- | --- | --- | --- |
| 1 | 219 | `getglobal` | 5989 | 5437 | 11426 |
| 2 | 12 | `eq` | 8369 | 2858 | 11227 |
| 3 | 220 | `setglobal` | 5485 | 1666 | 7151 |
| 4 | 1 | `add` | 3712 | 3391 | 7103 |
| 5 | 335 | `random` | 2517 | 2860 | 5377 |
| 6 | 2 | `sub` | 3449 | 1862 | 5311 |
| 7 | 10 | `gt` | 2283 | 2772 | 5055 |
| 8 | 22 | `lnot` | 2363 | 1920 | 4283 |
| 9 | 41 | `wait` | 1319 | 2636 | 3955 |
| 10 | 11 | `lt` | 2802 | 1059 | 3861 |
| 11 | 137 | `can_build` | 2863 | 598 | 3461 |
| 12 | 245 | `tinsert_int` | 2536 | 898 | 3434 |
| 13 | 111 | `exists_unit` | 1006 | 2169 | 3175 |
| 14 | 42 | `aget_unit` | 1538 | 1491 | 3029 |
| 15 | 103 | `getx_unit` | 1017 | 1104 | 2121 |
| 16 | 104 | `gety_unit` | 1005 | 1100 | 2105 |
| 17 | 20 | `land` | 1201 | 672 | 1873 |
| 18 | 334 | `upgrade_known` | 1740 | 133 | 1873 |
| 19 | 308 | `me` | 0 | 1276 | 1276 |
| 20 | 237 | `tget_int` | 97 | 972 | 1069 |
| 21 | 384 | `claim_nearest_type` | 0 | 1028 | 1028 |
| 22 | 270 | `my_count` | 585 | 398 | 983 |
| 23 | 110 | `exists_building` | 245 | 694 | 939 |
| 24 | 328 | `attack_move` | 444 | 447 | 891 |
| 25 | 114 | `hasflags_unit` | 564 | 306 | 870 |
| 26 | 125 | `release_unit` | 220 | 641 | 861 |
| 27 | 3 | `mul` | 469 | 374 | 843 |
| 28 | 134 | `distance` | 386 | 359 | 745 |
| 29 | 31 | `aget_int` | 562 | 125 | 687 |
| 30 | 146 | `set_stance` | 83 | 576 | 659 |
| 31 | 246 | `tinsert_unit` | 156 | 488 | 644 |
| 32 | 43 | `aset_unit` | 393 | 243 | 636 |
| 33 | 21 | `lor` | 326 | 273 | 599 |
| 34 | 159 | `const_159` | 310 | 271 | 581 |
| 35 | 143 | `move` | 162 | 380 | 542 |
| 36 | 307 | `health_building` | 168 | 330 | 498 |
| 37 | 101 | `getx_building` | 288 | 207 | 495 |
| 38 | 102 | `gety_building` | 288 | 207 | 495 |
| 39 | 223 | `is_locked` | 379 | 109 | 488 |
| 40 | 221 | `lock` | 321 | 157 | 478 |
| 41 | 182 | `const_182` | 10 | 450 | 460 |
| 42 | 13 | `ne` | 213 | 225 | 438 |
| 43 | 32 | `aset_int` | 338 | 91 | 429 |
| 44 | 352 | `difficulty` | 186 | 235 | 421 |
| 45 | 197 | `const_197` | 34 | 367 | 401 |
| 46 | 6 | `bor` | 4 | 393 | 397 |
| 47 | 196 | `const_196` | 10 | 334 | 344 |
| 48 | 4 | `div` | 96 | 229 | 325 |
| 49 | 283 | `horses` | 311 | 0 | 311 |
| 50 | 273 | `my_horses` | 261 | 26 | 287 |
| 51 | 188 | `my_nation` | 169 | 117 | 286 |
| 52 | 222 | `unlock` | 127 | 159 | 286 |
| 53 | 105 | `getx_neutral` | 98 | 165 | 263 |
| 54 | 106 | `gety_neutral` | 98 | 165 | 263 |
| 55 | 123 | `release_building` | 71 | 181 | 252 |
| 56 | 14 | `ge` | 23 | 205 | 228 |
| 57 | 296 | `guid_unit` | 143 | 82 | 225 |
| 58 | 140 | `find_my_unit_type` | 113 | 107 | 220 |
| 59 | 112 | `exists_neutral` | 91 | 125 | 216 |
| 60 | 241 | `tremove_int` | 10 | 202 | 212 |
| 61 | 304 | `atomic_begin` | 194 | 6 | 200 |
| 62 | 305 | `atomic_end` | 194 | 6 | 200 |
| 63 | 183 | `const_183` | 70 | 112 | 182 |
| 64 | 124 | `release_neutral` | 78 | 103 | 181 |
| 65 | 238 | `tget_unit` | 14 | 165 | 179 |
| 66 | 339 | `count_in_area` | 129 | 39 | 168 |
| 67 | 289 | `unit_limit` | 53 | 85 | 138 |
| 68 | 113 | `hasflags_building` | 11 | 126 | 137 |
| 69 | 275 | `my_free_living_space` | 104 | 26 | 130 |
| 70 | 141 | `find_neutral_type` | 101 | 26 | 127 |
| 71 | 45 | `aget_building` | 20 | 103 | 123 |
| 72 | 242 | `tremove_unit` | 12 | 108 | 120 |
| 73 | 375 | `count_in_area_outside` | 108 | 9 | 117 |
| 74 | 117 | `hasanyflag_unit` | 7 | 110 | 117 |
| 75 | 297 | `guid_building` | 15 | 97 | 112 |
| 76 | 365 | `hasflags` | 104 | 7 | 111 |
| 77 | 280 | `count` | 96 | 11 | 107 |
| 78 | 151 | `const_151` | 102 | 2 | 104 |
| 79 | 139 | `find_my_building_type` | 17 | 84 | 101 |
| 80 | 145 | `attack` | 6 | 95 | 101 |
| 81 | 383 | `claim_nearest` | 0 | 99 | 99 |
| 82 | 225 | `map_height` | 5 | 89 | 94 |
| 83 | 136 | `can_train` | 7 | 85 | 92 |
| 84 | 250 | `attack_building` | 49 | 39 | 88 |
| 85 | 189 | `nation` | 56 | 31 | 87 |
| 86 | 224 | `map_width` | 4 | 82 | 86 |
| 87 | 211 | `enter` | 14 | 72 | 86 |
| 88 | 326 | `follow` | 21 | 60 | 81 |
| 89 | 336 | `stop` | 62 | 16 | 78 |
| 90 | 274 | `my_food` | 50 | 26 | 76 |
| 91 | 203 | `find_building_type_of` | 39 | 36 | 75 |
| 92 | 15 | `le` | 56 | 17 | 73 |
| 93 | 276 | `my_farms` | 70 | 3 | 73 |
| 94 | 354 | `group_attack_move` | 0 | 72 | 72 |
| 95 | 191 | `const_191` | 2 | 69 | 71 |
| 96 | 202 | `find_unit_of` | 60 | 11 | 71 |
| 97 | 204 | `find_unit_type_of` | 68 | 2 | 70 |
| 98 | 271 | `my_wood` | 35 | 31 | 66 |
| 99 | 144 | `build_repair` | 10 | 53 | 63 |
| 100 | 165 | `const_165` | 9 | 53 | 62 |
| 101 | 135 | `build_near` | 17 | 45 | 62 |
| 102 | 8 | `mod` | 24 | 37 | 61 |
| 103 | 156 | `const_156` | 12 | 48 | 60 |
| 104 | 392 | `nearest_building` | 0 | 56 | 56 |
| 105 | 171 | `const_171` | 42 | 13 | 55 |
| 106 | 293 | `last_build_x` | 10 | 45 | 55 |
| 107 | 294 | `last_build_y` | 10 | 45 | 55 |
| 108 | 372 | `nearest_wall` | 51 | 0 | 51 |
| 109 | 394 | `reachable_point` | 0 | 50 | 50 |
| 110 | 364 | `map_players` | 32 | 17 | 49 |
| 111 | 138 | `produce` | 8 | 39 | 47 |
| 112 | 205 | `find_neutral_type_owned` | 30 | 16 | 46 |
| 113 | 218 | `free_seats` | 12 | 33 | 45 |
| 114 | 109 | `find_my_unit` | 20 | 25 | 45 |
| 115 | 387 | `nearest_enemy` | 0 | 43 | 43 |
| 116 | 132 | `resource_left` | 18 | 23 | 41 |
| 117 | 376 | `add_food` | 12 | 27 | 39 |
| 118 | 108 | `find_neutral` | 13 | 25 | 38 |
| 119 | 373 | `attack_range` | 37 | 0 | 37 |
| 120 | 369 | `upgrade_done` | 6 | 31 | 37 |
| 121 | 377 | `add_wood` | 12 | 25 | 37 |
| 122 | 251 | `hunt` | 12 | 24 | 36 |
| 123 | 272 | `my_gold` | 16 | 20 | 36 |
| 124 | 240 | `tget_building` | 0 | 33 | 33 |
| 125 | 279 | `my_population` | 32 | 0 | 32 |
| 126 | 368 | `nearest_unit` | 2 | 29 | 31 |
| 127 | 378 | `add_gold` | 12 | 19 | 31 |
| 128 | 228 | `find_water` | 27 | 3 | 30 |
| 129 | 226 | `found_x` | 26 | 2 | 28 |
| 130 | 227 | `found_y` | 26 | 2 | 28 |
| 131 | 278 | `my_guns` | 22 | 6 | 28 |
| 132 | 367 | `owner_neutral` | 11 | 16 | 27 |
| 133 | 379 | `owner_unit` | 2 | 24 | 26 |
| 134 | 200 | `find_building_of` | 22 | 3 | 25 |
| 135 | 360 | `transport_to_` | 1 | 24 | 25 |
| 136 | 233 | `tset_int` | 17 | 7 | 24 |
| 137 | 154 | `const_154` | 10 | 11 | 21 |
| 138 | 292 | `build_near_at` | 3 | 18 | 21 |
| 139 | 371 | `nearest_type` | 10 | 11 | 21 |
| 140 | 133 | `transport_to` | 8 | 13 | 21 |
| 141 | 398 | `nearest_enemy_` | 0 | 21 | 21 |
| 142 | 303 | `cargo` | 0 | 20 | 20 |
| 143 | 277 | `my_fields` | 17 | 0 | 17 |
| 144 | 363 | `victory_condition` | 2 | 15 | 17 |
| 145 | 168 | `const_168` | 4 | 11 | 15 |
| 146 | 306 | `health_unit` | 6 | 9 | 15 |
| 147 | 380 | `claim` | 14 | 1 | 15 |
| 148 | 48 | `aget_neutral` | 15 | 0 | 15 |
| 149 | 370 | `nearest_excluding` | 4 | 9 | 13 |
| 150 | 234 | `tset_unit` | 4 | 9 | 13 |
| 151 | 300 | `stored_gold` | 8 | 5 | 13 |
| 152 | 353 | `energy_percent` | 6 | 6 | 12 |
| 153 | 147 | `self_destruct` | 1 | 11 | 12 |
| 154 | 175 | `const_175` | 0 | 12 | 12 |
| 155 | 184 | `const_184` | 0 | 12 | 12 |
| 156 | 142 | `produce_neutral` | 6 | 5 | 11 |
| 157 | 358 | `unload_all` | 3 | 8 | 11 |
| 158 | 46 | `aset_building` | 3 | 8 | 11 |
| 159 | 5 | `band` | 5 | 6 | 11 |
| 160 | 187 | `const_187` | 5 | 5 | 10 |
| 161 | 374 | `follow_` | 8 | 2 | 10 |
| 162 | 348 | `demolish` | 1 | 9 | 10 |
| 163 | 236 | `tset_building` | 0 | 10 | 10 |
| 164 | 120 | `first_my_building` | 0 | 9 | 9 |
| 165 | 115 | `hasflags_neutral` | 0 | 9 | 9 |
| 166 | 356 | `walk_speed` | 8 | 0 | 8 |
| 167 | 213 | `board` | 5 | 3 | 8 |
| 168 | 311 | `move_` | 6 | 2 | 8 |
| 169 | 192 | `const_192` | 4 | 4 | 8 |
| 170 | 395 | `reachable_point_from` | 0 | 8 | 8 |
| 171 | 130 | `chop_wood` | 6 | 1 | 7 |
| 172 | 329 | `next_attacked_building` | 5 | 2 | 7 |
| 173 | 359 | `stored_gold_` | 1 | 6 | 7 |
| 174 | 244 | `tremove_building` | 0 | 7 | 7 |
| 175 | 248 | `tinsert_building` | 0 | 7 | 7 |
| 176 | 215 | `camouflage` | 2 | 4 | 6 |
| 177 | 341 | `dig_in` | 3 | 3 | 6 |
| 178 | 150 | `const_150` | 2 | 3 | 5 |
| 179 | 185 | `const_185` | 3 | 2 | 5 |
| 180 | 252 | `work_field` | 2 | 3 | 5 |
| 181 | 206 | `my_relation` | 1 | 4 | 5 |
| 182 | 198 | `const_198` | 1 | 4 | 5 |
| 183 | 332 | `last_event_building` | 3 | 2 | 5 |
| 184 | 343 | `disarm_trap` | 2 | 3 | 5 |
| 185 | 355 | `set_rally_point` | 0 | 5 | 5 |
| 186 | 216 | `uncamouflage` | 2 | 2 | 4 |
| 187 | 346 | `convert` | 2 | 2 | 4 |
| 188 | 325 | `rob` | 4 | 0 | 4 |
| 189 | 330 | `next_attacked_unit` | 2 | 2 | 4 |
| 190 | 49 | `aset_neutral` | 4 | 0 | 4 |
| 191 | 361 | `animal_into` | 3 | 1 | 4 |
| 192 | 347 | `heal` | 2 | 2 | 4 |
| 193 | 149 | `worker_attack` | 2 | 2 | 4 |
| 194 | 121 | `first_my_unit` | 0 | 4 | 4 |
| 195 | 391 | `group_attack_` | 0 | 4 | 4 |
| 196 | 253 | `mount` | 2 | 1 | 3 |
| 197 | 131 | `mine_gold` | 2 | 1 | 3 |
| 198 | 321 | `spell_lightning` | 2 | 1 | 3 |
| 199 | 195 | `const_195` | 1 | 2 | 3 |
| 200 | 327 | `patrol` | 2 | 0 | 2 |
| 201 | 107 | `find_my_building` | 2 | 0 | 2 |
| 202 | 193 | `const_193` | 2 | 0 | 2 |
| 203 | 190 | `const_190` | 2 | 0 | 2 |
| 204 | 400 | `ability_charge` | 0 | 2 | 2 |
| 205 | 381 | `make_allies` | 0 | 2 | 2 |
| 206 | 393 | `nearest_type_` | 0 | 2 | 2 |
| 207 | 331 | `last_event_unit` | 0 | 2 | 2 |
| 208 | 388 | `resign` | 0 | 2 | 2 |
| 209 | 351 | `release_all` | 0 | 2 | 2 |
| 210 | 340 | `count_checked` | 1 | 0 | 1 |
| 211 | 217 | `free_garrison` | 1 | 0 | 1 |
| 212 | 290 | `can_build_default` | 1 | 0 | 1 |
| 213 | 194 | `const_194` | 1 | 0 | 1 |
| 214 | 199 | `my_corrals` | 1 | 0 | 1 |
| 215 | 401 | `building_ability` | 0 | 1 | 1 |
| 216 | 320 | `spell_eagle_eye` | 0 | 1 | 1 |
| 217 | 324 | `spell_rain` | 0 | 1 | 1 |
| 218 | 399 | `player_bonus` | 0 | 1 | 1 |
| 219 | 174 | `const_174` | 0 | 1 | 1 |
| 220 | 148 | `unsaddle` | 0 | 1 | 1 |

Implemented but never used: 7 `bxor`, 33 `acopy_int`, 40 `sleep`, 44 `acopy_unit`, 47 `acopy_building`, 50 `acopy_neutral`, 116 `hasanyflag_building`, 118 `hasanyflag_neutral`, 122 `first_object`, 152 `const_152`, 153 `const_153`, 155 `const_155`, 157 `const_157`, 158 `const_158`, 160 `const_160`, 161 `const_161`, 162 `const_162`, 163 `const_163`, 164 `const_164`, 166 `const_166`, 167 `const_167`, 169 `const_169`, 170 `const_170`, 172 `const_172`, 173 `const_173`, 176 `const_176`, 177 `const_177`, 178 `const_178`, 179 `const_179`, 180 `const_180`, 181 `const_181`, 186 `const_186`, 201 `find_object_of`, 207 `relation`, 210 `release_unit`, 212 `into_corral`, 214 `unload`, 229 `would_move`, 230 `list_count`, 231 `list_a`, 232 `list_b`, 235 `tset_neutral`, 239 `tget_neutral`, 243 `tremove_neutral`, 247 `tinsert_neutral`, 281 `wood`, 282 `gold`, 284 `food`, 285 `free_living_space`, 286 `farms`, 287 `fields`, 288 `guns`, 291 `can_train_default`, 295 `guid_neutral`, 301 `my_warehouse_gold`, 302 `warehouse_gold`, 310 `const_310`, 312 `owner_building`, 322 `spell_hail`, 323 `spell_protect`, 337 `producing`, 338 `cancel_production`, 342 `dig_out`, 344 `pack_tepee`, 345 `unpack_tepee`, 350 `const_350`, 357 `special_state`, 362 `zero`, 366 `hasanyflag`, 382 `make_enemies`, 385 `claim_first`, 386 `claim_first_type`, 389 `nearest_object`, 390 `group_attack`, 396 `reachable_x`, 397 `reachable_y`.

## Operators

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 1 | `add (a, b) -> a+b` | 7103 (3712+3391) | 0x43a26e | Integer addition (32-bit wrap). |
| 2 | `sub (a, b) -> a-b` | 5311 (3449+1862) | 0x43a29e | Subtraction. |
| 3 | `mul (a, b) -> a*b` | 843 (469+374) | 0x43a2ce | Multiplication (low 32 bits). |
| 4 | `div (a, b) -> a/b` | 325 (96+229) | 0x43a2fd | Signed division truncating toward 0; b == 0 is treated as 1. |
| 5 | `band (a, b) -> a&b` | 11 (5+6) | 0x43a338 | Bitwise and (used to test object flag masks). |
| 6 | `bor (a, b) -> a\|b` | 397 (4+393) | 0x43a368 | Bitwise or (used to combine flag constants). |
| 7 | `bxor (a, b) -> a^b` | 0 (0+0) | 0x43a398 | Bitwise xor. |
| 8 | `mod (a, b) -> a%b` | 61 (24+37) | 0x43a3c8 | Signed remainder (C `%`); b == 0 would fault in the original (idiv). |
| 10 | `gt (a, b) -> a>b` | 5055 (2283+2772) | 0x43a3f7 | Signed comparison, pushes 0/1. |
| 11 | `lt (a, b) -> a<b` | 3861 (2802+1059) | 0x43a42c | Signed comparison. |
| 12 | `eq (a, b) -> a==b` | 11227 (8369+2858) | 0x43a461 | Equality. |
| 13 | `ne (a, b) -> a!=b` | 438 (213+225) | 0x43a496 | Inequality. |
| 14 | `ge (a, b) -> a>=b` | 228 (23+205) | 0x43a4cb | Signed comparison. |
| 15 | `le (a, b) -> a<=b` | 73 (56+17) | 0x43a500 | Signed comparison. |
| 20 | `land (a, b) -> a&&b` | 1873 (1201+672) | 0x43a535 | Logical and (both operands already evaluated; no short circuit). |
| 21 | `lor (a, b) -> a\|\|b` | 599 (326+273) | 0x43a582 | Logical or (no short circuit). |
| 22 | `lnot (a) -> !a` | 4283 (2363+1920) | 0x43a5cd | Logical not. |

## Module arrays and waiting

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 31 | `aget_int (&arr, i) -> value` | 687 (562+125) | 0x43a5f3 | Element i of int array `arr` (passed with pushi). 0 <= i <= 1000 grows the array to i+10 elements (new ones 0); other i give 0. If `arr` does not resolve the handler returns without pushing. *(store 0x40f270 then 0x459e50)* |
| 32 | `aset_int (&arr, i, value)` | 429 (338+91) | 0x43a63f | arr[i] = value (same growth rule; i outside 0..1000 is ignored). *(store 0x40f270 then 0x459e20)* |
| 33 | `acopy_int (&dst, &src)` | 0 (0+0) | 0x43a68f | dst = copy of src (resized to src's size). *(0x459f00)* |
| 42 | `aget_unit (&arr, i) -> value` | 3029 (1538+1491) | 0x43a5f3 | Element i of unit array `arr` (passed with pushi). 0 <= i <= 1000 grows the array to i+10 elements (new ones 0); other i give 0. If `arr` does not resolve the handler returns without pushing. *(store 0x40f270 then 0x459e50)* |
| 43 | `aset_unit (&arr, i, value)` | 636 (393+243) | 0x43a63f | arr[i] = value (same growth rule; i outside 0..1000 is ignored). *(store 0x40f270 then 0x459e20)* |
| 44 | `acopy_unit (&dst, &src)` | 0 (0+0) | 0x43a68f | dst = copy of src (resized to src's size). *(0x459f00)* |
| 45 | `aget_building (&arr, i) -> value` | 123 (20+103) | 0x43a5f3 | Element i of building array `arr` (passed with pushi). 0 <= i <= 1000 grows the array to i+10 elements (new ones 0); other i give 0. If `arr` does not resolve the handler returns without pushing. *(store 0x40f270 then 0x459e50)* |
| 46 | `aset_building (&arr, i, value)` | 11 (3+8) | 0x43a63f | arr[i] = value (same growth rule; i outside 0..1000 is ignored). *(store 0x40f270 then 0x459e20)* |
| 47 | `acopy_building (&dst, &src)` | 0 (0+0) | 0x43a68f | dst = copy of src (resized to src's size). *(0x459f00)* |
| 48 | `aget_neutral (&arr, i) -> value` | 15 (15+0) | 0x43a5f3 | Element i of neutral array `arr` (passed with pushi). 0 <= i <= 1000 grows the array to i+10 elements (new ones 0); other i give 0. If `arr` does not resolve the handler returns without pushing. *(store 0x40f270 then 0x459e50)* |
| 49 | `aset_neutral (&arr, i, value)` | 4 (4+0) | 0x43a63f | arr[i] = value (same growth rule; i outside 0..1000 is ignored). *(store 0x40f270 then 0x459e20)* |
| 50 | `acopy_neutral (&dst, &src)` | 0 (0+0) | 0x43a68f | dst = copy of src (resized to src's size). *(0x459f00)* |
| 40 | `sleep (ms)` | 0 (0+0) | 0x43a6d3 | Sleep: module+0x664 = ms; the module executes nothing until that many ms of game time have passed (decremented by 20*KISpeed per tick). Identical to 41. *(0x43ec10)* |
| 41 | `wait (ms)` | 3955 (1319+2636) | 0x43a6d3 | Same handler as 40; the id the compiler emits for `wait` (40 is never used). *(0x43ec10)* |

## Shared KI state: globals, tables, semaphores, atomic sections, events

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 219 | `getglobal (i) -> v` | 11426 (5989+5437) | 0x43b964 | KI-wide global i (KI+0x19938, 256 ints shared by all modules of the player); 0 if i outside 0..255. |
| 220 | `setglobal (i, v)` | 7151 (5485+1666) | 0x43b99d | global[i] = v (ignored outside 0..255). |
| 233 | `tset_int (t, i, v)` | 24 (17+7) | 0x43bc83 | table[t][i] = v (KI+0x930 + (t*256+i)*4); t 0..99, i 0..255, else ignored. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 234 | `tset_unit (t, i, v)` | 13 (4+9) | 0x43bc83 | table[t][i] = v (KI+0x930 + (t*256+i)*4); t 0..99, i 0..255, else ignored. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 235 | `tset_neutral (t, i, v)` | 0 (0+0) | 0x43bc83 | table[t][i] = v (KI+0x930 + (t*256+i)*4); t 0..99, i 0..255, else ignored. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 236 | `tset_building (t, i, v)` | 10 (0+10) | 0x43bc83 | table[t][i] = v (KI+0x930 + (t*256+i)*4); t 0..99, i 0..255, else ignored. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 237 | `tget_int (t, i) -> v` | 1069 (97+972) | 0x43bce5 | table[t][i]; 0 if out of range. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 238 | `tget_unit (t, i) -> v` | 179 (14+165) | 0x43bce5 | table[t][i]; 0 if out of range. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 239 | `tget_neutral (t, i) -> v` | 0 (0+0) | 0x43bce5 | table[t][i]; 0 if out of range. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 240 | `tget_building (t, i) -> v` | 33 (0+33) | 0x43bce5 | table[t][i]; 0 if out of range. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 241 | `tremove_int (t, i)` | 212 (10+202) | 0x43bd45 | Remove element i: table[t][i..254] = table[t][i+1..255], table[t][255] = 0. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 242 | `tremove_unit (t, i)` | 120 (12+108) | 0x43bd45 | Remove element i: table[t][i..254] = table[t][i+1..255], table[t][255] = 0. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 243 | `tremove_neutral (t, i)` | 0 (0+0) | 0x43bd45 | Remove element i: table[t][i..254] = table[t][i+1..255], table[t][255] = 0. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 244 | `tremove_building (t, i)` | 7 (0+7) | 0x43bd45 | Remove element i: table[t][i..254] = table[t][i+1..255], table[t][255] = 0. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 245 | `tinsert_int (t, i, v)` | 3434 (2536+898) | 0x43bdd0 | Insert at i: elements i..254 move up one (255 is lost), table[t][i] = v. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 246 | `tinsert_unit (t, i, v)` | 644 (156+488) | 0x43bdd0 | Insert at i: elements i..254 move up one (255 is lost), table[t][i] = v. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 247 | `tinsert_neutral (t, i, v)` | 0 (0+0) | 0x43bdd0 | Insert at i: elements i..254 move up one (255 is lost), table[t][i] = v. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 248 | `tinsert_building (t, i, v)` | 7 (0+7) | 0x43bdd0 | Insert at i: elements i..254 move up one (255 is lost), table[t][i] = v. (The four ids of the group share one handler; the compiler picks one by element type.) |
| 221 | `lock (k)` | 478 (321+157) | 0x43b9d9 | Take semaphore k (KI+0x82d+k). If it is taken the module blocks until it is free (module+0x658 = k; 0x43efa0). k outside 0..255: no effect. *(0x43efa0)* |
| 222 | `unlock (k)` | 286 (127+159) | 0x43ba0b | sem[k] = 0. |
| 223 | `is_locked (k) -> bool` | 488 (379+109) | 0x43ba37 | sem[k] == 1; 0 outside range. |
| 304 | `atomic_begin ()` | 200 (194+6) | 0x43c055 | KI+0x818 = 1, KI+0x81c = current slot: all other modules of this player stop executing (timers still run) until atomic_end. |
| 305 | `atomic_end ()` | 200 (194+6) | 0x43c070 | KI+0x818 = 0. |
| 329 | `next_attacked_building () -> bool` | 7 (5+2) | 0x43c351 | Pop the oldest handle from the player's "building damaged" queue (filled by the building damage routine 0x40c970 via 0x42d070) into module+0x4; false if empty. Read it with 332. *(0x43dd40)* |
| 330 | `next_attacked_unit () -> bool` | 4 (2+2) | 0x43c366 | Same for the "unit damaged" queue (unit damage routine 0x418f90 via 0x42d0b0). Read with 331. *(0x43dd80)* |
| 331 | `last_event_unit () -> h` | 2 (0+2) | 0x43c3a3 | module+0x4 (handle taken by 329/330). |
| 332 | `last_event_building () -> h` | 5 (3+2) | 0x43c3bc | module+0x4 (same field as 331). |

## Constants

Pushed constants: class/state flag masks, stance values, diplomacy values and GUIDs (see "Flags").

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 150 | `const_150 () -> 0x20000` | 5 (2+3) | 0x43a746 | Pushes 0x20000 (class bit: main building (HQ)). |
| 151 | `const_151 () -> 8` | 104 (102+2) | 0x43a75c | Pushes 8 (class bit: gold mine (types 700-703)). |
| 152 | `const_152 () -> 4` | 0 (0+0) | 0x43a76f | Pushes 4 (class building / state idle). |
| 153 | `const_153 () -> 2` | 0 (0+0) | 0x43a782 | Pushes 2 (class bit: unit). |
| 154 | `const_154 () -> 0x40` | 21 (10+11) | 0x43a795 | Pushes 0x40 (class bit 0x40 = tent; with find_neutral any mask containing 0x10 or 0x40 switches to the tree grid search, which is how the scripts find trees). |
| 155 | `const_155 () -> 0x10` | 0 (0+0) | 0x43a7a8 | Pushes 0x10 (class bit: tree (types 500-535, map grid list 9)). |
| 156 | `const_156 () -> 1` | 60 (12+48) | 0x43c37d | Pushes 1 (state 0x1 (worker task) / relation bit hostile). |
| 157 | `const_157 () -> 0x800` | 0 (0+0) | 0x43a7bb | Pushes 0x800 (class bit: gatherer (receives gold-mining orders)). |
| 158 | `const_158 () -> 0x1000000` | 0 (0+0) | 0x43a7d1 | Pushes 0x1000000 (class bit: civilian worker (receives wood-cutting orders)). |
| 159 | `const_159 () -> 4` | 581 (310+271) | 0x43a76f | Pushes 4 (class building / state idle (units) or finished (buildings)). |
| 160 | `const_160 () -> 0x8000` | 0 (0+0) | 0x43a7e7 | Pushes 0x8000 (class bit: builder). |
| 161 | `const_161 () -> 0x1a3` | 0 (0+0) | 0x43a7fd | Pushes 0x1a3 (GUID 419 (USA gold store)). |
| 162 | `const_162 () -> 0x199` | 0 (0+0) | 0x43a813 | Pushes 0x199 (GUID 409 (USA saw mill)). |
| 163 | `const_163 () -> 0x1c7` | 0 (0+0) | 0x43a829 | Pushes 0x1c7 (GUID 455 (covered wagon)). |
| 164 | `const_164 () -> 8` | 0 (0+0) | 0x43a75c | Pushes 8 (class bit: gold mine (types 700-703)). |
| 165 | `const_165 () -> 0x10` | 62 (9+53) | 0x43a9a9 | Pushes 0x10 (state producing (buildings) / class 0x10 tree). |
| 166 | `const_166 () -> 0x40000` | 0 (0+0) | 0x43a83f | Pushes 0x40000 (class bit: wagon). |
| 167 | `const_167 () -> 2` | 0 (0+0) | 0x43a983 | Pushes 2 (class bit: unit). |
| 168 | `const_168 () -> 0x80` | 15 (4+11) | 0x43a855 | Pushes 0x80 (state worker task bit / relation: human). |
| 169 | `const_169 () -> 0x20` | 0 (0+0) | 0x43a9e8 | Pushes 0x20 (class bit: livestock (buffalo, cow)). |
| 170 | `const_170 () -> 0x400` | 0 (0+0) | 0x43a9bc | Pushes 0x400 (class bit: armed unit (also the trap building)). |
| 171 | `const_171 () -> 0x1000` | 55 (42+13) | 0x43a86b | Pushes 0x1000 (class military / state below 40% HP). |
| 172 | `const_172 () -> 0x2000` | 0 (0+0) | 0x43a881 | Pushes 0x2000 (class bit: can ride). |
| 173 | `const_173 () -> 0x4000` | 0 (0+0) | 0x43a897 | Pushes 0x4000 (class bit: can garrison / building that takes a garrison). |
| 174 | `const_174 () -> 0x10000` | 1 (0+1) | 0x43a8ad | Pushes 0x10000 (class bit: gatherer). |
| 175 | `const_175 () -> 0x80000` | 12 (0+12) | 0x43a8c3 | Pushes 0x80000 (class bit: storage building (set at run time)). |
| 176 | `const_176 () -> 0x100000` | 0 (0+0) | 0x43a8d9 | Pushes 0x100000 (class bit: farm / granary). |
| 177 | `const_177 () -> 0x200000` | 0 (0+0) | 0x43a8ef | Pushes 0x200000 (class bit: exhausted field). |
| 178 | `const_178 () -> 0x400000` | 0 (0+0) | 0x43a905 | Pushes 0x400000 (class bit: field). |
| 179 | `const_179 () -> 0x800000` | 0 (0+0) | 0x43a91b | Pushes 0x800000 (class bit: women). |
| 180 | `const_180 () -> 0x2000000` | 0 (0+0) | 0x43a931 | Pushes 0x2000000 (class bit: horse). |
| 181 | `const_181 () -> 0x4000000` | 0 (0+0) | 0x43a947 | Pushes 0x4000000 (class bit: animal). |
| 182 | `const_182 () -> 0` | 460 (10+450) | 0x43a95d | Pushes 0 (stance 0). |
| 183 | `const_183 () -> 1` | 182 (70+112) | 0x43c37d | Pushes 1 (stance 1). |
| 184 | `const_184 () -> 2` | 12 (0+12) | 0x43a983 | Pushes 2 (stance 2). |
| 185 | `const_185 () -> 3` | 5 (3+2) | 0x43a970 | Pushes 3 (stance 3). |
| 186 | `const_186 () -> 0x191` | 0 (0+0) | 0x43aa1e | Pushes 0x191 (GUID 401 (USA house)). |
| 187 | `const_187 () -> 0x40` | 10 (5+5) | 0x43aa34 | Pushes 0x40 (relation: computer / class tent). |
| 190 | `const_190 () -> 0x100` | 2 (2+0) | 0x43aa94 | Pushes 0x100 (state moving). |
| 191 | `const_191 () -> 0x200` | 71 (2+69) | 0x43aaaa | Pushes 0x200 (state under construction). |
| 192 | `const_192 () -> 1` | 8 (4+4) | 0x43c37d | Pushes 1 (relation bit: hostile). |
| 193 | `const_193 () -> 2` | 2 (2+0) | 0x43a983 | Pushes 2 (relation bit 0x2). |
| 194 | `const_194 () -> 4` | 1 (1+0) | 0x43a996 | Pushes 4 (relation bit: allied). |
| 195 | `const_195 () -> 8` | 3 (1+2) | 0x43a75c | Pushes 8 (relation: same player (8)). |
| 196 | `const_196 () -> 0x400` | 344 (10+334) | 0x43a9bc | Pushes 0x400 (state inside a transport). |
| 197 | `const_197 () -> 0x800` | 401 (34+367) | 0x43a9d2 | Pushes 0x800 (state inside a building). |
| 198 | `const_198 () -> 0x10` | 5 (1+4) | 0x43a9a9 | Pushes 0x10 (relation: player absent (0x10)). |
| 310 | `const_310 () -> 0x20` | 0 (0+0) | 0x43a9e8 | Pushes 0x20 (class bit: livestock (buffalo, cow)). |
| 350 | `const_350 () -> 0x1000` | 0 (0+0) | 0x43c6a5 | Pushes 0x1000 (class bit: military). |

## Object queries

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 101 | `getx_building (h) -> x` | 495 (288+207) | 0x43a6f2 | X position in map pixels of the building (obj+0x2c); -1 if the handle does not resolve. *(0x4384a0)* |
| 102 | `gety_building (h) -> y` | 495 (288+207) | 0x43a71c | Y position in map pixels (obj+0x30); -1 if gone. *(0x4384c0)* |
| 103 | `getx_unit (h) -> x` | 2121 (1017+1104) | 0x43a6f2 | X position in map pixels of the unit (obj+0x2c); -1 if the handle does not resolve. *(0x4384a0)* |
| 104 | `gety_unit (h) -> y` | 2105 (1005+1100) | 0x43a71c | Y position in map pixels (obj+0x30); -1 if gone. *(0x4384c0)* |
| 105 | `getx_neutral (h) -> x` | 263 (98+165) | 0x43a6f2 | X position in map pixels of the neutral (obj+0x2c); -1 if the handle does not resolve. *(0x4384a0)* |
| 106 | `gety_neutral (h) -> y` | 263 (98+165) | 0x43a71c | Y position in map pixels (obj+0x30); -1 if gone. *(0x4384c0)* |
| 110 | `exists_building (h) -> bool` | 939 (245+694) | 0x43aac0 | True if h != 0 and the object still exists (0x42b820 finds it). The scripts' "is alive" test. *(0x438d90)* |
| 111 | `exists_unit (h) -> bool` | 3175 (1006+2169) | 0x43aac0 | True if h != 0 and the object still exists (0x42b820 finds it). The scripts' "is alive" test. *(0x438d90)* |
| 112 | `exists_neutral (h) -> bool` | 216 (91+125) | 0x43aac0 | True if h != 0 and the object still exists (0x42b820 finds it). The scripts' "is alive" test. *(0x438d90)* |
| 113 | `hasflags_building (h, mask) -> bool` | 137 (11+126) | 0x43b925 | (state(obj) & mask) == mask, state = the dynamic flags returned by virtual +0x2c (see "Flags"); false if gone. E.g. hasflags_unit(e, 4) = idle, hasflags_building(b, 0x10) = producing. *(0x438500)* |
| 114 | `hasflags_unit (h, mask) -> bool` | 870 (564+306) | 0x43b925 | (state(obj) & mask) == mask, state = the dynamic flags returned by virtual +0x2c (see "Flags"); false if gone. E.g. hasflags_unit(e, 4) = idle, hasflags_building(b, 0x10) = producing. *(0x438500)* |
| 115 | `hasflags_neutral (h, mask) -> bool` | 9 (0+9) | 0x43b925 | (state(obj) & mask) == mask, state = the dynamic flags returned by virtual +0x2c (see "Flags"); false if gone. E.g. hasflags_unit(e, 4) = idle, hasflags_building(b, 0x10) = producing. *(0x438500)* |
| 116 | `hasanyflag_building (h, mask) -> bool` | 0 (0+0) | 0x43c115 | (state(obj) & mask) != 0. *(0x438530)* |
| 117 | `hasanyflag_unit (h, mask) -> bool` | 117 (7+110) | 0x43c115 | (state(obj) & mask) != 0. *(0x438530)* |
| 118 | `hasanyflag_neutral (h, mask) -> bool` | 0 (0+0) | 0x43c115 | (state(obj) & mask) != 0. *(0x438530)* |
| 365 | `hasflags (h, mask) -> bool` | 111 (104+7) | 0x43c96e | (class(obj) & mask) == mask with the static class flags obj+0x24 (0x4324a0), e.g. hasflags(e, 0x2000) = can ride, 0x80000000 = leader. *(0x439850)* |
| 366 | `hasanyflag (h, mask) -> bool` | 0 (0+0) | 0x43c9ad | (class(obj) & mask) != 0 (class flags obj+0x24). *(0x439880)* |
| 295 | `guid_neutral (h) -> guid` | 0 (0+0) | 0x43bf8a | Object type GUID (obj+0xc, e.g. 104, 458); -1 if gone. *(0x438d70)* |
| 296 | `guid_unit (h) -> guid` | 225 (143+82) | 0x43bf8a | Object type GUID (obj+0xc, e.g. 104, 458); -1 if gone. *(0x438d70)* |
| 297 | `guid_building (h) -> guid` | 112 (15+97) | 0x43bf8a | Object type GUID (obj+0xc, e.g. 104, 458); -1 if gone. *(0x438d70)* |
| 312 | `owner_building (h) -> player` | 0 (0+0) | 0x43c0eb | Owner player number (obj+0x14); 0 if gone. (Ids 312/367/379 share one handler; the scripts use 379 for units and 367 for cattle.) *(0x4398b0)* |
| 367 | `owner_neutral (h) -> player` | 27 (11+16) | 0x43c9ec | Owner player number (obj+0x14); 0 if gone. (Ids 312/367/379 share one handler; the scripts use 379 for units and 367 for cattle.) *(0x4398b0)* |
| 379 | `owner_unit (h) -> player` | 26 (2+24) | 0x43c9ec | Owner player number (obj+0x14); 0 if gone. (Ids 312/367/379 share one handler; the scripts use 379 for units and 367 for cattle.) *(0x4398b0)* |
| 306 | `health_unit (h) -> percent` | 15 (6+9) | 0x43c07f | Hit points in percent: obj+0x4 * 100 / obj+0x470 (units); -1 if gone. *(0x438e60)* |
| 307 | `health_building (h) -> percent` | 498 (168+330) | 0x43c0a9 | Hit points in percent: obj+0x4 * 100 / obj+0x578 (buildings); -1 if gone. *(0x438e20)* |
| 132 | `resource_left (h) -> amount` | 41 (18+23) | 0x43b11a | obj+0x9c (0x423c70): what is left in a gold mine (class 0x8, types 700-703); the scripts test `> 0` before sending miners. 0 if gone. *(0x4385f0)* |
| 217 | `free_garrison (building) -> n` | 1 (1+0) | 0x43b094 | Garrison capacity obj+0xdc (building property 8, max 10) minus units inside obj+0xd8. *(0x438f80)* |
| 218 | `free_seats (transport) -> n` | 45 (12+33) | 0x43b0be | Passenger capacity obj+0x3d4 (raft 8, riverboats 8/10, stagecoach 2, default 4) minus passengers obj+0x3d0. *(0x438fb0)* |
| 300 | `stored_gold (building) -> n` | 13 (8+5) | 0x43bfb4 | obj+0x6fc of a storage building: amount stored (gold in a gold warehouse); -1 if gone. (Other classes use +0x6fc differently: a gatherer's resource object, a fighter's leash radius.) *(0x438db0)* |
| 359 | `stored_gold_ (building) -> n` | 7 (1+6) | 0x43c8c2 | Same field as 300, 0 if gone. *(0x439800)* |
| 303 | `cargo (wagon) -> n` | 20 (0+20) | 0x43c02b | obj+0x6b0: cargo loaded on a wagon (travois, covered wagon, stagecoach); kind at +0x6b4. 0 if gone. *(0x438df0)* |
| 337 | `producing (building) -> guid` | 0 (0+0) | 0x43c465 | Type id currently in production (queue +0x108[0]) if the queue (+0x104) is not empty, else 0. *(0x4392f0)* |
| 353 | `energy_percent (unit) -> percent` | 12 (6+6) | 0x43c707 | Magic/healing energy: obj+0x394 * 100 / obj+0x380 if the unit has an energy pool (byte +0x398: medicine man, nurse, nun, priest...), else 0. Energy refills 1 per tick up to 10000 (15000 with upgrade 917). *(0x439530)* |
| 356 | `walk_speed (unit) -> speed` | 8 (8+0) | 0x43c84e | obj+0x47c: LaufenSpeed table value (50..160) from property 110; 0 if gone. *(0x439760)* |
| 357 | `special_state (h) -> n` | 0 (0+0) | 0x43c878 | obj+0x700: assassin 0 normal / 1 dug in / 2 stalking / 4 struck; field bit 1 growing, bit 2 ripe; trap 1 armed. 0 if gone. *(0x439780)* |
| 373 | `attack_range (unit) -> px` | 37 (37+0) | 0x43cc79 | obj+0x3e4: ranged attack range in px (64, 100, 200, 350, 500 by property 115); used as search radius. 0 if gone. *(0x439ab0)* |
| 400 | `ability_charge (building) -> 0..100` | 2 (0+2) | 0x43d249 | obj+0xa0 >> 8: the building ability meter (grows 1 per 5.12 s after upgrade 965 or 968-970; 401 costs 25, 399 costs 75). 0 if gone. *(0x439e10)* |
| 134 | `distance (x1, y1, x2, y2) -> d` | 745 (386+359) | 0x43b1a8 | Euclidean distance, `(int)sqrt(dx*dx + dy*dy)` (x87 fsqrt, truncated by 0x49bb26 = _ftol). |

## Searches and claims

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 107 | `find_my_building (mask, x, y, state) -> h` | 2 (2+0) | 0x43aba8 | Nearest (squared distance to x,y) object in player ME's list whose class flags contain all bits of `mask` \| 4 (building) and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560 -> 0x42bce0 -> 0x424ad0)* |
| 108 | `find_neutral (mask, x, y, state) -> h` | 38 (13+25) | 0x43ac4c | Nearest (squared distance to x,y) object in player 0 (neutral objects: trees 0x40, mines 0x8, stores...)'s list whose class flags contain all bits of `mask` and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560 -> 0x42bce0)* |
| 109 | `find_my_unit (mask, x, y, state) -> h` | 45 (20+25) | 0x43abe8 | Nearest (squared distance to x,y) object in player ME's list whose class flags contain all bits of `mask` \| 2 (unit) and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560 -> 0x42bce0)* |
| 200 | `find_building_of (player, mask, x, y, state) -> h` | 25 (22+3) | 0x43acaf | Nearest (squared distance to x,y) object in player `player`'s list whose class flags contain all bits of `mask` \| 4 and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560)* |
| 201 | `find_object_of (player, mask, x, y, state) -> h` | 0 (0+0) | 0x43ad97 | Nearest (squared distance to x,y) object in player `player`'s list whose class flags contain all bits of `mask` and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560)* |
| 202 | `find_unit_of (player, mask, x, y, state) -> h` | 71 (60+11) | 0x43ad23 | Nearest (squared distance to x,y) object in player `player`'s list whose class flags contain all bits of `mask` \| 2 and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed. *(0x438560)* |
| 139 | `find_my_building_type (guid, x, y, state) -> h` | 101 (17+84) | 0x43b335 | Nearest object of type `guid` (obj+0xc) in player ME's list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0. *(0x438a60 -> 0x42bd70 -> 0x424e10)* |
| 140 | `find_my_unit_type (guid, x, y, state) -> h` | 220 (113+107) | 0x43b335 | Nearest object of type `guid` (obj+0xc) in player ME's list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0. (same handler as 139) *(0x438a60)* |
| 141 | `find_neutral_type (guid, x, y, state) -> h` | 127 (101+26) | 0x43b397 | Nearest object of type `guid` (obj+0xc) in player 0's list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0. Horses 480, buffalo 481, cows 482. *(0x438a60)* |
| 203 | `find_building_type_of (player, guid, x, y, state) -> h` | 75 (39+36) | 0x43ae09 | Nearest object of type `guid` (obj+0xc) in player `player`'s list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0. *(0x438a60)* |
| 204 | `find_unit_type_of (player, guid, x, y, state) -> h` | 70 (68+2) | 0x43ae09 | Nearest object of type `guid` (obj+0xc) in player `player`'s list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0. (same handler as 203) *(0x438a60)* |
| 205 | `find_neutral_type_owned (player, guid, x, y, state) -> h` | 46 (30+16) | 0x43ae7a | Nearest object of type guid in the neutral list (player 0) whose owner (obj+0x14) is `player` (cattle and horses in a player's corral), state any-of, unclaimed; claims it. *(0x438a90 -> 0x424ec0)* |
| 368 | `nearest_unit (player, x, y, mask, state) -> h` | 31 (2+29) | 0x43ca16 | Nearest object in player `player`'s list with class flags containing mask\|2 and state any-of `state` (or 0); no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8). *(0x4398d0 -> 0x424c40)* |
| 389 | `nearest_object (player, x, y, mask, state) -> h` | 0 (0+0) | 0x43ca62 | Nearest object in player `player`'s list with class flags containing mask and state any-of `state` (or 0); no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8). *(0x4398d0 -> 0x424c40)* |
| 392 | `nearest_building (player, x, y, mask, state) -> h` | 56 (0+56) | 0x43caa8 | Nearest object in player `player`'s list with class flags containing mask\|4 and state any-of `state` (or 0); no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8). *(0x4398d0 -> 0x424c40)* |
| 370 | `nearest_excluding (player, x, y, mask, notstate) -> h` | 13 (4+9) | 0x43cb4b | Nearest object in player `player`'s list with class flags containing mask and (state & notstate) == 0; no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8). *(0x4399c0 -> 0x424ce0)* |
| 371 | `nearest_type (player, x, y, guid, notstate) -> h` | 21 (10+11) | 0x43cbb5 | Nearest object in player `player`'s list with type guid and (state & notstate) == 0; no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8). *(0x439a10 -> 0x424d80)* |
| 393 | `nearest_type_ (player, x, y, guid, notstate) -> h` | 2 (0+2) | 0x43cbb5 | Same handler as 371. *(0x439a10)* |
| 383 | `claim_nearest (player, x, y, mask, notstate) -> h` | 99 (0+99) | 0x43ce30 | Nearest in player's list with class containing mask\|2, (state & notstate) == 0, not claimed by me; claims it (sets obj+0x1c bit). *(0x439b40 -> 0x4252e0)* |
| 384 | `claim_nearest_type (player, x, y, guid, notstate) -> h` | 1028 (0+1028) | 0x43cea4 | Nearest of type guid with (state & notstate) == 0, not claimed by me; claims it. The standard way to pick an idle own unit: `e = claim_nearest_type(me(), mainx, mainy, 459, 0xc00)`. *(0x439b90 -> 0x4253b0)* |
| 385 | `claim_first (player, ignored, notstate) -> h` | 0 (0+0) | 0x43cf15 | First object (list order) in player's list with (state & notstate) == 0 not claimed by me (class mask 0 = any; the second argument is replaced by 0); claims it. Unused. *(0x439be0 -> 0x425470)* |
| 386 | `claim_first_type (player, guid, notstate) -> h` | 0 (0+0) | 0x43cf69 | First object of type guid, (state & notstate) == 0, not claimed by me; claims it. *(0x439c30 -> 0x4254e0)* |
| 387 | `nearest_enemy (x, y, classany, notstate) -> h` | 43 (0+43) | 0x43d1c8 | First object found ring by ring within 500 px of (x, y) in the object grid (0x7d2a8c, 0x45df50) that is hostile to me, has any of the class bits and none of the state bits. 0 if none. *(0x439ca0)* |
| 398 | `nearest_enemy_ (x, y, classany, notstate) -> h` | 21 (0+21) | 0x43d1c8 | Same handler as 387. *(0x439ca0)* |
| 372 | `nearest_wall (player, x, y, radius) -> h` | 51 (51+0) | 0x43cc1f | Nearest wall/palisade cell of `player` within radius (wall list 0x7d29f4, 0x448790; the wall grid byte holds the owner); handle of that wall segment or 0. *(0x439a60)* |
| 380 | `claim (h)` | 15 (14+1) | 0x43cda5 | Claim the object for me (virtual +0x28(me): obj+0x1c \|= 1<<me) so my claiming searches skip it. *(0x439ad0)* |
| 123 | `release_building (h)` | 252 (71+181) | 0x43ab81 | Release my claim (virtual +0x24(me)): the object can be found again by my claiming searches. (123-125 share one handler.) *(0x438620)* |
| 124 | `release_neutral (h)` | 181 (78+103) | 0x43ab81 | Release my claim (virtual +0x24(me)): the object can be found again by my claiming searches. (123-125 share one handler.) *(0x438620)* |
| 125 | `release_unit (h)` | 861 (220+641) | 0x43ab81 | Release my claim (virtual +0x24(me)): the object can be found again by my claiming searches. (123-125 share one handler.) *(0x438620)* |
| 120 | `first_my_building (mask) -> h` | 9 (0+9) | 0x43aaef | world 0x42bca0(me, mask\|4, 0) -> 0x424a70: first (list order) own object whose class contains mask\|4 and that is active (virtual +0x54); scripts: mask 0x20000 = main building. *(0x4384e0)* |
| 121 | `first_my_unit (mask) -> h` | 4 (0+4) | 0x43ab22 | 0x42bca0(me, mask\|2, 0): first own unit with those class bits (0x40000 = covered wagon / settler wagon, 0x80000000). *(0x4384e0)* |
| 122 | `first_object (mask) -> h` | 0 (0+0) | 0x43ab55 | 0x42bca0(0, mask, 0) over player 0. *(0x4384e0)* |
| 339 | `count_in_area (player, guid, x, y, r) -> n` | 168 (129+39) | 0x43c4af | Objects of player (0..10) of type guid (or category: 0 all units, 1-4 units per nation, 5 all buildings, 6-9 buildings per nation, 16 all military, 17-20 military per nation) inside the square x-r..x+r, y-r..y+r (0x42ad00, PtInRect). Animals 480-483 count for any owner. Sets world+0x4c = 0 first (count units inside buildings too). *(0x439340)* |
| 375 | `count_in_area_outside (player, guid, x, y, r) -> n` | 117 (108+9) | 0x43cca3 | Same with world+0x4c = 1: units inside buildings or transports are not counted. *(0x439340)* |
| 228 | `find_water (x, y) -> bool` | 30 (27+3) | 0x43baf1 | Ring search in 16 px steps from (x, y) over the map cell flags (0x7d2a54, 0x407d80) for a cell with flag 8 (water); on success stores it in module+0x114/+0x118 (read by 226/227) and returns 1. *(0x439030)* |
| 226 | `found_x () -> x` | 28 (26+2) | 0x43bab9 | module+0x114 from 228. |
| 227 | `found_y () -> y` | 28 (26+2) | 0x43bad5 | module+0x118 from 228. |
| 229 | `would_move (unit, x, y) -> bool` | 0 (0+0) | 0x43bb5d | Snaps (x, y) to the centre of the nearest cell passable for the unit's movement class (0x419ba0, up to 32 rings); true if that differs from the unit's position. On true the handler also stores two values in module+0x124/+0x128 (freeing the old +0x124 block), which 230-232 read as a pair list - apparently left over from an earlier design. Unused by the shipped modules. *(0x439050)* |
| 230 | `list_count () -> n` | 0 (0+0) | 0x43bbe6 | module+0x128 (229's list size). |
| 231 | `list_a (i) -> a` | 0 (0+0) | 0x43bc02 | First dword of pair i of the module list (0 if out of range). |
| 232 | `list_b (i) -> b` | 0 (0+0) | 0x43bc42 | Second dword of pair i. |
| 394 | `reachable_point (unit, x, y) -> bool` | 50 (0+50) | 0x43d09a | Pathfinder 0x45f6a0(unit movement class +0x4ac, unit x, y, &x, &y): moves (x, y) to the nearest cell reachable from the unit; result in module+0x11c/+0x120 (read by 396/397) whether or not it succeeded; returns true if found. *(0x439d80)* |
| 395 | `reachable_point_from (moveclass, fromx, fromy, x, y) -> bool` | 8 (0+8) | 0x43d107 | Same with an explicit movement class and start point. *(0x439dc0)* |
| 396 | `reachable_x () -> x` | 0 (0+0) | 0x43d190 | module+0x11c. |
| 397 | `reachable_y () -> y` | 0 (0+0) | 0x43d1ac | module+0x120. |

## Player, economy and match state

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 308 | `me () -> player` | 1276 (0+1276) | 0x43c0d3 | The KI's own player number (KI+0x828). |
| 188 | `my_nation () -> nation` | 286 (169+117) | 0x43aa47 | Own nation: dword at 0x5aefdc + player*300 (+0x10c of the SPIELER record copy at 0x5aeed0) : 0 Natives, 1 Mexicans, 2 Outlaws, 3 USA, -1 none (checked against the campaign maps' SPIELER records and the per-nation modules). *(0x438d50)* |
| 189 | `nation (player) -> nation` | 87 (56+31) | 0x43aa6a | Nation of any player. *(0x438d50)* |
| 271 | `my_wood () -> n` | 66 (35+31) | 0x43b63d | Own stock of wood (0x58fe34[player]). |
| 272 | `my_gold () -> n` | 36 (16+20) | 0x43b660 | Own stock of gold (0x58fe14[player]). |
| 273 | `my_horses () -> n` | 287 (261+26) | 0x43b683 | Own stock of horses (0x58fdd4[player]). |
| 274 | `my_food () -> n` | 76 (50+26) | 0x43b6a6 | Own stock of food (0x58fdb4[player]). |
| 278 | `my_guns () -> n` | 28 (22+6) | 0x43b732 | Own stock of guns (0x58fe74[player]). |
| 281 | `wood (player) -> n` | 0 (0+0) | 0x43b7d5 | Stock of wood of any player (0x58fe34[p]; no range check). |
| 282 | `gold (player) -> n` | 0 (0+0) | 0x43b7ff | Stock of gold of any player (0x58fe14[p]; no range check). |
| 283 | `horses (player) -> n` | 311 (311+0) | 0x43b829 | Stock of horses of any player (0x58fdd4[p]; no range check). |
| 284 | `food (player) -> n` | 0 (0+0) | 0x43b853 | Stock of food of any player (0x58fdb4[p]; no range check). |
| 288 | `guns (player) -> n` | 0 (0+0) | 0x43b8fb | Stock of guns of any player (0x58fe74[p]; no range check). |
| 301 | `my_warehouse_gold () -> n` | 0 (0+0) | 0x43bfde | Gold lying in my gold warehouses (0x58fe54[p] = player manager +0x124, the sum of their +0x6fc). Spendable gold is 272. *(0x438de0)* |
| 302 | `warehouse_gold (player) -> n` | 0 (0+0) | 0x43c001 | Same for any player. *(0x438de0)* |
| 275 | `my_free_living_space () -> n` | 130 (104+26) | 0x43b6c9 | min(unit limit 0x58fd74[0], housing 0x58fd94[p]) - population 0x58fd74[p] (0x422ad0): how many more units fit. *(0x438cb0)* |
| 285 | `free_living_space (player) -> n` | 0 (0+0) | 0x43b87d | Same for any player. *(0x438cb0)* |
| 279 | `my_population () -> n` | 32 (32+0) | 0x43b755 | Own population (living space used, 0x58fd74[p]); 0 if p not 1..8. *(0x439720)* |
| 289 | `unit_limit () -> n` | 138 (53+85) | 0x43b778 | The match unit limit 0x58fd74[0] = (menu choice + 3) * 25, 75..200. *(0x439740)* |
| 270 | `my_count (guid) -> n` | 983 (585+398) | 0x43b60c | Number of own objects of type guid (world 0x42a0b0(player, guid)). *(0x438c50)* |
| 280 | `count (player, guid) -> n` | 107 (96+11) | 0x43b79b | Number of objects of type guid owned by player. *(0x438c50)* |
| 340 | `count_checked (player, guid) -> n` | 1 (1+0) | 0x43c523 | Same as 280 but 0 unless 0 <= player <= 10 (player 0 = neutral: `native_340(0, 482)` counts free cows). *(0x4393a0)* |
| 276 | `my_farms () -> n` | 73 (70+3) | 0x43b6ec | Own count of GUIDs 408 + 208 + 108 (USA farm, Mexican finca, Native field). *(0x438cd0)* |
| 286 | `farms (player) -> n` | 0 (0+0) | 0x43b8a7 | Same for any player. *(0x438cd0)* |
| 277 | `my_fields () -> n` | 17 (17+0) | 0x43b70f | Own count of GUID 149 (field). *(0x438d10)* |
| 287 | `fields (player) -> n` | 0 (0+0) | 0x43b8d1 | Same for any player. *(0x438d10)* |
| 199 | `my_corrals () -> n` | 1 (1+0) | 0x43a9fb | Own count of GUIDs 405 + 305 + 205 + 105 (ranch, corral, hacienda, corral: horse breeding). *(0x4390c0)* |
| 334 | `upgrade_known (id) -> bool` | 1873 (1740+133) | 0x43c3d5 | Own upgrade id (900-999) researched or in research: byte 0x590e38[p*100 + id-900] or 0x590b18[...] set; false outside 900..999. *(0x439920)* |
| 369 | `upgrade_done (id) -> bool` | 37 (6+31) | 0x43cb15 | Own upgrade id (900-999): byte 0x590b18[p*100 + id-900] set. *(0x439980)* |
| 352 | `difficulty () -> s` | 421 (186+235) | 0x43c6db | From the difficulty option v = [0x803a0c] (0 very easy, 1 easy, 2 medium, 3 difficult): returns 0 for v = 0, else 4 - v (easy 3, medium 2, difficult 1). Scripts subtract it from unit counts and treat 0 specially (`if (s == 0) s = 3`). |
| 363 | `victory_condition () -> n` | 17 (2+15) | 0x43c93a | [0x802b0c]: 0 everybody for themselves, 1 kill the leader, 2 destroy the main buildings. |
| 364 | `map_players () -> n` | 49 (32+17) | 0x43c952 | Number of players / start positions of the current map (map list 0x7d3c60, entry +0x2d8; 0x442210). Scripts: `maxspieler`, `< 5`. *(0x439840)* |
| 224 | `map_width () -> px` | 86 (4+82) | 0x43ba81 | Map size x ([0x7d2a68]); scripts clamp coordinates to 1..map_width. *(0x439010)* |
| 225 | `map_height () -> px` | 94 (5+89) | 0x43ba9d | Map size y ([0x7d2a6c]). *(0x439020)* |
| 206 | `my_relation (player) -> bits` | 5 (1+4) | 0x43aeeb | Relation of me to player (0x42bdd0(me-1, p-1)): bit 0x1 hostile, 0x4 allied, 0x20 set by a declaration, \| 0x40 if the other player is a computer, \| 0x80 if human; 0x10 if either player is absent; 8 if p == me. *(0x438fe0)* |
| 207 | `relation (p1, p2) -> bits` | 0 (0+0) | 0x43af1e | Same for two players; 8 if equal. *(0x438fe0)* |
| 335 | `random (lo, hi) -> n` | 5377 (2517+2860) | 0x43c40b | Pseudo-random number in lo..hi-1: idx = ([0x7d3c5c] + 1) mod 1000 (one counter for all players); r = table[idx] (1000 CRT rand() values 0..32767 at 0x7d2c9c, filled by 0x4382c0 when the KI is reset); n = lo + (hi-lo)*r/32767, then n = max(n, lo), then n = min(n, hi-1). So hi itself only comes out as hi-1, and random(a, a) returns a-1. *(0x439270)* |
| 362 | `zero () -> 0` | 0 (0+0) | 0x43c91e | Calls 0x41d4a0, which returns 0. Unused. *(0x41d4a0)* |
| 136 | `can_train (guid) -> bool` | 92 (7+85) | 0x43b295 | Prerequisite buildings exist for guid (0x42a020: every type in its requirement list is owned) and I can afford its unit costs (props 101-105 food, wood, horses, gold, guns and 119 living space, from my table; 0x422680). *(0x438900)* |
| 137 | `can_build (guid) -> bool` | 3461 (2863+598) | 0x43b2cc | Prerequisites met and I can afford its building costs (props 1-5, no living space). Types without props 1-5 (units) only test the prerequisites, which is how the scripts use it for units too. *(0x4389a0)* |
| 290 | `can_build_default (guid) -> bool` | 1 (1+0) | 0x43be6b | Same with the default table. *(0x4389a0)* |
| 291 | `can_train_default (guid) -> bool` | 0 (0+0) | 0x43bea3 | Same, costs from the neutral/default table (player 0). *(0x438900)* |

## Orders to units

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 143 | `move (unit, x, y)` | 542 (162+380) | 0x43b42c | Move to (x, y) (order 0x20000001 -> 0x41bb20, the normal right-click move; ignored while the unit is inside a building or transport). Not sent unless x > 0 and y > 0. *(0x438b00)* |
| 311 | `move_ (unit, x, y)` | 8 (6+2) | 0x43b42c | Same handler as 143. *(0x438b00)* |
| 328 | `attack_move (unit, x, y)` | 891 (444+447) | 0x43c30f | Move to (x, y) attacking enemies met on the way and stay there (order 0x2000001a -> 0x41bb50, a one-way patrol leg; only the AI sends it). Not sent unless x > 0 and y > 0. The most used order. *(0x439240)* |
| 327 | `patrol (unit, x, y)` | 2 (2+0) | 0x43c2cd | Patrol between the current position and (x, y) (order 0x20000019 -> 0x41b9b0). *(0x439210)* |
| 145 | `attack (unit, target)` | 101 (6+95) | 0x43b4a0 | Attack (or hunt) an object (order 0x20000007 -> virtual +0xc8; fighters 0x436290, no effect for workers and wagons). *(0x438b50)* |
| 251 | `hunt (unit, animal)` | 36 (12+24) | 0x43b4a0 | Same handler as 145; the scripts use it on buffalo and cows. *(0x438b50)* |
| 250 | `attack_building (unit, building)` | 88 (49+39) | 0x43b576 | Attack a building (order 0x2000000b -> virtual +0xc4, fighters 0x4368c0); the scripts use it on palisades blocking the way. *(0x438bf0)* |
| 149 | `worker_attack (unit, target)` | 4 (2+2) | 0x43b544 | Melee attack by a non-fighter with a melee value (order 0x2000000a -> 0x419910). *(0x438bd0)* |
| 146 | `set_stance (unit, stance)` | 659 (83+576) | 0x43b4d2 | Set the behaviour/stance (order 0x20000008 -> 0x4196b0, unit+0x468; for 2 and 3 the current position becomes the guard point). Values 0..3 (constants 182-185); the UI sends 0/1/2. Order of meanings probably aggressive, defensive, hold ground, passive (texts 60-63) - unverified. *(0x438b70)* |
| 336 | `stop (unit)` | 78 (62+16) | 0x43c445 | Stop (order 0x20000026 -> 0x4186a0: task = idle, also stops passengers). *(0x4392d0)* |
| 326 | `follow (unit, target)` | 81 (21+60) | 0x43c29b | Follow an object (order 0x20000018 -> 0x41b980; used for escorts). *(0x4391f0)* |
| 374 | `follow_ (unit, target)` | 10 (8+2) | 0x43c29b | Same handler as 326. *(0x4391f0)* |
| 211 | `enter (unit, building)` | 86 (14+72) | 0x43af8c | Enter / garrison a building (order 0x20000012 -> 0x41a640; unit and building need class 0x4000: towers, forts, quarters). *(0x438ec0)* |
| 212 | `into_corral (horse, corral)` | 0 (0+0) | 0x43afbe | Put a horse into a corral (order 0x20000011 -> 0x461540; target class 0x40000000). *(0x438ee0)* |
| 213 | `board (unit, transport)` | 8 (5+3) | 0x43aff0 | Board a boat / raft / coach (order 0x20000013 -> 0x41a900; transport class 0x8000000). *(0x438f00)* |
| 214 | `unload (transport, index)` | 0 (0+0) | 0x43b022 | Unload passenger number `index` (order 0x20000014 -> 0x41ac30; needs a free landing cell within 128 px). *(0x438f20)* |
| 358 | `unload_all (transport)` | 11 (3+8) | 0x43c8a2 | If the object has class 0x8000000: send order 0x20000014(t, 0) once per passenger (count obj+0x3d0). *(0x4397a0)* |
| 130 | `chop_wood (worker, tree)` | 7 (6+1) | 0x43b144 | Order 0x20000005(worker, tree.x, tree.y) -> 0x402860: cut wood at the tree nearest to the given tree's position (nearest class-0x10 object within 1000 px). *(0x4385b0)* |
| 131 | `mine_gold (worker, mine)` | 3 (2+1) | 0x43b0e8 | Dig gold at a mine (order 0x20000004 -> 0x402420; refused when the mine is empty, 0x423c70 == 0). *(0x438590)* |
| 133 | `transport_to (wagon, building)` | 21 (8+13) | 0x43b176 | Wagon transport (order 0x2000000c -> virtual +0xb8, 0x464180): to the main building = deliver, to a gold warehouse etc. = load there. *(0x438650)* |
| 360 | `transport_to_ (wagon, building)` | 25 (1+24) | 0x43b176 | Same handler as 133. *(0x438650)* |
| 252 | `work_field (worker, field)` | 5 (2+3) | 0x43b5a8 | Work a field (order 0x2000000d -> 0x402bf0; women, class 0x800000). *(0x438c10)* |
| 253 | `mount (unit, horse)` | 3 (2+1) | 0x43b5da | Mount a horse (order 0x20000010 -> 0x419fc0; unit class 0x2000, not mounted). *(0x438c30)* |
| 361 | `animal_into (animal, building)` | 4 (3+1) | 0x43c8ec | Lead an animal into a building, e.g. a cow to the slaughterhouse/corral (order 0x20000024 -> 0x43fbf0). *(0x439820)* |
| 144 | `build_repair (worker, building)` | 63 (10+53) | 0x43b46e | Help construct or repair a building (order 0x20000003 -> 0x41b420). *(0x438b30)* |
| 135 | `build_near (worker, guid, x, y) -> bool` | 62 (17+45) | 0x43b217 | Place a building: spiral search from (x, y) outward in 16 px steps up to +-500 px for a spot on the worker's terrain level (0x407cf0) where the footprint fits (placement helper 0x429a20/0x45c900, terrain mask 0x100, 0x1000 for shipyards 218/315/418), then order 0x20000002(worker, x, y, guid) (place site, deduct cost, build) or 0x2000000f for a field (149). Returns 1 if a spot was found; the spot is kept in module+0x10c/0x110 (read with 293/294). No affordability check (use 137). *(0x438670)* |
| 292 | `build_near_at (worker, x, y, guid) -> bool` | 21 (3+18) | 0x43bedb | Same as 135 with the arguments in this order. *(0x438d30 -> 0x438670)* |
| 293 | `last_build_x () -> x` | 55 (10+45) | 0x43bf52 | module+0x110 (x of the last 135/292 placement). |
| 294 | `last_build_y () -> y` | 55 (10+45) | 0x43bf6e | module+0x10c. |
| 147 | `self_destruct (unit)` | 12 (1+11) | 0x43b504 | Order 0x20000009 sub-code 6 -> 0x419120(0): the unit dies. *(0x438b90)* |
| 148 | `unsaddle (unit)` | 1 (0+1) | 0x43b524 | Order 0x20000009 sub-code 2 -> 0x41a080: dismount; a horse (480) and the foot type (guid-1) appear. *(0x438bb0)* |
| 215 | `camouflage (unit)` | 6 (2+4) | 0x43b054 | Order 0x20000009 sub-code 3 -> 0x41a550 (unit+0x401 = 1). *(0x438f40)* |
| 216 | `uncamouflage (unit)` | 4 (2+2) | 0x43b074 | Order 0x20000009 sub-code 4 -> 0x41a5b0. *(0x438f60)* |
| 345 | `unpack_tepee (travois)` | 0 (0+0) | 0x43c601 | Order 0x20000009 sub-code 5 -> 0x4647f0. *(0x439450)* |
| 320 | `spell_eagle_eye (medicine_man, x, y)` | 1 (0+1) | 0x43c14f | Order 0x20000016 spell 0 at (x, y) (0x433c00). Spells need energy obj+0x394 >= the spell's cost. *(0x439110)* |
| 321 | `spell_lightning (medicine_man, x, y)` | 3 (2+1) | 0x43c191 | Order 0x20000016 spell 1 at (x, y). *(0x439140)* |
| 322 | `spell_hail (medicine_man, target)` | 0 (0+0) | 0x43c1d3 | Order 0x20000016 spell 2 on an object. *(0x439170)* |
| 323 | `spell_protect (medicine_man, target)` | 0 (0+0) | 0x43c205 | Order 0x20000016 spell 4 (protective dance) on an object. *(0x439190)* |
| 324 | `spell_rain (medicine_man, target)` | 1 (0+1) | 0x43c237 | Order 0x20000016 spell 3 (rain) on an object. *(0x4391b0)* |
| 325 | `rob (unit, building)` | 4 (4+0) | 0x43c269 | Rob / steal from a building (order 0x20000017 -> virtual +0x94, 0x41b620). *(0x4391d0)* |
| 341 | `dig_in (unit)` | 6 (3+3) | 0x43c55d | Bury / dig in (order 0x2000001f -> 0x4377c0; the assassin). *(0x4393d0)* |
| 342 | `dig_out (unit)` | 0 (0+0) | 0x43c57d | Come out (order 0x20000020 -> 0x4377f0). *(0x4393f0)* |
| 343 | `disarm_trap (unit, trap)` | 5 (2+3) | 0x43c59d | Disarm an enemy trap (order 0x20000021 -> 0x41bd10). *(0x439410)* |
| 344 | `pack_tepee (travois, tepee)` | 0 (0+0) | 0x43c5cf | Pack an own tepee (class 0x40) onto a travois (order 0x2000001d -> 0x4646d0). *(0x439430)* |
| 346 | `convert (priest, unit)` | 4 (2+2) | 0x43c621 | Convert (order 0x2000001c -> 0x4593b0; needs energy and range 500). *(0x439470)* |
| 347 | `heal (healer, unit)` | 4 (2+2) | 0x43c653 | Heal (order 0x2000001b -> 0x43f3f0; only if the target is hurt). *(0x439490)* |
| 354 | `group_attack_move (table, n, formation, x, y)` | 72 (0+72) | 0x43c731 | Formation attack-move of the first n (max 20) handles in KI table `table` (0..99): order 0x20000028 {leader = table[t][0], x, y, formation, n-1, the others}. The scripts use formation 6. *(0x439570)* |
| 390 | `group_attack (table, n, formation, target)` | 0 (0+0) | 0x43cfd3 | Formation attack on an object by the first n (max 20) units of table t: order 0x20000027 {leader, target.x, target.y, formation, target, n-1, others}. Nothing is sent if the target is gone. *(0x439cf0)* |
| 391 | `group_attack_ (table, n, formation, target)` | 4 (0+4) | 0x43cfd3 | Same handler as 390. *(0x439cf0)* |

## Orders to buildings

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 138 | `produce (building, guid)` | 47 (8+39) | 0x43b303 | Queue a unit/upgrade (order 0x10000001 -> 0x40cd10): costs (props 101-105) from the owner's table are deducted only if the queue accepts it (max 10, one leader, upgrade not already done). No affordability check - test 136 first. *(0x438a40)* |
| 142 | `produce_neutral (building, guid)` | 11 (6+5) | 0x43b3fa | Same with costs from the neutral table (order 0x10000002): horses 480, cows 482, guns 710, liquor 711. *(0x438ae0)* |
| 210 | `release_unit (building, index)` | 0 (0+0) | 0x43af5a | Let garrisoned unit `index` out (order 0x10000003 -> 0x40d7b0). *(0x438ea0)* |
| 338 | `cancel_production (building)` | 0 (0+0) | 0x43c48f | Cancel the first queue entry with refund (order 0x10000004 index 0). *(0x439320)* |
| 348 | `demolish (building)` | 10 (1+9) | 0x43c685 | Order 0x10000005: the building takes 5000 damage (virtual +0x44 = 0x40c970; HP are x256, so 19.5 HP per order). *(0x4394b0)* |
| 351 | `release_all (building)` | 2 (0+2) | 0x43c6bb | If class 0x4000: order 0x10000003(b, 0) once per occupant (obj+0xd8). *(0x4394d0)* |
| 355 | `set_rally_point (building, x, y)` | 5 (0+5) | 0x43c80c | Order 0x10000008: rally point (building+0xf8 = x, +0xf4 = y; both must be > 0). *(0x4395f0)* |
| 399 | `player_bonus (building)` | 1 (0+1) | 0x43d229 | Order 0x10000009 -> 0x40e3c0: uses 0x4b00 of the building's charge (+0xa0) for a 60 s player-wide effect (world+4+4*(p-1); probably a combat bonus). *(0x439df0)* |
| 401 | `building_ability (building, x, y)` | 1 (0+1) | 0x43d273 | Order 0x10000006 -> 0x40de90: uses 0x1900 charge, creates a 7 s effect object at (x, y) (probably reveals the area). *(0x439e40)* |

## Player-level orders

| id | signature | uses (base+exp) | handler | behaviour |
| --- | --- | --- | --- | --- |
| 376 | `add_food (amount)` | 39 (12+27) | 0x43cd21 | Player order 0x40000009(me, amount): adds food (0x422990). The AI's resource cheat (multi_situation_analyser tops itself up when low). *(0x455ea0)* |
| 377 | `add_wood (amount)` | 37 (12+25) | 0x43cd4d | Player order 0x40000008: adds wood (0x422650). *(0x455ea0)* |
| 378 | `add_gold (amount)` | 31 (12+19) | 0x43cd79 | Player order 0x4000000a: adds gold (0x422600). *(0x455ea0)* |
| 381 | `make_allies (p1, p2)` | 2 (0+2) | 0x43cdcc | Player order 0x40000004: p1 allies with p2 (relation bit 4, shared vision, message 372). *(0x439b00)* |
| 382 | `make_enemies (p1, p2)` | 0 (0+0) | 0x43cdfe | Player order 0x40000003: p1 declares p2 enemy (bit 1, message 373). *(0x439b20)* |
| 388 | `resign ()` | 2 (0+2) | 0x43cfba | Player order 0x4000000c(me): "player left" message and removal of this player. *(0x439c80)* |

## Engine notes for the native API

### Handles and object lists

A handle is `list<<28 | (guid & 0xfff)<<16 | slot` (0x4325f0). 0x42b820 resolves it: lists 0..8 are
neutral (0) and players 1..8 at 0x7d2778 + list*60 (capacities 1000 / 500 each), list 9 is the
tree/map-object grid (20000), list 10 walls (10000). Resolution fails (natives return 0 or -1)
when the slot is empty or holds a different type. Slots are reused only after the next-fit cursor
wraps, so handles are unique in practice but not guaranteed. **A handle changes when the object
changes owner** (conversion, capture: 0x42cd70 moves it to the new owner's list), so a converted
unit's old handle stops resolving. A dying object (+0x28) resolves only while it is still shown.

### Claims (obj+0x1c)

Each object carries a per-player bitmask "claimed by this AI". Virtual +0x28 (0x4325b0) sets bit
`1<<player`, +0x24 (0x4325d0) clears it. The claiming searches (107-109, 139-141, 200-205,
383-386) skip objects the calling player has claimed and claim what they return; 380 claims and
123-125 release explicitly. This is how modules running in parallel avoid taking the same unit:
`e = claim_nearest_type(me(), x, y, 459, 0xc00)` hands out each idle cavalryman only once until
someone releases it. The non-claiming searches (368-371, 389, 392, 393, 387) ignore claims.

### Searches

All are linear scans of one player's object list with squared-distance comparison (ties keep the
earlier list entry). Filters: class mask (obj+0x24, "contains all" or "any"), exact type
(obj+0xc), owner (205), state "any of" (or no filter when the mask is 0) / state "none of", and the
claim bit. 107-109/200-202 with a class mask containing 0x10 or 0x40 search the tree grid instead
(0x405bf0, radius 10000, class 0x10) and claim nothing. 387 (enemies within 500 px) scans the
object grid ring by ring and returns the first hit, not the nearest.

### Orders

Every order native builds a message for the order queue 0x80b278 (0x455ea0 / 0x455ee0 /
0x455f20 / 0x455f60, or by hand for group orders). The queue executes it after the network
latency (0x455cb0, `time = now + [0x80e2bc]` ticks, the same path the user interface and the
multiplayer lockstep use), through 0x456450: `code>>28` 1 = building orders (0x4564a0),
2 = unit orders (0x456760), 4 = player orders (0x4571f0). Checks done there: the object must
exist and be of the right kind (units: class & 0xe000002 and not dying; buildings: class &
0x600004); **there is no ownership check**, so a script can order any player's objects (and the
searches take a player argument, so campaign scripts can pick up another player's units). Costs are deducted
when the order executes, without an affordability check (0x10000001, 0x20000002): scripts test
`can_train`/`can_build` first.

Unit order codes used by natives: 0x20000001 move, 0x20000002 place building and build,
0x20000003 build/repair, 0x20000004 mine gold, 0x20000005 cut wood near (x,y), 0x20000007
attack/hunt, 0x20000008 stance, 0x20000009 sub-command (2 unsaddle, 3/4 camouflage on/off,
5 unpack tepee, 6 die), 0x2000000a worker attack, 0x2000000b attack building, 0x2000000c wagon
transport, 0x2000000d work field, 0x2000000f plant field, 0x20000010 mount, 0x20000011 horse
into corral, 0x20000012 garrison, 0x20000013 board, 0x20000014 unload one, 0x20000016 spell
(0 eagle eye, 1 lightning, 2 hail, 3 rain, 4 protective dance), 0x20000017 rob, 0x20000018
follow, 0x20000019 patrol, 0x2000001a attack-move (AI only), 0x2000001b heal, 0x2000001c
convert, 0x2000001d pack tepee, 0x2000001f/0x20000020 dig in/out, 0x20000021 disarm trap,
0x20000024 animal into building, 0x20000026 stop, 0x20000027 formation attack, 0x20000028
formation attack-move. Building orders: 0x10000001 produce, 0x10000002 produce at neutral
cost, 0x10000003 release garrison member, 0x10000004 cancel queue entry, 0x10000005 demolish
(5000 damage), 0x10000006 area ability, 0x10000008 rally point, 0x10000009 60 s player bonus.
Player orders: 0x40000003 declare enemy, 0x40000004 ally, 0x40000008/9/a add wood/food/gold,
0x4000000c leave the game.

### Flags


### Class bits (obj+0x24, static; natives 365/366, searches)

| bit | meaning |
| --- | --- |
| 0x1 | static scenery |
| 0x2 | unit |
| 0x4 | building |
| 0x8 | gold mine (types 700-703) |
| 0x10 | tree (types 500-535, map grid list 9) |
| 0x20 | livestock (buffalo, cow) |
| 0x40 | tent / packable tepee |
| 0x80 | food drop-off |
| 0x100 | gold warehouse |
| 0x200 | wood drop-off |
| 0x400 | armed unit (also the trap building) |
| 0x800 | gatherer (receives gold-mining orders) |
| 0x1000 | military |
| 0x2000 | can ride |
| 0x4000 | can garrison / building that takes a garrison |
| 0x8000 | builder |
| 0x10000 | gatherer |
| 0x20000 | main building (HQ) |
| 0x40000 | wagon |
| 0x80000 | storage building (set at run time) |
| 0x100000 | farm / granary |
| 0x200000 | exhausted field |
| 0x400000 | field |
| 0x800000 | women |
| 0x1000000 | civilian worker (receives wood-cutting orders) |
| 0x2000000 | horse |
| 0x4000000 | animal |
| 0x8000000 | unit transport (boat, raft, stagecoach) |
| 0x10000000 | can camouflage (run time) |
| 0x20000000 | detects hidden units (archers, trappers, hunters) |
| 0x40000000 | horse corral |
| 0x80000000 | leader / hero |

### State bits (virtual +0x2c, dynamic; natives 113-118, search state filters)

| bit | units | buildings |
| --- | --- | --- |
| 0x1 | worker task bit |  |
| 0x2 | worker task bit |  |
| 0x4 | idle | finished |
| 0x8 | working / building |  |
| 0x10 |  | producing |
| 0x20 | wagon bit |  |
| 0x40 |  | field lying fallow (+0x6f9 == 0) |
| 0x80 | worker task bit |  |
| 0x100 | moving |  |
| 0x200 |  | under construction |
| 0x400 | inside a transport (boarded: unit+0x3f0 and +0x3a0 set, 0x41aacb) |  |
| 0x800 | inside a building (quartered: +0x3f0 set, +0x3a0 clear, 0x41a814) |  |
| 0x1000 |  | below 40% HP |
| 0x2000 | fighter in combat |  |
| 0x4000 | task 0x40000/0x80000 |  |
| 0x8000 | medicine man casting |  |
| 0x10000 | camouflaged |  |
| 0x20000 | damaged | damaged |
| 0x100000 | task 0x400 |  |
| 0x800000 | +0x418 bit 2 |  |
| 0x1000000 | following |  |
| 0x2000000 | carrying wood |  |
| 0x4000000 | carrying gold |  |
| 0x8000000 | carrying food |  |
| 0x10000000 | mounted |  |
| 0x20000000 | dug in |  |
| 0x40000000 | animal |  |
| 0x80000000 | hero |  |

Units: 0x41a2f0, then the unit class's extra bits (virtual +0x8c: farm and wagon task bits,
herders, healers; none sets 0x400 or 0x800). 0x400 and 0x800 come only from unit+0x3f0
("inside"), which only quartering in a building (0x41a80d, +0x3a0 = 0: 0x800) and boarding a
transport (0x41aac4, +0x3a0 = 1: 0x400) set. So `find_my_unit(military, x, y, 0x800)` in
a_initeinheiten registers only quartered soldiers, and units standing free never get into the
unit tables (base mex_04: mex04_grün_austragen waits for the green patrol's commander for
good). Searches take the state argument as "any of these bits, or 0 for any" (0x424b2b).
