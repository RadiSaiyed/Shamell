"use strict";

/*
 * Drei-Männer-Mühle (Three Men's Morris) — game logic.
 *
 * Board is a 3x3 grid; each player owns three pieces.
 *
 *   Phase 1 — Setzen:
 *     Players alternately place one of their three pieces on any
 *     empty cell. X opens. A 3-in-a-row formed during placement
 *     ends the round immediately.
 *
 *   Phase 2 — Ziehen:
 *     Once all six pieces are on the board, players alternately
 *     pick up one of their own pieces and drop it on any empty cell
 *     (free-movement variant — pieces jump, no adjacency required).
 *     First to line up three wins.
 *
 *   A player with no legal move on their turn loses. Under the
 *   free-movement rule there are always three empty cells, so this
 *   case is guarded for safety but is effectively unreachable.
 *
 * AI difficulty:
 *   * easy   — uniformly random legal move.
 *   * medium — heuristic: win if possible, else block an immediate
 *              loss, else prefer center → corner → side during the
 *              setup phase, else random.
 *   * hard   — depth-limited alpha-beta minimax with a threat-based
 *              heuristic and move ordering. Plays near-optimally
 *              and punishes any imperfect human response.
 *
 * Win counts persist in localStorage. The game has no draws, so we
 * track only wins_x / wins_o.
 */

const WIN_LINES = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

const PIECES_PER_PLAYER = 3;
const TOTAL_PIECES = PIECES_PER_PLAYER * 2;

// Minimax search depth for "hard". 8 plies easily covers any forced
// win in this game and keeps response time well under a second with
// alpha-beta pruning + move ordering.
const HARD_DEPTH = 8;
const WIN_SCORE = 10000;

const STATS_KEY = "morris3.stats.v1";

const state = {
  board: emptyBoard(),
  current: "X",
  mode: null, // "local" | "ai-easy" | "ai-medium" | "ai-hard"
  humanPlayer: "X",
  aiPlayer: "O",
  finished: false,
  winningLine: null,
  piecesX: 0,
  piecesO: 0,
  selected: null, // index of own piece picked up during movement phase
};

function emptyBoard() {
  return new Array(9).fill(null);
}

function other(mark) {
  return mark === "X" ? "O" : "X";
}

function isPlacementPhase() {
  return state.piecesX + state.piecesO < TOTAL_PIECES;
}

// ---------- Stats ----------

function loadStats() {
  try {
    const raw = localStorage.getItem(STATS_KEY);
    if (!raw) return { wins_x: 0, wins_o: 0 };
    const parsed = JSON.parse(raw);
    return {
      wins_x: Number.isFinite(parsed.wins_x) ? parsed.wins_x : 0,
      wins_o: Number.isFinite(parsed.wins_o) ? parsed.wins_o : 0,
    };
  } catch (_) {
    return { wins_x: 0, wins_o: 0 };
  }
}

function saveStats(stats) {
  try {
    localStorage.setItem(STATS_KEY, JSON.stringify(stats));
  } catch (_) {
    // localStorage may be unavailable; the game still works.
  }
}

function renderStats() {
  const stats = loadStats();
  for (const key of ["wins_x", "wins_o"]) {
    const node = document.querySelector(`[data-stat="${key}"]`);
    if (node) node.textContent = String(stats[key]);
  }
}

function recordWin(player) {
  const stats = loadStats();
  if (player === "X") stats.wins_x += 1;
  else stats.wins_o += 1;
  saveStats(stats);
}

// ---------- Win detection ----------

function findWinningLine(board) {
  for (const line of WIN_LINES) {
    const [a, b, c] = line;
    if (board[a] && board[a] === board[b] && board[a] === board[c]) {
      return { winner: board[a], line };
    }
  }
  return null;
}

function countThreats(board, who) {
  // Lines where `who` has two marks and the third cell is empty —
  // single-move winning shots on the next turn.
  let n = 0;
  for (const line of WIN_LINES) {
    let mine = 0;
    let theirs = 0;
    for (const idx of line) {
      const v = board[idx];
      if (v === who) mine++;
      else if (v !== null) theirs++;
    }
    if (mine === 2 && theirs === 0) n++;
  }
  return n;
}

// ---------- Move generation ----------
//
// A move is { from: number|null, to: number }. `from === null` is a
// placement; otherwise the piece at `from` is picked up and dropped
// on the empty `to`.

function legalMoves(board, toMove, piecesX, piecesO) {
  const moves = [];
  if (piecesX + piecesO < TOTAL_PIECES) {
    for (let i = 0; i < 9; i++) {
      if (board[i] === null) moves.push({ from: null, to: i });
    }
  } else {
    for (let from = 0; from < 9; from++) {
      if (board[from] !== toMove) continue;
      for (let to = 0; to < 9; to++) {
        if (board[to] === null) moves.push({ from, to });
      }
    }
  }
  return moves;
}

function doMove(board, move, who) {
  if (move.from !== null) board[move.from] = null;
  board[move.to] = who;
}

function undoMove(board, move, who) {
  board[move.to] = null;
  if (move.from !== null) board[move.from] = who;
}

// ---------- AI ----------

function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function aiMoveEasy(ctx) {
  return pickRandom(legalMoves(ctx.board, ctx.toMove, ctx.piecesX, ctx.piecesO));
}

function aiMoveMedium(ctx, me, opp) {
  const moves = legalMoves(ctx.board, me, ctx.piecesX, ctx.piecesO);

  // 1. Take an immediate win if one exists.
  for (const m of moves) {
    doMove(ctx.board, m, me);
    const won = findWinningLine(ctx.board)?.winner === me;
    undoMove(ctx.board, m, me);
    if (won) return m;
  }

  // 2. If the opponent has an immediate win, occupy that cell to block.
  const oppMoves = legalMoves(ctx.board, opp, ctx.piecesX, ctx.piecesO);
  let blockCell = null;
  for (const m of oppMoves) {
    doMove(ctx.board, m, opp);
    const won = findWinningLine(ctx.board)?.winner === opp;
    undoMove(ctx.board, m, opp);
    if (won) {
      blockCell = m.to;
      break;
    }
  }
  if (blockCell !== null) {
    const blocker = moves.find((m) => m.to === blockCell);
    if (blocker) return blocker;
  }

  // 3. Placement-phase preferences: center, then a corner, then a side.
  if (ctx.piecesX + ctx.piecesO < TOTAL_PIECES) {
    const center = moves.find((m) => m.to === 4);
    if (center) return center;
    const corners = moves.filter((m) => [0, 2, 6, 8].includes(m.to));
    if (corners.length) return pickRandom(corners);
  }

  return pickRandom(moves);
}

function evalHeuristic(board, me, opp) {
  // Completed lines dominate everything else — they short-circuit
  // both the move ordering and the search proper. Without this,
  // ordering can bury an immediate win behind moves that merely
  // create new two-mark threats.
  const w = findWinningLine(board);
  if (w) return w.winner === me ? WIN_SCORE : -WIN_SCORE;
  // Otherwise: threat differential dominates; center control is a
  // small positional kicker.
  let score = (countThreats(board, me) - countThreats(board, opp)) * 12;
  if (board[4] === me) score += 2;
  else if (board[4] === opp) score -= 2;
  return score;
}

function orderMoves(ctx, moves, me, opp) {
  // Score every move with the heuristic and sort so the best for
  // the side-to-move appears first. Cheap, but cuts alpha-beta
  // search size dramatically.
  const maxing = ctx.toMove === me;
  const scored = moves.map((m) => {
    doMove(ctx.board, m, ctx.toMove);
    const s = evalHeuristic(ctx.board, me, opp);
    undoMove(ctx.board, m, ctx.toMove);
    return { m, s };
  });
  scored.sort((a, b) => (maxing ? b.s - a.s : a.s - b.s));
  return scored.map((x) => x.m);
}

function minimaxMorris(ctx, me, opp, depth, alpha, beta, ply) {
  const winLine = findWinningLine(ctx.board);
  if (winLine) {
    return {
      score: winLine.winner === me ? WIN_SCORE - ply : -WIN_SCORE + ply,
    };
  }
  if (depth === 0) {
    return { score: evalHeuristic(ctx.board, me, opp) };
  }

  const rawMoves = legalMoves(ctx.board, ctx.toMove, ctx.piecesX, ctx.piecesO);
  if (rawMoves.length === 0) {
    // Side-to-move is stuck — they lose. Cannot occur under free
    // movement, but the search needs a defined value.
    return {
      score: ctx.toMove === me ? -WIN_SCORE + ply : WIN_SCORE - ply,
    };
  }

  const moves = orderMoves(ctx, rawMoves, me, opp);
  const maxing = ctx.toMove === me;
  let bestMove = moves[0];
  let bestScore = maxing ? -Infinity : Infinity;

  for (const m of moves) {
    const mover = ctx.toMove;
    doMove(ctx.board, m, mover);
    if (m.from === null) {
      if (mover === "X") ctx.piecesX++;
      else ctx.piecesO++;
    }
    ctx.toMove = other(mover);

    const r = minimaxMorris(ctx, me, opp, depth - 1, alpha, beta, ply + 1);

    ctx.toMove = mover;
    if (m.from === null) {
      if (mover === "X") ctx.piecesX--;
      else ctx.piecesO--;
    }
    undoMove(ctx.board, m, mover);

    if (maxing) {
      if (r.score > bestScore) {
        bestScore = r.score;
        bestMove = m;
      }
      if (bestScore > alpha) alpha = bestScore;
      if (alpha >= beta) break;
    } else {
      if (r.score < bestScore) {
        bestScore = r.score;
        bestMove = m;
      }
      if (bestScore < beta) beta = bestScore;
      if (alpha >= beta) break;
    }
  }
  return { score: bestScore, move: bestMove };
}

function aiMoveHard(ctx, me, opp) {
  // Opening: claim the center. It is the strongest first move and
  // saves a full search on an empty board.
  if (ctx.board.every((c) => c === null)) {
    return { from: null, to: 4 };
  }
  const search = {
    board: ctx.board.slice(),
    toMove: me,
    piecesX: ctx.piecesX,
    piecesO: ctx.piecesO,
  };
  return minimaxMorris(search, me, opp, HARD_DEPTH, -Infinity, Infinity, 0).move;
}

function aiMove(ctx, difficulty, me, opp) {
  if (difficulty === "easy") return aiMoveEasy(ctx);
  if (difficulty === "medium") return aiMoveMedium(ctx, me, opp);
  return aiMoveHard(ctx, me, opp);
}

// ---------- Rendering ----------

function $(sel) {
  return document.querySelector(sel);
}

function buildBoardDom() {
  const boardEl = $("#board");
  boardEl.innerHTML = "";
  for (let i = 0; i < 9; i++) {
    const cell = document.createElement("button");
    cell.className = "cell";
    cell.dataset.index = String(i);
    cell.setAttribute("role", "gridcell");
    cell.setAttribute("aria-label", `Feld ${i + 1}`);
    cell.addEventListener("click", () => onCellClick(i));
    boardEl.appendChild(cell);
  }
}

function cellLocked(i) {
  // Returns true when the cell should not respond to user input.
  if (state.finished) return true;
  if (state.mode !== "local" && state.current === state.aiPlayer) return true;

  if (isPlacementPhase()) {
    return state.board[i] !== null;
  }
  if (state.selected === null) {
    // Movement phase, nothing picked up yet — only own pieces are live.
    return state.board[i] !== state.current;
  }
  // Selection active — empty cells and own pieces (for re-selection) stay live.
  return state.board[i] !== null && state.board[i] !== state.current;
}

function renderBoard() {
  const cells = document.querySelectorAll("#board .cell");
  cells.forEach((node, i) => {
    const mark = state.board[i];
    node.textContent = mark ?? "";
    if (mark) node.dataset.mark = mark;
    else delete node.dataset.mark;
    const isWin = state.winningLine?.includes(i);
    node.classList.toggle("is-winning", !!isWin);
    node.classList.toggle("is-selected", state.selected === i);
    node.classList.toggle("is-disabled", cellLocked(i));
  });

  const turnLabel = $("#turn-label");
  const turnDot = document.querySelector(".turn-dot");
  const phaseLabel = $("#phase-label");
  if (phaseLabel) {
    phaseLabel.textContent = isPlacementPhase() ? "Setzphase" : "Zugphase";
  }

  if (state.finished) {
    turnLabel.textContent = "Runde beendet";
  } else if (state.mode && state.mode !== "local" && state.current === state.aiPlayer) {
    turnLabel.textContent = isPlacementPhase() ? "KI setzt …" : "KI zieht …";
  } else if (state.mode === "local") {
    const verb = isPlacementPhase() ? "setzt" : "zieht";
    turnLabel.textContent = `${state.current} ${verb}`;
  } else if (isPlacementPhase()) {
    turnLabel.textContent = "Du setzt — leeres Feld wählen";
  } else if (state.selected === null) {
    turnLabel.textContent = "Wähle einen deiner Steine";
  } else {
    turnLabel.textContent = "Wohin damit?";
  }
  turnDot.dataset.player = state.current;
}

function showResult(text) {
  $("#result-banner").textContent = text;
}

// ---------- Game flow ----------

function startGame(mode) {
  state.mode = mode;
  state.board = emptyBoard();
  state.current = "X";
  state.finished = false;
  state.winningLine = null;
  state.piecesX = 0;
  state.piecesO = 0;
  state.selected = null;
  // Human is always X (opens placement). Predictable AI loop.
  state.humanPlayer = "X";
  state.aiPlayer = "O";
  $("[data-screen='menu']").classList.remove("is-active");
  $("[data-screen='game']").classList.add("is-active");
  showResult("");
  renderBoard();
}

function newRound() {
  if (!state.mode) return;
  startGame(state.mode);
}

function backToMenu() {
  state.mode = null;
  state.finished = false;
  state.selected = null;
  $("[data-screen='game']").classList.remove("is-active");
  $("[data-screen='menu']").classList.add("is-active");
  renderStats();
}

function onCellClick(index) {
  if (state.finished) return;
  if (state.mode !== "local" && state.current === state.aiPlayer) return;

  if (isPlacementPhase()) {
    if (state.board[index] !== null) return;
    applyMove({ from: null, to: index }, state.current);
    scheduleAiTurn();
    return;
  }

  // Movement phase
  if (state.selected === null) {
    if (state.board[index] !== state.current) return;
    state.selected = index;
    renderBoard();
    return;
  }
  if (index === state.selected) {
    // Tap the already-picked-up piece to drop the selection.
    state.selected = null;
    renderBoard();
    return;
  }
  if (state.board[index] === state.current) {
    // Re-select another own piece without committing the previous one.
    state.selected = index;
    renderBoard();
    return;
  }
  if (state.board[index] !== null) return;

  const move = { from: state.selected, to: index };
  state.selected = null;
  applyMove(move, state.current);
  scheduleAiTurn();
}

function scheduleAiTurn() {
  if (state.finished) return;
  if (state.mode === "local" || state.current !== state.aiPlayer) return;
  // Slight delay so the AI move feels intentional rather than instant.
  setTimeout(() => {
    // Guard against the user restarting / leaving during the delay.
    if (state.finished) return;
    if (!state.mode || state.mode === "local") return;
    if (state.current !== state.aiPlayer) return;
    const difficulty = state.mode.replace("ai-", "");
    const ctx = {
      board: state.board.slice(),
      toMove: state.aiPlayer,
      piecesX: state.piecesX,
      piecesO: state.piecesO,
    };
    const move = aiMove(ctx, difficulty, state.aiPlayer, state.humanPlayer);
    if (move) applyMove(move, state.aiPlayer);
  }, 280);
}

function applyMove(move, mark) {
  doMove(state.board, move, mark);
  if (move.from === null) {
    if (mark === "X") state.piecesX++;
    else state.piecesO++;
  }

  const win = findWinningLine(state.board);
  if (win) {
    state.finished = true;
    state.winningLine = win.line;
    recordWin(win.winner);
    if (state.mode === "local") {
      showResult(`${win.winner} gewinnt!`);
    } else if (win.winner === state.humanPlayer) {
      showResult("Du gewinnst!");
    } else {
      showResult("KI gewinnt.");
    }
    renderBoard();
    return;
  }

  state.current = other(state.current);

  // Movement phase: if the new side-to-move is fully blocked, they
  // lose. Free-movement makes this effectively unreachable but the
  // rule is enforced for completeness.
  if (!isPlacementPhase()) {
    const next = legalMoves(state.board, state.current, state.piecesX, state.piecesO);
    if (next.length === 0) {
      state.finished = true;
      recordWin(mark);
      if (state.mode === "local") {
        showResult(`${mark} gewinnt – Gegner blockiert.`);
      } else if (mark === state.humanPlayer) {
        showResult("Du gewinnst – KI blockiert.");
      } else {
        showResult("KI gewinnt – du bist blockiert.");
      }
      renderBoard();
      return;
    }
  }

  renderBoard();
}

// ---------- Bootstrap ----------

function attachMenuHandlers() {
  document.querySelectorAll(".mode-btn").forEach((btn) => {
    if (btn.classList.contains("is-disabled")) return;
    btn.addEventListener("click", () => {
      const mode = btn.dataset.mode;
      if (!mode) return;
      startGame(mode);
    });
  });
}

function attachGameHandlers() {
  $("#back-to-menu").addEventListener("click", backToMenu);
  $("#restart-btn").addEventListener("click", newRound);
  $("#new-round-btn").addEventListener("click", newRound);
  $("#change-mode-btn").addEventListener("click", backToMenu);
}

function init() {
  buildBoardDom();
  attachMenuHandlers();
  attachGameHandlers();
  renderStats();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
