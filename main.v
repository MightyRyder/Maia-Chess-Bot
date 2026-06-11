module main
import rand
import os
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

const panel_ratio = 16.0 / 9.0
const panel_width = int(f32(board_pixels) * panel_ratio) - board_pixels   // ~498
const window_w_ext = board_pixels + panel_width
const window_h_ext = board_pixels

const checker_size = 40
const bg_scroll_speed = 20.0

@[heap]
struct MaiaBot {
mut:
	process      &os.Process = unsafe { nil }
	ready        bool
	thinking     bool
	pending_move string
}

struct Move {
	from int
	to int
	promo int
	en_passant bool
	castle bool
}

struct BoardSnapshot {
    board         [64]int
    white_to_move bool
    w_king_moved bool
    w_rook_a_moved bool
    w_rook_h_moved bool
    b_king_moved bool
    b_rook_a_moved bool
    b_rook_h_moved bool
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

	history []BoardSnapshot
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

fn system_prefers_dark_mode() bool {
    // Windows: check registry
    $if windows {
        res := os.execute('reg query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize" /v AppsUseLightTheme')
        if res.exit_code == 0 && res.output.contains('0x0') {
            return true   // 0x0 = dark, 0x1 = light
        }
        return false
    }
    // Linux (GNOME)
    $if linux {
        res := os.execute('gsettings get org.gnome.desktop.interface color-scheme')
        if res.exit_code == 0 && res.output.contains('prefer-dark') {
            return true
        }
        return false
    }
    // macOS
    $if macos {
        res := os.execute('defaults read -g AppleInterfaceStyle')
        if res.exit_code == 0 && res.output.trim_space() == 'Dark' {
            return true
        }
        return false
    }
    return false   // fallback: light mode
}

fn uci_sq(uci string) int {
    // "e2" → square index matching your board layout (0=a8, 63=h1)
    if uci.len < 2 { return -1 }
    f := int(uci[0]) - int(`a`)   // 'a'=0 … 'h'=7
    r := int(uci[1]) - int(`1`)   // '1'=0 … '8'=7  (uci rank, 1-based)
    row := 7 - r                   // rank 8 → row 0, rank 1 → row 7
    return row * 8 + f
}

fn uci_to_move(uci string) Move {
    // Handles normal moves ("e2e4") and promotions ("e7e8q")
    if uci.len < 4 { return Move{} }
    from := uci_sq(uci[0..2])
    to   := uci_sq(uci[2..4])
    mut promo := 0
    if uci.len == 5 {
        promo = match uci[4] {
            `q` { piece_queen }
            `r` { piece_rook }
            `b` { piece_bishop }
            `n` { piece_knight }
            else { 0 }
        }
    }
    return Move{ from: from, to: to, promo: promo }
}

fn build_castling_flags(gs &GameState) string {
    return '${if gs.w_king_moved   { 1 } else { 0 }} ' +
           '${if gs.w_rook_a_moved { 1 } else { 0 }} ' +
           '${if gs.w_rook_h_moved { 1 } else { 0 }} ' +
           '${if gs.b_king_moved   { 1 } else { 0 }} ' +
           '${if gs.b_rook_a_moved { 1 } else { 0 }} ' +
           '${if gs.b_rook_h_moved { 1 } else { 0 }}'
}

// Resolves the standard OS user-data directory for the application data
fn get_maia_install_dir() string {
	base_data_dir := os.data_dir() // Universally handles AppData, .local/share, etc.
	return os.join_path(base_data_dir, 'maia-chess-bot', 'backend-assets')
}

// Determines the binary executable filename depending on the platform
fn get_maia_exe_path() string {
	dir := get_maia_install_dir()
	$if windows {
		return os.join_path(dir, 'maia-bot.exe')
	} $else {
		return os.join_path(dir, 'maia-bot')
	}
}

// Runs a check at startup; downloads and unzips backend assets if they don't exist
fn ensure_maia_installed() ! {
    exe_path := get_maia_exe_path()
    if os.exists(exe_path) {
        return
    }

    println('Maia backend not found. Beginning automatic installation...')
    install_dir := get_maia_install_dir()
    os.mkdir_all(install_dir)!

    mut download_url := 'https://github.com/MightyRyder/Maia-Chess-Bot/releases/download/backend-assets/'
    $if windows {
        download_url += 'maia_windows_x64.zip'
    } $else $if linux {
        download_url += 'maia_linux_x64.zip'
    } $else $if macos {
        download_url += 'maia_macos_arm64.zip'
    }

    zip_path := os.join_path(install_dir, 'backend.zip')

    // Replace http.download_file with curl
    result := os.execute('curl -fsSL -o "${zip_path}" "${download_url}"')
    if result.exit_code != 0 {
        return error('Download failed: ${result.output}')
    }

    $if windows {
        os.execute('powershell -Command "Expand-Archive -Path \'${zip_path}\' -DestinationPath \'${install_dir}\' -Force"')
    } $else {
        os.execute('unzip -q "${zip_path}" -d "${install_dir}"')
        os.chmod(exe_path, 0o755)!
    }

    os.rm(zip_path)!
    println('Maia backend successfully deployed to: $install_dir')
}

fn new_maia_bot() &MaiaBot {
	// First, verify everything is downloaded and extracted
	ensure_maia_installed() or {
		eprintln('ERROR: Failed to verify or install maia backend: $err')
		return &MaiaBot{ process: unsafe { nil }, ready: false }
	}

	exe_path := get_maia_exe_path()
	install_dir := get_maia_install_dir()

	// Launch the compiled standalone binary directly
	mut p := os.new_process(exe_path)
	p.work_folder = install_dir // Keeps file context confined to installation path

	p.run()

	if p.pid == 0 {
		eprintln('ERROR: failed to launch maia bot (PID 0)')
		return &MaiaBot{ process: unsafe { nil }, ready: false }
	}

	println('maia backend pid: ${p.pid}')
	return &MaiaBot{ process: p, ready: false }
}

fn (mut bot MaiaBot) send_move_request(fen string, elo_self int, elo_oppo int) {
	install_dir := get_maia_install_dir()
	req := os.join_path(install_dir, 'maia_req.txt')
	res := os.join_path(install_dir, 'maia_res.txt')
	
	os.rm(res) or {}
	os.write_file(req, '${fen}|${elo_self}|${elo_oppo}') or {}
}

fn (mut bot MaiaBot) check_move_response() ?string {
	install_dir := get_maia_install_dir()
	res := os.join_path(install_dir, 'maia_res.txt')
	
	if !os.exists(res) {
		return none
	}
	line := os.read_file(res) or { return none }
	// Don't delete here - let get_eval_from_response() clean up after reading eval
	if line.starts_with('BEST_MOVE ') {
		return line['BEST_MOVE '.len..].trim_space()
	}
	return none
}

fn (mut bot MaiaBot) get_eval_from_response() f32 {
	install_dir := get_maia_install_dir()
	res := os.join_path(install_dir, 'maia_res.txt')
	
	if !os.exists(res) {
		return 0.0
	}
	content := os.read_file(res) or { return 0.0 }
	os.rm(res) or {}  // Clean up after reading eval
	
	for line in content.split('\n') {
		if line.starts_with('EVAL ') {
			eval_str := line['EVAL '.len..].trim_space()
			return eval_str.f32()
		}
	}
	return 0.0
}

fn update_eval(gs &GameState, mut maia MaiaBot) f32 {
	// Get evaluation from the maia bot response file
	// Stockfish always returns eval from white's perspective
	return maia.get_eval_from_response()
}

fn uci_to_squares(move_str string) (int, int) {
    if move_str.len < 4 { return -1, -1 }
    from := uci_sq(move_str[0..2])
    to   := uci_sq(move_str[2..4])
    return from, to
}

fn board_to_fen(gs &GameState) string {
	abs_to_char := fn(code int) u8 {
		return match piece_abs(code) {
			piece_pawn   { `p` }
			piece_knight { `n` }
			piece_bishop { `b` }
			piece_rook   { `r` }
			piece_queen  { `q` }
			piece_king   { `k` }
			else         { `?` }
		}
	}

	mut rows := []string{}
	for rank in 0..8 {
		mut empty := 0
		mut row := ''
		for file in 0..8 {
			code := gs.board[rank * 8 + file]
			if code == 0 {
				empty++
			} else {
				if empty > 0 { row += empty.str(); empty = 0 }
				ch := abs_to_char(code)
				row += if code > 0 { ch.ascii_str().to_upper() } else { ch.ascii_str() }
			}
		}
		if empty > 0 { row += empty.str() }
		rows << row
	}

	side := if gs.white_to_move { 'w' } else { 'b' }

	mut castling := ''
	if !gs.w_king_moved && !gs.w_rook_h_moved { castling += 'K' }
	if !gs.w_king_moved && !gs.w_rook_a_moved { castling += 'Q' }
	if !gs.b_king_moved && !gs.b_rook_h_moved { castling += 'k' }
	if !gs.b_king_moved && !gs.b_rook_a_moved { castling += 'q' }
	if castling == '' { castling = '-' }

	ep := if gs.en_passant_sq >= 0 {
		files := ['a','b','c','d','e','f','g','h']
		rank := 8 - gs.en_passant_sq / 8
		'${files[gs.en_passant_sq % 8]}${rank}'
	} else {
		'-'
	}

	return '${rows.join('/')} ${side} ${castling} ${ep} 0 1'
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
		// white pawns attack upward (to lower index). A white pawn at sq+7 or sq+9
		// attacks sq — but only if it doesn't wrap across the file boundary.
		if rank_of(sq) + 1 < 8 {
			if file_of(sq) > 0 && gs.board[sq + 7] == piece_pawn {
				return true
			}
			if file_of(sq) < 7 && gs.board[sq + 9] == piece_pawn {
				return true
			}
		}
	} else {
		// black pawns attack downward (to higher index). A black pawn at sq-7 or sq-9
		// attacks sq — but only if it doesn't wrap across the file boundary.
		if rank_of(sq) - 1 >= 0 {
			if file_of(sq) < 7 && gs.board[sq - 7] == -piece_pawn {
				return true
			}
			if file_of(sq) > 0 && gs.board[sq - 9] == -piece_pawn {
				return true
			}
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

fn (mut gs GameState) save_snapshot() {
    snapshot := BoardSnapshot{
        board: gs.board
        white_to_move: gs.white_to_move
        w_king_moved: gs.w_king_moved
        w_rook_a_moved: gs.w_rook_a_moved
        w_rook_h_moved: gs.w_rook_h_moved
        b_king_moved: gs.b_king_moved
        b_rook_a_moved: gs.b_rook_a_moved
        b_rook_h_moved: gs.b_rook_h_moved
    }
    gs.history << snapshot
}

fn (mut gs GameState) load_snapshot(snapshot BoardSnapshot) {
    gs.board = snapshot.board
    gs.white_to_move = snapshot.white_to_move
    gs.w_king_moved = snapshot.w_king_moved
    gs.w_rook_a_moved = snapshot.w_rook_a_moved
    gs.w_rook_h_moved = snapshot.w_rook_h_moved
    gs.b_king_moved = snapshot.b_king_moved
    gs.b_rook_a_moved = snapshot.b_rook_a_moved
    gs.b_rook_h_moved = snapshot.b_rook_h_moved
}

fn (mut gs GameState) undo_move() {
    if gs.history.len > 2 {
        gs.history.pop()
        gs.history.pop()
        last_snapshot := gs.history.last()
        gs.load_snapshot(last_snapshot)
        gs.refresh_status()
    }
}

fn (mut gs GameState) update_eval(mut bot MaiaBot) {
	if gs.game_over {
		return
	}

	fen := board_to_fen(gs)

	max_elo := 2600
	bot.send_move_request(fen, max_elo, max_elo)
}

fn draw_best_move_hint(from_sq int, to_sq int) {
    if from_sq < 0 || to_sq < 0 {
        return
    }

    from_x, from_y := square_to_pixel(from_sq)
    to_x, to_y := square_to_pixel(to_sq)

    // Highlight the two squares
    rl.draw_rectangle(from_x, from_y, square_size, square_size, rl.Color{0, 228, 48, 100})
    rl.draw_rectangle(to_x, to_y, square_size, square_size, rl.Color{0, 228, 48, 160})

    // Arrow from centre of from‑square to centre of to‑square
    start_v := rl.Vector2{
        x: f32(from_x) + f32(square_size) * 0.5,
        y: f32(from_y) + f32(square_size) * 0.5,
    }
    end_v := rl.Vector2{
        x: f32(to_x) + f32(square_size) * 0.5,
        y: f32(to_y) + f32(square_size) * 0.5,
    }
    rl.draw_line_ex(start_v, end_v, 6.0, rl.Color{0, 228, 48, 225})
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
	panel_x := (window_w_ext - panel_w) / 2
	panel_y := (window_h_ext - panel_h) / 2

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

fn draw_hover(gs &GameState) {
	if gs.mouse_sq >= 0 {
		draw_square_overlay(gs.mouse_sq, hover_col)
	}
}

fn draw_scrolling_checkerboard(x int, y int, w int, h int, offset f64, dark_mode bool) {
    tile1 := if dark_mode { rl.Color{60, 60, 60, 255} } else { rl.Color{255, 255, 255, 255} }
    tile2 := if dark_mode { rl.Color{30, 30, 30, 255} } else { rl.Color{220, 220, 220, 255} }

    rl.begin_scissor_mode(x, y, w, h)

    // Calculate a smooth pixel shift that wraps around every checker_size (40)
    shift := int(offset) % checker_size

    // Start drawing one tile early (-shift) to cover the gap as the board slides
    for j := y - shift; j < y + h + checker_size; j += checker_size {
        for i := x - shift; i < x + w + checker_size; i += checker_size {
            
            // Calculate the logical grid row/col to alternate colors
            col := (i - x + shift) / checker_size
            row := (j - y + shift) / checker_size

            color := if (row + col) % 2 == 0 { tile1 } else { tile2 }
            rl.draw_rectangle(i, j, checker_size, checker_size, color)
        }
    }
    
    rl.end_scissor_mode()
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

	gs.save_snapshot()
	gs.finalize_move(candidates[0])
}

fn (mut gs GameState) try_black_move(mut bot MaiaBot, bot_elo int) {
	if gs.game_over || gs.promoting || gs.white_to_move || bot.thinking { return }
	if !bot.ready {
		install_dir := get_maia_install_dir()
		ready_path := os.join_path(install_dir, 'maia_ready.txt')
		if os.exists(ready_path) {
			bot.ready = true
		} else {
			return
		}
	}
	bot.thinking = true
	fen := board_to_fen(gs)
	bot.send_move_request(fen, bot_elo, bot_elo)
}

fn (mut gs GameState) apply_pending_move(mut bot MaiaBot) {
	if !bot.thinking || gs.game_over || gs.promoting || gs.white_to_move {
		return
	}
	if best_uci := bot.check_move_response() {
		bot.thinking = false

		hint := uci_to_move(best_uci)
		legal := gs.all_legal_moves(false)
		mut found := false
		for mv in legal {
			if mv.from == hint.from && mv.to == hint.to {
				if hint.promo == 0 || mv.promo == hint.promo {
					gs.finalize_move(mv)
					found = true
					break
				}
			}
		}
		if !found {
			eprintln('maia: ${best_uci} not legal, falling back to random')
			moves := gs.all_legal_moves(false)
			if moves.len == 0 { gs.refresh_status(); return }
			gs.finalize_move(moves[rand.intn(moves.len) or { 0 }])
		}
	}
}

fn (mut gs GameState) handle_promotion_click(mouse_x int, mouse_y int) {
	if !gs.promoting {
		return
	}
	panel_w := square_size * 4
	panel_h := square_size + 48
	panel_x := (window_w_ext - panel_w) / 2
	panel_y := (window_h_ext - panel_h) / 2 + 26

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
    mut bot_elo := 1000
    min_elo := 600
    max_elo := 2600
    mut is_dragging_elo := false
    mut anim_offset := f64(0.0)
    dark_mode := system_prefers_dark_mode()

    mut current_eval := f32(0.0)
    mut show_best_move := false

	mut hint_requested := false
	mut hint_from_sq := -1
	mut hint_to_sq := -1

    rl.set_config_flags(.flag_window_resizable | .flag_vsync_hint)
    rl.init_window(window_w_ext, window_h_ext, 'Maia Chess Stardance Project')
    rl.set_target_fps(fps)

    render_tex := rl.load_render_texture(window_w_ext, window_h_ext)
    defer { rl.unload_render_texture(render_tex) }

    mut gs := new_game()
    mut maia := new_maia_bot()

    embedded_map := get_embedded_map()
    mut piece_textures := load_piece_textures_embedded(embedded_map)
    defer {
        for _, tex in piece_textures {
            rl.unload_texture(tex)
        }
    }

    for !rl.window_should_close() {
        dt := rl.get_frame_time()
        anim_offset += bg_scroll_speed * f64(dt)
        
        sw := f32(rl.get_screen_width())
        sh := f32(rl.get_screen_height())

        raw_mouse_x := f32(rl.get_mouse_x())
        raw_mouse_y := f32(rl.get_mouse_y())

        mouse_x := int((raw_mouse_x / sw) * f32(window_w_ext))
        mouse_y := int((raw_mouse_y / sh) * f32(window_h_ext))
        mouse_pos := rl.Vector2{f32(mouse_x), f32(mouse_y)}

        gs.mouse_sq = pixel_to_square(mouse_x, mouse_y)

        slider_x := f32(window_w_ext - 80) 
        slider_y := f32(100)
        slider_w := f32(20)
        slider_h := f32(400)

        btn_w := f32(110)
        btn_h := f32(35)
        btn_new_game := rl.Rectangle{ slider_x - 140, slider_y, btn_w, btn_h }
        btn_undo := rl.Rectangle{ slider_x - 140, slider_y + 50, btn_w, btn_h }
        btn_best_move := rl.Rectangle{ slider_x - 140, slider_y + 100, btn_w, btn_h }

        if rl.is_mouse_button_pressed(0) {
            if rl.check_collision_point_rec(mouse_pos, btn_new_game) {
                gs = new_game()
                show_best_move = false
				current_eval = 0.0
            } else if rl.check_collision_point_rec(mouse_pos, btn_undo) {
                gs.undo_move()
                show_best_move = false
				current_eval = update_eval(gs, mut maia)
            } else if rl.check_collision_point_rec(mouse_pos, btn_best_move) {
				show_best_move = !show_best_move
				if !show_best_move {
					hint_requested = false
					hint_from_sq = -1
					hint_to_sq = -1
				}
			}
        }

        if gs.promoting {
            if rl.is_mouse_button_pressed(0) {
                gs.handle_promotion_click(mouse_x, mouse_y)
				if !gs.promoting {
					current_eval = update_eval(gs, mut maia)
				}
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
					last_move_count := gs.history.len
					gs.try_player_release(end_sq)
					gs.drag_active = false
					show_best_move = false
					if gs.history.len > last_move_count {
						current_eval = update_eval(gs, mut maia)
					}
				}
            }
        }

        elo_percent := f32(bot_elo - min_elo) / f32(max_elo - min_elo)
        handle_y := slider_y + slider_h - (elo_percent * slider_h)
        
        handle_rect := rl.Rectangle{ slider_x - 10, handle_y - 10, slider_w + 20, 20 }
        track_rect := rl.Rectangle{ slider_x, slider_y, slider_w, slider_h }

        if rl.is_mouse_button_pressed(0) {
            if rl.check_collision_point_rec(mouse_pos, handle_rect) ||
               rl.check_collision_point_rec(mouse_pos, track_rect) {
                is_dragging_elo = true
            }
        }

        if rl.is_mouse_button_released(0) {
            is_dragging_elo = false
        }

        if is_dragging_elo {
            mut clamped_y := f32(mouse_y)
            if clamped_y < slider_y { clamped_y = slider_y }
            if clamped_y > slider_y + slider_h { clamped_y = slider_y + slider_h }

            new_percent := 1.0 - ((clamped_y - slider_y) / slider_h)
            bot_elo = min_elo + int(new_percent * f32(max_elo - min_elo))
        }

        if !gs.white_to_move && !gs.promoting && !gs.game_over {
            gs.try_black_move(mut maia, bot_elo)
            show_best_move = false
        }
        if !gs.white_to_move && !gs.promoting && !gs.game_over {
            gs.apply_pending_move(mut maia)
			current_eval = update_eval(gs, mut maia)
        }

		if gs.white_to_move && show_best_move {
            if !hint_requested && hint_from_sq == -1 {
                // Generate the standard FEN layout string from your GameState
                fen_str := board_to_fen(gs)
                
                // Always use max ELO for best move
                maia.send_move_request(fen_str, max_elo, 0)
                hint_requested = true
            }
            if hint_requested {
                // Safely unwrap the optional string response from the text loop file
                if move_str := maia.check_move_response() {
                    // Use your native tracker to turn a uci string like "g1f3" into array coordinates
                    from_sq, to_sq := uci_to_squares(move_str)
                    hint_from_sq = from_sq
                    hint_to_sq = to_sq
                    hint_requested = false
                }
            }
        }

		if !gs.white_to_move {
			hint_requested = false
			hint_from_sq = -1
			hint_to_sq = -1
		}

        rl.begin_texture_mode(render_tex)
        rl.clear_background(rl.Color{20, 20, 20, 255})

        draw_board()
        draw_last_move(gs)
        draw_hover(gs)
        draw_selection_hints(gs)
        draw_pieces(gs, piece_textures)
        draw_coords()

        if show_best_move {
			draw_best_move_hint(hint_from_sq, hint_to_sq)
		}

        draw_scrolling_checkerboard(board_pixels, 0, panel_width, board_pixels, anim_offset, dark_mode)

        eval_bar_x := f32(board_pixels + 20)
        eval_bar_y := f32(100)
        eval_bar_w := f32(20)
        eval_bar_h := f32(400)

        // Draw status text at bottom of screen with eval bar alignment
        status_col := if gs.game_over || gs.in_check { status_bad_col } else { text_col }
        rl.draw_text(gs.status, int(eval_bar_x) - 5, int(window_h_ext) - 25, 14, status_col)

        rl.draw_rectangle_rec(track_rect, rl.Color{50, 50, 50, 255})

        filled_height := (slider_y + slider_h) - handle_y
        filled_rect := rl.Rectangle{ slider_x, handle_y, slider_w, filled_height }
        rl.draw_rectangle_rec(filled_rect, rl.Color{200, 50, 50, 255})

        rl.draw_rectangle_rec(handle_rect, rl.Color{220, 220, 220, 255})

        elo_str := if bot_elo >= max_elo { "ELO: MAX" } else { "ELO: $bot_elo" }
        rl.draw_text(elo_str, int(slider_x) - 15, int(slider_y) - 30, 18, rl.Color{255, 255, 255, 255})

        color_new_game := if rl.check_collision_point_rec(mouse_pos, btn_new_game) { rl.Color{90, 90, 90, 255} } else { rl.Color{60, 60, 60, 255} }
        rl.draw_rectangle_rec(btn_new_game, color_new_game)
        rl.draw_text("New Game", int(btn_new_game.x) + 14, int(btn_new_game.y) + 10, 14, rl.Color{255, 255, 255, 255})

        color_undo := if rl.check_collision_point_rec(mouse_pos, btn_undo) { rl.Color{90, 90, 90, 255} } else { rl.Color{60, 60, 60, 255} }
        rl.draw_rectangle_rec(btn_undo, color_undo)
        rl.draw_text("Undo Move", int(btn_undo.x) + 14, int(btn_undo.y) + 10, 14, rl.Color{255, 255, 255, 255})

        color_best_move := if show_best_move { rl.Color{180, 50, 50, 255} } else if rl.check_collision_point_rec(mouse_pos, btn_best_move) { rl.Color{90, 90, 90, 255} } else { rl.Color{60, 60, 60, 255} }
        rl.draw_rectangle_rec(btn_best_move, color_best_move)
        rl.draw_text("Best Move", int(btn_best_move.x) + 14, int(btn_best_move.y) + 10, 14, rl.Color{255, 255, 255, 255})

        rl.draw_rectangle(int(eval_bar_x), int(eval_bar_y), int(eval_bar_w), int(eval_bar_h), rl.Color{30, 30, 30, 255})

        clamped_eval := if current_eval > 10.0 { 10.0 } else if current_eval < -10.0 { -10.0 } else { current_eval }
        white_pct := (clamped_eval + 10.0) / 20.0
        white_fill_h := eval_bar_h * white_pct
        white_fill_y := eval_bar_y + (eval_bar_h - white_fill_h)

        rl.draw_rectangle(int(eval_bar_x), int(white_fill_y), int(eval_bar_w), int(white_fill_h), rl.Color{220, 220, 220, 255})
        rl.draw_text(current_eval.str(), int(eval_bar_x) - 5, int(eval_bar_y) - 25, 16, rl.Color{255, 255, 255, 255})

        if gs.promoting {
            draw_promotion_menu(gs, piece_textures)
        }

        rl.end_texture_mode()

        rl.begin_drawing()
        rl.clear_background(rl.Color{0, 0, 0, 255})

        src := rl.Rectangle{0, 0, f32(window_w_ext), -f32(window_h_ext)}
        dest := rl.Rectangle{0, 0, sw, sh}
        rl.draw_texture_pro(render_tex.texture, src, dest, rl.Vector2{}, 0, rl.Color{255, 255, 255, 255})

        rl.end_drawing()

        if rl.is_key_pressed(int(rl.KeyboardKey.key_f)) {
            rl.toggle_fullscreen()
        }
    }

   // Clean up bot processes
	$if windows {
		os.execute('taskkill /f /im maia-bot.exe >nul 2>&1')
	} $else {
		os.execute('pkill -9 maia-bot')
	}

    rl.close_window()
}
