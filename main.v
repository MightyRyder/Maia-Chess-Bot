module main

import rand
import raylib as rl

const b_bishop_bytes  = $embed_file('chess7/bB.png').to_bytes()
const b_knight_bytes  = $embed_file('chess7/bN.png').to_bytes()
const b_rook_bytes    = $embed_file('chess7/bR.png').to_bytes()
const b_queen_bytes   = $embed_file('chess7/bQ.png').to_bytes()
const b_king_bytes    = $embed_file('chess7/bK.png').to_bytes()
const b_pawn_bytes    = $embed_file('chess7/bP.png').to_bytes()

const w_bishop_bytes  = $embed_file('chess7/wB.png').to_bytes()
const w_knight_bytes  = $embed_file('chess7/wN.png').to_bytes()
const w_rook_bytes    = $embed_file('chess7/wR.png').to_bytes()
const w_queen_bytes   = $embed_file('chess7/wQ.png').to_bytes()
const w_king_bytes    = $embed_file('chess7/wK.png').to_bytes()
const w_pawn_bytes    = $embed_file('chess7/wP.png').to_bytes()

const square_size = 80
const board_pixels = square_size * 8
const window_w = board_pixels
const window_h = board_pixels
const fps = 60

const piece_none = 0
const piece_pawn = 1
const piece_knight = 2
const piece_bishop = 3
const piece_rook = 4
const piece_queen = 5
const piece_king = 6

const color_white = 0
const color_black = 1

const light_sq_color = rl.Color{ r: 240, g: 217, b: 181, a: 255 }
const dark_sq_color = rl.Color{ r: 139, g:  69, b:  19, a: 255 }
const select_col = rl.Color{ r: 255, g: 215, b:   0, a: 120 }
const target_col = rl.Color{ r: 123, g: 104, b: 238, a: 150 }
const hover_col = rl.Color{ r: 255, g: 255, b:   0, a:  55 }
const last_move_col = rl.Color{ r:  80, g: 200, b: 120, a: 110 }
const panel_col = rl.Color{ r: 30, g: 30, b: 30, a: 230 }
const panel_outline_col = rl.Color{ r: 90, g: 90, b: 90, a: 255 }
const text_col = rl.Color{ r: 235, g: 235, b: 235, a: 255 }
const status_bad_col = rl.Color{ r: 255, g: 120, b: 120, a: 255 }

struct Move {
	from int
	to int
	promo int
	en_passant bool
	castle bool
}

struct GameState {
mut:
	board [64]int

	white_to_move bool
	game_over bool
	in_check bool
	status string

	selected_sq int
	selected_moves []Move
	drag_active bool

	mouse_sq int
	last_from int
	last_to int

	en_passant_sq int

	w_king_moved bool
	w_rook_a_moved bool
	w_rook_h_moved bool
	b_king_moved bool
	b_rook_a_moved bool
	b_rook_h_moved bool

	promoting bool
	promotion_moves []Move
}

fn get_embedded_map() map[string][]u8 {
	return {
		'bB': b_bishop_bytes
		'bN': b_knight_bytes
		'bR': b_rook_bytes
		'bQ': b_queen_bytes
		'bK': b_king_bytes
		'bP': b_pawn_bytes
		'wB': w_bishop_bytes
		'wN': w_knight_bytes
		'wR': w_rook_bytes
		'wQ': w_queen_bytes
		'wK': w_king_bytes
		'wP': w_pawn_bytes
	}
}

fn load_piece_textures_embedded(emb map[string][]u8) map[string]rl.Texture2D {
	mut tex := map[string]rl.Texture2D{}
	colors := ['w', 'b']
	pieces := ['P', 'N', 'B', 'R', 'Q', 'K']
	for c in colors {
		for p in pieces {
			key := '${c}${p}'
			if data := emb[key] {
				if data.len == 0 {
					println('Warning: empty embedded file for $key')
					continue
				}
				img := rl.load_image_from_memory('.png', &data[0], data.len)
				if img.width == 0 || img.height == 0 {
					println('Warning: failed to decode $key from memory')
				} else {
					tex[key] = rl.load_texture_from_image(img)
					rl.unload_image(img)
				}
			} else {
				println('Warning: embedded file for $key not found')
			}
		}
	}
	return tex
}

fn abs_int(n int) int {
	return if n < 0 { -n } else { n }
}

fn on_board(sq int) bool {
	return sq >= 0 && sq < 64
}

fn file_of(sq int) int {
	return sq % 8
}

fn rank_of(sq int) int {
	return sq / 8
}

fn piece_is_white(code int) bool {
	return code > 0
}

fn piece_color(code int) int {
	return if code > 0 { color_white } else { color_black }
}

fn piece_abs(code int) int {
	return if code < 0 { -code } else { code }
}

fn side_name(white bool) string {
	return if white { 'White' } else { 'Black' }
}

fn piece_short_name(code int) string {
	return match piece_abs(code) {
		piece_pawn { 'P' }
		piece_knight { 'N' }
		piece_bishop { 'B' }
		piece_rook { 'R' }
		piece_queen { 'Q' }
		piece_king { 'K' }
		else { '?' }
	}
}

fn promo_name(promo int) string {
	return match promo {
		piece_queen { 'Queen' }
		piece_rook { 'Rook' }
		piece_bishop { 'Bishop' }
		piece_knight { 'Knight' }
		else { 'Piece' }
	}
}

fn piece_text_color(code int) rl.Color {
	return if code > 0 { rl.Color{ r: 250, g: 250, b: 250, a: 255 } } else { rl.Color{ r: 20, g: 20, b: 20, a: 255 } }
}

fn new_game() GameState {
	mut gs := GameState{
		white_to_move: true
		en_passant_sq: -1
		selected_sq: -1
		mouse_sq: -1
		last_from: -1
		last_to: -1
		status: 'White to move'
	}

	// White pieces
	gs.board[56] = piece_rook
	gs.board[57] = piece_knight
	gs.board[58] = piece_bishop
	gs.board[59] = piece_queen
	gs.board[60] = piece_king
	gs.board[61] = piece_bishop
	gs.board[62] = piece_knight
	gs.board[63] = piece_rook
	for sq in 48 .. 56 {
		gs.board[sq] = piece_pawn
	}

	// Black pieces
	gs.board[0] = -piece_rook
	gs.board[1] = -piece_knight
	gs.board[2] = -piece_bishop
	gs.board[3] = -piece_queen
	gs.board[4] = -piece_king
	gs.board[5] = -piece_bishop
	gs.board[6] = -piece_knight
	gs.board[7] = -piece_rook
	for sq in 8 .. 16 {
		gs.board[sq] = -piece_pawn
	}

	gs.refresh_status()
	return gs
}

fn (gs &GameState) king_sq(white bool) int {
	target := if white { piece_king } else { -piece_king }
	for sq in 0 .. 64 {
		if gs.board[sq] == target {
			return sq
		}
	}
	return -1
}

fn (gs &GameState) square_attacked(sq int, by_white bool) bool {
	// pawns
	if by_white {
		if file_of(sq) > 0 && on_board(sq + 9) && gs.board[sq + 9] == piece_pawn {
			return true
		}
		if file_of(sq) < 7 && on_board(sq + 7) && gs.board[sq + 7] == piece_pawn {
			return true
		}
	} else {
		if file_of(sq) > 0 && on_board(sq - 7) && gs.board[sq - 7] == -piece_pawn {
			return true
		}
		if file_of(sq) < 7 && on_board(sq - 9) && gs.board[sq - 9] == -piece_pawn {
			return true
		}
	}

	// knights
	knight_steps := [
		[-2, -1], [-2, 1], [-1, -2], [-1, 2],
		[1, -2], [1, 2], [2, -1], [2, 1],
	]
	for step in knight_steps {
		r := rank_of(sq) + step[0]
		f := file_of(sq) + step[1]
		if r < 0 || r > 7 || f < 0 || f > 7 { continue }
		idx := r * 8 + f
		code := gs.board[idx]
		if code != 0 && piece_is_white(code) == by_white && piece_abs(code) == piece_knight {
			return true
		}
	}

	// kings
	for dr in -1 .. 2 {
		for df in -1 .. 2 {
			if dr == 0 && df == 0 { continue }
			r := rank_of(sq) + dr
			f := file_of(sq) + df
			if r < 0 || r > 7 || f < 0 || f > 7 { continue }
			idx := r * 8 + f
			code := gs.board[idx]
			if code != 0 && piece_is_white(code) == by_white && piece_abs(code) == piece_king {
				return true
			}
		}
	}

	// rook/queen lines
	rays := [
		[-1, 0], [1, 0], [0, -1], [0, 1],
		[-1, -1], [-1, 1], [1, -1], [1, 1],
	]
	for ray in rays {
		dr := ray[0]
		df := ray[1]
		mut r := rank_of(sq) + dr
		mut f := file_of(sq) + df
		for r >= 0 && r < 8 && f >= 0 && f < 8 {
			idx := r * 8 + f
			code := gs.board[idx]
			if code != 0 {
				if piece_is_white(code) == by_white {
					abs := piece_abs(code)
					if (dr == 0 || df == 0) && (abs == piece_rook || abs == piece_queen) {
						return true
					}
					if (dr != 0 && df != 0) && (abs == piece_bishop || abs == piece_queen) {
						return true
					}
				}
				break
			}
			r += dr
			f += df
		}
	}

	return false
}

fn (gs &GameState) in_check_for(white bool) bool {
	ksq := gs.king_sq(white)
	if ksq < 0 { return false }
	return gs.square_attacked(ksq, !white)
}

fn append_promo_moves(mut moves []Move, from int, to int, en_passant bool, castle bool) {
	for promo in [piece_queen, piece_rook, piece_bishop, piece_knight] {
		moves << Move{
			from: from
			to: to
			promo: promo
			en_passant: en_passant
			castle: castle
		}
	}
}

fn (gs &GameState) pseudo_moves_from(sq int, white bool) []Move {
	if !on_board(sq) {
		return []Move{}
	}
	code := gs.board[sq]
	if code == 0 || piece_is_white(code) != white {
		return []Move{}
	}

	mut moves := []Move{}
	abs := piece_abs(code)
	r := rank_of(sq)
	f := file_of(sq)

	match abs {
		piece_pawn {
			dir := if white { -1 } else { 1 }
			start_rank := if white { 6 } else { 1 }
			promo_rank := if white { 0 } else { 7 }

			one_r := r + dir
			if one_r >= 0 && one_r < 8 {
				one_sq := one_r * 8 + f
				if gs.board[one_sq] == 0 {
					if one_r == promo_rank {
						append_promo_moves(mut moves, sq, one_sq, false, false)
					} else {
						moves << Move{ from: sq, to: one_sq }
					}

					if r == start_rank {
						two_r := r + dir * 2
						two_sq := two_r * 8 + f
						mid_sq := one_sq
						if two_r >= 0 && two_r < 8 && gs.board[mid_sq] == 0 && gs.board[two_sq] == 0 {
							moves << Move{ from: sq, to: two_sq }
						}
					}
				}
			}

			for df in [-1, 1] {
				nf := f + df
				nr := r + dir
				if nf < 0 || nf > 7 || nr < 0 || nr > 7 { continue }
				target := nr * 8 + nf
				target_code := gs.board[target]
				if target_code != 0 && piece_is_white(target_code) != white {
					if nr == promo_rank {
						append_promo_moves(mut moves, sq, target, false, false)
					} else {
						moves << Move{ from: sq, to: target }
					}
				}
				if target == gs.en_passant_sq {
					moves << Move{ from: sq, to: target, en_passant: true }
				}
			}
		}
		piece_knight {
			steps := [
				[-2, -1], [-2, 1], [-1, -2], [-1, 2],
				[1, -2], [1, 2], [2, -1], [2, 1],
			]
			for step in steps {
				nr := r + step[0]
				nf := f + step[1]
				if nr < 0 || nr > 7 || nf < 0 || nf > 7 { continue }
				target := nr * 8 + nf
				target_code := gs.board[target]
				if target_code == 0 || piece_is_white(target_code) != white {
					moves << Move{ from: sq, to: target }
				}
			}
		}
		piece_bishop, piece_rook, piece_queen {
			dirs := if abs == piece_bishop {
				[[-1, -1], [-1, 1], [1, -1], [1, 1]]
			} else if abs == piece_rook {
				[[-1, 0], [1, 0], [0, -1], [0, 1]]
			} else {
				[[-1, -1], [-1, 1], [1, -1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]]
			}
			for dir in dirs {
				mut nr := r + dir[0]
				mut nf := f + dir[1]
				for nr >= 0 && nr < 8 && nf >= 0 && nf < 8 {
					target := nr * 8 + nf
					target_code := gs.board[target]
					if target_code == 0 {
						moves << Move{ from: sq, to: target }
					} else {
						if piece_is_white(target_code) != white {
							moves << Move{ from: sq, to: target }
						}
						break
					}
					nr += dir[0]
					nf += dir[1]
				}
			}
		}
		piece_king {
			for dr in -1 .. 2 {
				for df in -1 .. 2 {
					if dr == 0 && df == 0 { continue }
					nr := r + dr
					nf := f + df
					if nr < 0 || nr > 7 || nf < 0 || nf > 7 { continue }
					target := nr * 8 + nf
					target_code := gs.board[target]
					if target_code == 0 || piece_is_white(target_code) != white {
						moves << Move{ from: sq, to: target }
					}
				}
			}

			// Castling
			if !gs.in_check_for(white) {
				if white {
					// king side: e1 -> g1, rook h1 -> f1
					if !gs.w_king_moved && !gs.w_rook_h_moved
						&& gs.board[61] == 0 && gs.board[62] == 0
						&& gs.board[63] == piece_rook
						&& !gs.square_attacked(61, false) && !gs.square_attacked(62, false) {
						moves << Move{ from: 60, to: 62, castle: true }
					}
					// queen side: e1 -> c1, rook a1 -> d1
					if !gs.w_king_moved && !gs.w_rook_a_moved
						&& gs.board[59] == 0 && gs.board[58] == 0 && gs.board[57] == 0
						&& gs.board[56] == piece_rook
						&& !gs.square_attacked(59, false) && !gs.square_attacked(58, false) {
						moves << Move{ from: 60, to: 58, castle: true }
					}
				} else {
					// king side: e8 -> g8, rook h8 -> f8
					if !gs.b_king_moved && !gs.b_rook_h_moved
						&& gs.board[5] == 0 && gs.board[6] == 0
						&& gs.board[7] == -piece_rook
						&& !gs.square_attacked(5, true) && !gs.square_attacked(6, true) {
						moves << Move{ from: 4, to: 6, castle: true }
					}
					// queen side: e8 -> c8, rook a8 -> d8
					if !gs.b_king_moved && !gs.b_rook_a_moved
						&& gs.board[3] == 0 && gs.board[2] == 0 && gs.board[1] == 0
						&& gs.board[0] == -piece_rook
						&& !gs.square_attacked(3, true) && !gs.square_attacked(2, true) {
						moves << Move{ from: 4, to: 2, castle: true }
					}
				}
			}
		}
		else {}
	}

	return moves
}

fn (gs GameState) is_legal_move(mv Move, white bool) bool {
	if !on_board(mv.from) || !on_board(mv.to) {
		return false
	}
	if gs.board[mv.from] == 0 {
		return false
	}
	if piece_is_white(gs.board[mv.from]) != white {
		return false
	}

	mut tmp := gs
	tmp.apply_move_core(mv)
	return !tmp.in_check_for(white)
}

fn (gs &GameState) legal_moves_from(sq int, white bool) []Move {
	pseudo := gs.pseudo_moves_from(sq, white)
	mut legal := []Move{}
	for mv in pseudo {
		if gs.is_legal_move(mv, white) {
			legal << mv
		}
	}
	return legal
}

fn (gs &GameState) all_legal_moves(white bool) []Move {
	mut moves := []Move{}
	for sq in 0 .. 64 {
		if gs.board[sq] != 0 && piece_is_white(gs.board[sq]) == white {
			for mv in gs.legal_moves_from(sq, white) {
				moves << mv
			}
		}
	}
	return moves
}

fn (mut gs GameState) apply_move_core(mv Move) {
	moving := gs.board[mv.from]
	white := piece_is_white(moving)
	abs := piece_abs(moving)

	// clear old en passant by default
	gs.en_passant_sq = -1

	// identify capture square
	mut captured_sq := mv.to
	mut captured_code := gs.board[mv.to]

	if mv.en_passant {
		if white {
			captured_sq = mv.to + 8
		} else {
			captured_sq = mv.to - 8
		}
		captured_code = gs.board[captured_sq]
	}

	// update castling rights when king / rook moves
	if abs == piece_king {
		if white {
			gs.w_king_moved = true
		} else {
			gs.b_king_moved = true
		}
	}
	if abs == piece_rook {
		if white {
			if mv.from == 56 { gs.w_rook_a_moved = true }
			if mv.from == 63 { gs.w_rook_h_moved = true }
		} else {
			if mv.from == 0 { gs.b_rook_a_moved = true }
			if mv.from == 7 { gs.b_rook_h_moved = true }
		}
	}

	// update castling rights if a rook is captured on its home square
	if captured_code != 0 && piece_abs(captured_code) == piece_rook {
		if captured_sq == 56 { gs.w_rook_a_moved = true }
		if captured_sq == 63 { gs.w_rook_h_moved = true }
		if captured_sq == 0 { gs.b_rook_a_moved = true }
		if captured_sq == 7 { gs.b_rook_h_moved = true }
	}

	// move the piece
	gs.board[mv.from] = 0
	gs.board[mv.to] = moving

	// remove captured piece
	if mv.en_passant {
		gs.board[captured_sq] = 0
	} else if captured_code != 0 {
		gs.board[mv.to] = moving
	}

	// castling rook move
	if mv.castle && abs == piece_king {
		if white {
			if mv.to == 62 {
				gs.board[63] = 0
				gs.board[61] = piece_rook
			} else if mv.to == 58 {
				gs.board[56] = 0
				gs.board[59] = piece_rook
			}
		} else {
			if mv.to == 6 {
				gs.board[7] = 0
				gs.board[5] = -piece_rook
			} else if mv.to == 2 {
				gs.board[0] = 0
				gs.board[3] = -piece_rook
			}
		}
	}

	// pawn double push creates en passant target
	if abs == piece_pawn && abs_int(mv.to - mv.from) == 16 {
		if white {
			gs.en_passant_sq = mv.from - 8
		} else {
			gs.en_passant_sq = mv.from + 8
		}
	}

	// promotion
	if abs == piece_pawn {
		end_rank := rank_of(mv.to)
		if (white && end_rank == 0) || (!white && end_rank == 7) {
			promo := if mv.promo == 0 { piece_queen } else { mv.promo }
			gs.board[mv.to] = if white { promo } else { -promo }
		}
	}

	gs.last_from = mv.from
	gs.last_to = mv.to
	gs.white_to_move = !gs.white_to_move
}

fn (mut gs GameState) refresh_status() {
	gs.in_check = gs.in_check_for(gs.white_to_move)
	legal := gs.all_legal_moves(gs.white_to_move)

	if legal.len == 0 {
		gs.game_over = true
		if gs.in_check {
			loser := side_name(gs.white_to_move)
			winner := side_name(!gs.white_to_move)
			gs.status = 'Checkmate - ${winner} wins. ${loser} is mated.'
		} else {
			gs.status = 'Stalemate - no legal moves.'
		}
	} else {
		gs.game_over = false
		side := side_name(gs.white_to_move)
		if gs.in_check {
			gs.status = '${side} to move - check.'
		} else {
			gs.status = '${side} to move.'
		}
	}
}

fn (mut gs GameState) finalize_move(mv Move) {
	gs.apply_move_core(mv)
	gs.selected_sq = -1
	gs.selected_moves = []Move{}
	gs.drag_active = false
	gs.promoting = false
	gs.promotion_moves = []Move{}
	gs.refresh_status()
}

fn (mut gs GameState) start_promotion_selection(moves []Move) {
	gs.promoting = true
	gs.promotion_moves = []Move{}
	for mv in moves {
		gs.promotion_moves << mv
	}
	gs.drag_active = false
	gs.selected_sq = -1
	gs.selected_moves = []Move{}
}

fn (mut gs GameState) choose_promotion(idx int) {
	if !gs.promoting { return }
	if idx < 0 || idx >= gs.promotion_moves.len { return }
	mv := gs.promotion_moves[idx]
	gs.finalize_move(mv)
}

fn square_to_pixel(sq int) (int, int) {
	col := sq % 8
	row := sq / 8
	return col * square_size, row * square_size
}

fn square_center(sq int) (int, int) {
	x, y := square_to_pixel(sq)
	return x + square_size / 2, y + square_size / 2
}

fn pixel_to_square(px int, py int) int {
	col := px / square_size
	row := py / square_size
	if col < 0 || col > 7 || row < 0 || row > 7 { return -1 }
	return row * 8 + col
}

fn draw_board() {
	for row in 0 .. 8 {
		for col in 0 .. 8 {
			color := if (row + col) % 2 == 0 { light_sq_color } else { dark_sq_color }
			rl.draw_rectangle(col * square_size, row * square_size, square_size, square_size, color)
		}
	}
}

fn draw_coords() {
	font_size := 14
	files := ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
	for i in 0 .. 8 {
		rl.draw_text(files[i], i * square_size + square_size - 16, board_pixels - 18, font_size, text_col)
		rl.draw_text((8 - i).str(), 4, i * square_size + 2, font_size, text_col)
	}
}

fn draw_square_overlay(sq int, col rl.Color) {
	x, y := square_to_pixel(sq)
	rl.draw_rectangle(x, y, square_size, square_size, col)
}

fn draw_piece(sq int, code int, textures map[string]rl.Texture2D) {
	if code == 0 { return }
	x, y := square_to_pixel(sq)
	key := (if code > 0 { 'w' } else { 'b' }) + piece_short_name(code)
	if tex := textures[key] {
		src_rect := rl.Rectangle{
			x: 0
			y: 0
			width: f32(tex.width)
			height: f32(tex.height)
		}
		dest_rect := rl.Rectangle{
			x: f32(x)
			y: f32(y)
			width: f32(square_size)
			height: f32(square_size)
		}
		rl.draw_texture_pro(tex, src_rect, dest_rect, rl.Vector2{}, 0.0, rl.Color{255, 255, 255, 255})
	} else {
		// fallback if texture missing
		cx := x + square_size / 2
		cy := y + square_size / 2
		fill := if code > 0 { rl.Color{ r: 248, g: 248, b: 248, a: 255 } } else { rl.Color{ r: 25, g: 25, b: 25, a: 255 } }
		edge := if code > 0 { rl.Color{ r: 35, g: 35, b: 35, a: 255 } } else { rl.Color{ r: 230, g: 230, b: 230, a: 255 } }
		rl.draw_circle(cx, cy, 28, fill)
		rl.draw_circle_lines(cx, cy, 28, edge)

		label := piece_short_name(code)
		font_size := 32
		tw := rl.measure_text(label, font_size)
		tx := cx - tw / 2
		ty := cy - font_size / 2 - 2
		rl.draw_text(label, tx, ty, font_size, piece_text_color(code))
	}
}

fn draw_pieces(gs &GameState, textures map[string]rl.Texture2D) {
	for sq in 0 .. 64 {
		code := gs.board[sq]
		if code != 0 {
			draw_piece(sq, code, textures)
		}
	}
}

fn draw_selection_hints(gs &GameState) {
	if gs.selected_sq < 0 { return }
	draw_square_overlay(gs.selected_sq, select_col)
	for mv in gs.selected_moves {
		x, y := square_to_pixel(mv.to)
		rl.draw_circle(x + square_size / 2, y + square_size / 2, 10, target_col)
	}
}

fn draw_last_move(gs &GameState) {
	if gs.last_from >= 0 {
		draw_square_overlay(gs.last_from, last_move_col)
	}
	if gs.last_to >= 0 {
		draw_square_overlay(gs.last_to, last_move_col)
	}
}

fn draw_promotion_menu(gs &GameState, textures map[string]rl.Texture2D) {
	panel_w := square_size * 4
	panel_h := square_size + 48
	panel_x := (window_w - panel_w) / 2
	panel_y := (window_h - panel_h) / 2

	rl.draw_rectangle(panel_x - 3, panel_y - 3, panel_w + 6, panel_h + 6, panel_outline_col)
	rl.draw_rectangle(panel_x, panel_y, panel_w, panel_h, panel_col)
	rl.draw_text('Choose promotion', panel_x + 10, panel_y + 8, 20, text_col)

	for i, mv in gs.promotion_moves {
		btn_x := panel_x + i * square_size
		btn_y := panel_y + 26
		btn_color := if i % 2 == 0 { light_sq_color } else { dark_sq_color }
		rl.draw_rectangle(btn_x, btn_y, square_size, square_size, btn_color)
		rl.draw_rectangle_lines(btn_x, btn_y, square_size, square_size, panel_outline_col)

		code := if gs.white_to_move { mv.promo } else { -mv.promo }
		key := (if code > 0 { 'w' } else { 'b' }) + piece_short_name(code)
		if tex := textures[key] {
			src_rect := rl.Rectangle{
				x: 0
				y: 0
				width: f32(tex.width)
				height: f32(tex.height)
			}
			dest_rect := rl.Rectangle{
				x: f32(btn_x)
				y: f32(btn_y)
				width: f32(square_size)
				height: f32(square_size)
			}
			rl.draw_texture_pro(tex, src_rect, dest_rect, rl.Vector2{}, 0.0, rl.Color{255, 255, 255, 255})
		} else {
			label := piece_short_name(code)
			font_size := 34
			tw := rl.measure_text(label, font_size)
			rl.draw_text(label, btn_x + square_size / 2 - tw / 2, btn_y + 20, font_size,
				if i % 2 == 0 { text_col } else { rl.Color{ r: 250, g: 250, b: 250, a: 255 } })
		}
	}
}

fn draw_status_bar(gs &GameState) {
	rl.draw_rectangle(0, board_pixels - 28, board_pixels, 28, rl.Color{ r: 20, g: 20, b: 20, a: 190 })
	col := if gs.game_over || gs.in_check { status_bad_col } else { text_col }
	rl.draw_text(gs.status, 8, board_pixels - 22, 18, col)
}

fn draw_hover(gs &GameState) {
	if gs.mouse_sq >= 0 {
		draw_square_overlay(gs.mouse_sq, hover_col)
	}
}

fn find_move_candidates(gs &GameState, from_sq int, to_sq int, white bool) []Move {
	mut out := []Move{}
	for mv in gs.legal_moves_from(from_sq, white) {
		if mv.to == to_sq {
			out << mv
		}
	}
	return out
}

fn (mut gs GameState) try_player_release(to_sq int) {
	if gs.game_over || gs.promoting {
		return
	}
	if gs.selected_sq < 0 {
		return
	}
	if to_sq < 0 {
		gs.selected_sq = -1
		gs.selected_moves = []Move{}
		return
	}

	candidates := find_move_candidates(gs, gs.selected_sq, to_sq, true)
	if candidates.len == 0 {
		gs.selected_sq = -1
		gs.selected_moves = []Move{}
		return
	}

	if candidates.len > 1 {
		gs.start_promotion_selection(candidates)
		return
	}

	gs.finalize_move(candidates[0])
}

fn (mut gs GameState) try_black_move() {
	if gs.game_over || gs.promoting || gs.white_to_move {
		return
	}
	moves := gs.all_legal_moves(false)
	if moves.len == 0 {
		gs.refresh_status()
		return
	}
	idx := rand.intn(moves.len) or { 0 }
	gs.finalize_move(moves[idx])
}

fn (mut gs GameState) handle_promotion_click(mouse_x int, mouse_y int) {
	if !gs.promoting {
		return
	}
	panel_w := square_size * 4
	panel_h := square_size + 48
	panel_x := (window_w - panel_w) / 2
	panel_y := (window_h - panel_h) / 2 + 26

	if mouse_y < panel_y || mouse_y >= panel_y + square_size {
		return
	}
	if mouse_x < panel_x || mouse_x >= panel_x + panel_w {
		return
	}
	idx := (mouse_x - panel_x) / square_size
	if idx >= 0 && idx < gs.promotion_moves.len {
		gs.choose_promotion(idx)
	}
}

fn main() {
	rl.init_window(window_w, window_h, 'Maia Chess Stardance Project')
	rl.set_target_fps(fps)

	mut gs := new_game()

	embedded_map := get_embedded_map()
	mut piece_textures := load_piece_textures_embedded(embedded_map)
	defer {
		for _, tex in piece_textures {
			rl.unload_texture(tex)
		}
	}

	for !rl.window_should_close() {
		mouse_x := rl.get_mouse_x()
		mouse_y := rl.get_mouse_y()
		gs.mouse_sq = pixel_to_square(mouse_x, mouse_y)

		// Input
		if gs.promoting {
			if rl.is_mouse_button_pressed(0) {
				gs.handle_promotion_click(mouse_x, mouse_y)
			}
		} else if !gs.game_over {
			if gs.white_to_move {
				if rl.is_mouse_button_pressed(0) {
					sq := pixel_to_square(mouse_x, mouse_y)
					if sq >= 0 && gs.board[sq] > 0 {
						gs.selected_sq = sq
						gs.selected_moves = gs.legal_moves_from(sq, true)
						gs.drag_active = true
					}
				}
				if rl.is_mouse_button_released(0) && gs.drag_active {
					end_sq := pixel_to_square(mouse_x, mouse_y)
					gs.try_player_release(end_sq)
					gs.drag_active = false
				}
			}
		}

		// Black AI move, immediately after White finishes a turn
		if !gs.white_to_move && !gs.promoting && !gs.game_over {
			gs.try_black_move()
		}

		rl.begin_drawing()
		rl.clear_background(rl.Color{ r: 20, g: 20, b: 20, a: 255 })

		draw_board()
		draw_last_move(gs)
		draw_hover(gs)
		draw_selection_hints(gs)
		draw_pieces(gs, piece_textures)
		draw_coords()
		if gs.promoting {
			draw_promotion_menu(gs, piece_textures)
		}
		draw_status_bar(gs)

		rl.end_drawing()
	}

	rl.close_window()
}
