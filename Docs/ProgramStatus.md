# Terminal program status

The browser terminal supports [OSC 7501, Program Status Protocol revision 0.4](https://www.superlogical.com/rex/docs/build/program-status). Programs can report work, progress, a request for input, completion or failure through their terminal output.

aelab shows the most actionable report at the bottom of the terminal page and in its browser tab title, for example `[approval needed] Codex@aelab`. Expand the status strip to see all reports. Approval requests take priority over failures, active work, completion and idle reports. Connection status remains separate. The strip stays visible when the terminal header is collapsed.

To try it in an aelab shell:

```sh
printf '\033]7501;state=working:app=demo:progress=40\033\\'
printf '\033]7501;state=blocked:app=demo:kind=permission:msg=QXBwcm92ZT8=\033\\'
printf '\033]7501;state=done:app=demo\033\\'
printf '\033]7501;state=clear\033\\'
```

The second report displays “approval needed · demo · Approve?”. If your shell emits prompt integration, active work/input requests clear when the next prompt appears; emit reports from inside a running program to keep them visible while it works. Completion and failure reports remain until the next terminal keypress. Full terminal reset clears everything.

Programs that query support receive a capability reply automatically. Reports must reach the browser: SSH and daemon terminals carry their output normally, but a multiplexer such as tmux may filter unknown sequences. aelab does not change multiplexer settings or infer status from screen text.

Status is local to each open terminal page; it is not collected in the dashboard or saved on the server. Pinned reconnects reconstruct it from the bounded terminal replay, so reports older than that replay may be unavailable. Replayed queries never generate new input.
