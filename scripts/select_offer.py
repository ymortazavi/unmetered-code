#!/usr/bin/env python3
"""
Interactive GPU offer selector using curses. Arrow keys to move, Enter to select.
Reads offer data from stdin (header line, then "ID\tdisplay_line" per row).
Writes selected OFFER_ID to the file path given as first argument.
Exits 0 on success. If stdin is not a TTY, writes first offer and exits.
"""
import sys


def main() -> None:
    outfile = sys.argv[1] if len(sys.argv) > 1 else None
    if not outfile:
        sys.stderr.write("Usage: select_offer.py <outfile>\n")
        sys.exit(1)

    lines_in = sys.stdin.read().splitlines()
    if not lines_in:
        sys.stderr.write("No input\n")
        sys.exit(1)

    header = lines_in[0]
    offers = []  # (offer_id, display_line)
    for line in lines_in[1:]:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split("\t", 1)
        if len(parts) >= 1 and parts[0].strip().isdigit():
            offer_id = parts[0].strip()
            display = parts[1].strip() if len(parts) > 1 else line
            offers.append((offer_id, display))

    if not offers:
        sys.stderr.write("No offer rows\n")
        sys.exit(1)

    # Non-interactive: write first and exit
    if not sys.stdout.isatty():
        with open(outfile, "w") as f:
            f.write(offers[0][0] + "\n")
        sys.exit(0)

    try:
        import curses
    except ImportError:
        with open(outfile, "w") as f:
            f.write(offers[0][0] + "\n")
        sys.exit(0)

    def run(scr) -> str:
        curses.curs_set(0)
        scr.keypad(True)
        scr.timeout(100)
        selected = [0]
        max_visible = curses.LINES - 4
        if max_visible < 1:
            max_visible = 1
        offset = [0]  # scroll offset

        def draw():
            scr.clear()
            h, w = scr.getmaxyx()
            scr.addstr(0, 0, header[: w - 1], curses.A_BOLD)
            scr.addstr(1, 0, " ↑/↓ select  Enter confirm "[: w - 1], curses.A_DIM)
            start = offset[0]
            end = min(start + max_visible, len(offers))
            for i in range(start, end):
                row_idx = i - start + 2
                oid, disp = offers[i]
                disp_short = (disp[: w - 4] + "..") if len(disp) > w - 2 else disp
                if i == selected[0]:
                    scr.addstr(row_idx, 0, disp_short[: w - 1], curses.A_REVERSE)
                else:
                    scr.addstr(row_idx, 0, disp_short[: w - 1])
            scr.refresh()

        while True:
            draw()
            try:
                key = scr.getch()
            except (KeyboardInterrupt, curses.error):
                continue
            if key in (curses.KEY_UP, ord("k")):
                selected[0] = max(0, selected[0] - 1)
                if selected[0] < offset[0]:
                    offset[0] = selected[0]
            elif key in (curses.KEY_DOWN, ord("j")):
                selected[0] = min(len(offers) - 1, selected[0] + 1)
                if selected[0] >= offset[0] + max_visible:
                    offset[0] = selected[0] - max_visible + 1
            elif key in (ord("\n"), ord("\r"), ord(" ")):
                break
            elif key == ord("q"):
                selected[0] = 0
                break
        return offers[selected[0]][0]

    try:
        selected_id = curses.wrapper(run)
    except Exception:
        selected_id = offers[0][0]

    with open(outfile, "w") as f:
        f.write(selected_id + "\n")


if __name__ == "__main__":
    main()
