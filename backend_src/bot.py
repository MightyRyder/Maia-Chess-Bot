#!/usr/bin/env python3
"""
bot.py — Maia 2 move advisor for the V/Raylib chess engine.

Board encoding matches main.v exactly:
  Positive  = white piece, Negative = black piece, 0 = empty
  1=pawn 2=knight 3=bishop 4=rook 5=queen 6=king
  Index 0 = a8 (top-left), 63 = h1 (bottom-right)  [row-major, rank 8 first]

Usage
-----
  python bot.py \\
      --board "0 0 -4 -5 -6 -3 -2 -4  ..." \\   # 64 ints, space-separated
      --white-to-move 1                            # 1 = white, 0 = black
      --elo-self  1500 \\
      --elo-oppo  1500 \\
      [--game-type rapid]                          # rapid | blitz
      [--en-passant -1]                            # target square index, -1 = none
      [--castling-rights "KQkq"]                   # FEN castling string
      [--top-n 3]                                  # how many moves to print
      [--device cpu]                               # cpu | gpu

The script outputs one line:
  BEST_MOVE <uci>   e.g.  BEST_MOVE e2e4

Followed by the top-N likely moves with probabilities.
"""

import argparse
import sys

# ---------------------------------------------------------------------------
# Piece / square helpers (mirror main.v constants)
# ---------------------------------------------------------------------------
PIECE_NONE   = 0
PIECE_PAWN   = 1
PIECE_KNIGHT = 2
PIECE_BISHOP = 3
PIECE_ROOK   = 4
PIECE_QUEEN  = 5
PIECE_KING   = 6

FILES = "abcdefgh"

def sq_to_uci(sq: int) -> str:
    """Convert flat board index (0=a8 … 63=h1) to UCI square name."""
    rank = 8 - sq // 8        # row 0 → rank 8, row 7 → rank 1
    file = sq % 8             # col 0 → 'a', col 7 → 'h'
    return FILES[file] + str(rank)

def board_to_fen(board: list[int],
                 white_to_move: bool,
                 castling: str,
                 ep_sq: int) -> str:
    """
    Convert the engine's flat [64]int board to a FEN string.

    Piece mapping (same sign convention as main.v):
      +1 wP  +2 wN  +3 wB  +4 wR  +5 wQ  +6 wK
      -1 bP  -2 bN  -3 bB  -4 bR  -5 bQ  -6 bK
    """
    abs_to_char = {
        PIECE_PAWN:   'p',
        PIECE_KNIGHT: 'n',
        PIECE_BISHOP: 'b',
        PIECE_ROOK:   'r',
        PIECE_QUEEN:  'q',
        PIECE_KING:   'k',
    }

    rows = []
    for rank in range(8):          # rank 8 (row 0) → rank 1 (row 7)
        empty = 0
        row_str = ""
        for file in range(8):
            code = board[rank * 8 + file]
            if code == 0:
                empty += 1
            else:
                if empty:
                    row_str += str(empty)
                    empty = 0
                ch = abs_to_char[abs(code)]
                row_str += ch.upper() if code > 0 else ch
        if empty:
            row_str += str(empty)
        rows.append(row_str)

    piece_placement = "/".join(rows)
    side = "w" if white_to_move else "b"
    castling_str = castling if castling else "-"
    ep_str = sq_to_uci(ep_sq) if ep_sq >= 0 else "-"

    return f"{piece_placement} {side} {castling_str} {ep_str} 0 1"


# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(
        description="Query Maia 2 for the most human-like move at a given ELO."
    )
    p.add_argument(
        "--board", required=False,
        help='64 space-separated ints matching the V engine board (0=a8 … 63=h1).'
    )
    p.add_argument(
        "--white-to-move", type=int, required=False, choices=[0, 1],
        help="1 = white to move, 0 = black to move."
    )
    p.add_argument(
        "--elo-self", type=int, required=False,
        help="ELO of the side to move (Maia 2 range: ~1100–2300)."
    )
    p.add_argument(
        "--elo-oppo", type=int, required=False,
        help="ELO of the opponent."
    )
    p.add_argument(
        "--game-type", default="rapid", choices=["rapid", "blitz"],
        help='Model variant: "rapid" (default) or "blitz".'
    )
    p.add_argument(
        "--en-passant", type=int, default=-1,
        help="En-passant target square index (same encoding as V engine; -1 = none)."
    )
    p.add_argument(
        "--castling-rights", default=None,
        help='FEN-style castling rights, e.g. "KQkq", "Kq", "-". '
             'Ignored when --castling-bools is given.'
    )
    p.add_argument(
        "--castling-bools",
        nargs=6, type=int, metavar=("WK_MOVED", "WR_A_MOVED", "WR_H_MOVED",
                                    "BK_MOVED", "BR_A_MOVED", "BR_H_MOVED"),
        help="Six 0/1 flags matching GameState fields: "
             "w_king_moved w_rook_a_moved w_rook_h_moved "
             "b_king_moved b_rook_a_moved b_rook_h_moved. "
             "Overrides --castling-rights."
    )
    p.add_argument(
        "--top-n", type=int, default=3,
        help="How many top moves to display (default 3)."
    )
    p.add_argument(
        "--device", default="cpu", choices=["cpu", "gpu"],
        help="Inference device (default cpu)."
    )
    return p.parse_args()


# ---------------------------------------------------------------------------
# Castling helpers
# ---------------------------------------------------------------------------
def castling_bools_to_str(wk_moved: bool, wr_a_moved: bool, wr_h_moved: bool,
                           bk_moved: bool, br_a_moved: bool, br_h_moved: bool) -> str:
    """
    Convert the six castling-rights booleans from GameState to a FEN castling string.

    A right is available when *neither* the king nor the relevant rook has moved.
    """
    s = ""
    if not wk_moved and not wr_h_moved: s += "K"
    if not wk_moved and not wr_a_moved: s += "Q"
    if not bk_moved and not br_h_moved: s += "k"
    if not bk_moved and not br_a_moved: s += "q"
    return s or "-"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    import sys, os, time

    args = parse_args()

    from maia2 import model as maia2_model_mod, inference as maia2_inf

    maia_model = maia2_model_mod.from_pretrained(type=args.game_type, device=args.device)
    prepared = maia2_inf.prepare()

    # Dynamically resolve the absolute path at runtime.
    # Since V sets p.work_folder, this will point straight to the install directory.
    base_dir = os.getcwd()

    ready_path = os.path.join(base_dir, 'maia_ready.txt')
    req        = os.path.join(base_dir, 'maia_req.txt')
    res        = os.path.join(base_dir, 'maia_res.txt')

    # Signal that the engine is loaded and ready
    with open(ready_path, 'w') as f:
        f.write('ready\n')

    while True:
        if os.path.exists(req):
            try:
                with open(req, 'r') as f:
                    line = f.read().strip()
                os.remove(req)

                parts = line.split('|')
                fen      = parts[0]
                elo_self = int(parts[1])
                elo_oppo = int(parts[2])

                move_probs, win_prob = maia2_inf.inference_each(
                    maia_model, prepared, fen, elo_self, elo_oppo
                )
                best = max(move_probs, key=move_probs.get)

                with open(res, 'w') as f:
                    f.write(f'BEST_MOVE {best}\n')

            except Exception as e:
                with open(res, 'w') as f:
                    f.write('ERROR\n')
        else:
            time.sleep(0.05)

if __name__ == "__main__":
    main()