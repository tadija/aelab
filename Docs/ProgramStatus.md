# Terminal program status

The browser terminal supports [OSC 7501, Program Status Protocol revision 0.4](https://www.superlogical.com/rex/docs/build/program-status). Programs can report work, progress, a request for input, completion or failure through their terminal output.

aelab shows the most actionable report in the browser tab title, for example `[approval needed] Codex@my-project`, and beside the title on its pinned dashboard card. Pin numbers sit before the card title. Hover a status badge to read its message. Approval requests take priority over failures, active work, completion and idle reports. Working reports use a yellow badge. Connection status remains separate; the tty page adds no status footer.

To try it in an aelab shell:

```sh
printf '\033]7501;state=working:app=demo:progress=40\033\\'
printf '\033]7501;state=blocked:app=demo:kind=permission:msg=QXBwcm92ZT8=\033\\'
printf '\033]7501;state=done:app=demo\033\\'
printf '\033]7501;state=clear\033\\'
```

The second report shows an approval-needed badge, with “Approve?” in its tooltip. If your shell emits prompt integration, active work/input requests clear when the next prompt appears; emit reports from inside a running program to keep them visible while it works. Completion and failure reports remain until the next terminal keypress. Full terminal reset clears everything.

Programs that query support receive a capability reply automatically. Reports must reach aelab’s PTY stream: SSH and daemon terminals carry their output normally, but a multiplexer such as tmux may filter unknown sequences. aelab does not change multiplexer settings or infer status from screen text.

The server tracks validated reports while the PTY is alive, including when a pinned terminal has no open browser tab. Dashboard cards refresh through the existing authorized pin list; tab updates can trigger an earlier refresh. Status is memory-only and disappears with the terminal. Replayed queries never generate new input. Opening a terminal tab reconstructs its title from the bounded replay, so older reports may be absent from the tab while still appearing on its card.
