# Simple console-based chess game for two players with optional 5 or 10 minute clocks.
# Supports two board orientations (white on bottom or black on bottom).

import time
import sys
from dataclasses import dataclass
from typing import Tuple, Optional

# Mapping of pieces for initial board setup using simple characters.
INITIAL_BOARD = [
    list("rnbqkbnr"),
    list("pppppppp"),
    [" "] * 8,
    [" "] * 8,
    [" "] * 8,
    [" "] * 8,
    list("PPPPPPPP"),
    list("RNBQKBNR"),
]

FILE_TO_COL = {
    "a": 0, "b": 1, "c": 2, "d": 3,
    "e": 4, "f": 5, "g": 6, "h": 7,
}

COL_TO_FILE = {v: k for k, v in FILE_TO_COL.items()}

@dataclass
class Move:
    src: Tuple[int, int]
    dst: Tuple[int, int]

class ChessGame:
    def __init__(self, minutes_per_player: int = 10, orientation_white_bottom: bool = True):
        self.board = [row[:] for row in INITIAL_BOARD]
        self.current_player = 'white'
        self.timers = {
            'white': minutes_per_player * 60,
            'black': minutes_per_player * 60,
        }
        self.orientation_white_bottom = orientation_white_bottom
        self.last_move_time = time.time()

    def switch_orientation(self):
        self.orientation_white_bottom = not self.orientation_white_bottom

    def print_board(self):
        board = self.board if self.orientation_white_bottom else self.board[::-1]
        header = '  ' + ' '.join(list('abcdefgh'))
        if not self.orientation_white_bottom:
            header = '  ' + ' '.join(list('hgfedcba'))
        print(header)
        for i, row in enumerate(board):
            rank = 8 - i if self.orientation_white_bottom else i + 1
            line = str(rank) + ' ' + ' '.join(row if self.orientation_white_bottom else row[::-1])
            print(line)
        print(header)
        print(f"Turno: {self.current_player} | Tempo restante: {self.timers['white']}s branco, {self.timers['black']}s preto")

    def parse_move(self, move_str: str) -> Optional[Move]:
        if len(move_str) not in (4, 5):
            return None
        move_str = move_str.replace(" ", "")
        try:
            src_col = FILE_TO_COL[move_str[0].lower()]
            src_row = 8 - int(move_str[1])
            dst_col = FILE_TO_COL[move_str[2].lower()]
            dst_row = 8 - int(move_str[3])
            return Move((src_row, src_col), (dst_row, dst_col))
        except (KeyError, ValueError):
            return None

    def apply_move(self, move: Move) -> bool:
        sr, sc = move.src
        dr, dc = move.dst
        piece = self.board[sr][sc]
        if piece == ' ':
            return False
        # Simple turn checking: uppercase for white, lowercase for black
        if self.current_player == 'white' and not piece.isupper():
            return False
        if self.current_player == 'black' and not piece.islower():
            return False
        self.board[dr][dc] = piece
        self.board[sr][sc] = ' '
        self.current_player = 'black' if self.current_player == 'white' else 'white'
        return True

    def update_timer(self):
        now = time.time()
        elapsed = now - self.last_move_time
        self.timers[self.current_player] -= elapsed
        self.last_move_time = now

    def is_time_up(self) -> Optional[str]:
        if self.timers['white'] <= 0:
            return 'white'
        if self.timers['black'] <= 0:
            return 'black'
        return None

def main():
    minutes = 10
    orientation_white_bottom = True
    if len(sys.argv) > 1:
        if sys.argv[1] in {'5', '10'}:
            minutes = int(sys.argv[1])
        if len(sys.argv) > 2 and sys.argv[2] == 'flip':
            orientation_white_bottom = False
    game = ChessGame(minutes_per_player=minutes, orientation_white_bottom=orientation_white_bottom)
    while True:
        game.print_board()
        if (loser := game.is_time_up()):
            winner = 'black' if loser == 'white' else 'white'
            print(f"Tempo esgotado para {loser}. {winner} vence!")
            break
        move_input = input("Digite o movimento (ex. e2e4) ou 'flip' para mudar a visão: ")
        game.update_timer()
        if move_input.strip().lower() == 'flip':
            game.switch_orientation()
            continue
        move = game.parse_move(move_input.strip())
        if not move or not game.apply_move(move):
            print("Movimento inválido. Tente novamente.")
            continue

if __name__ == "__main__":
    main()
