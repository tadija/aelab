import Foundation

/// Optional user-service setup for a native daemon installation.
public enum DaemonUserService {
    private static let publish = """
    if test -e "$p" || test -L "$p"; then
        if test -L "$p" || ! test -f "$p" || ! cmp -s "$temporary" "$p"; then
            printf '%s\\n' 'Refusing to replace an unrelated daemon user service' >&2
            exit 1
        fi
    else
        ln "$temporary" "$p"
    fi
    """
    public static func script(macos: Bool) -> String {
        if macos {
            return """
            set -eu
            p="$HOME/Library/LaunchAgents/dev.aelab.daemon.plist"
            mkdir -p "$HOME/Library/LaunchAgents"
            daemon_home=${1:-"$HOME/.aelab/daemon"}
            temporary=$(mktemp "$p.XXXXXX")
            trap 'rm -f "$temporary"' EXIT HUP INT TERM
            chmod 600 "$temporary"
            # XML escaping handles home directory characters without shell interpolation into XML.
            escaped=$(printf '%s' "$daemon_home" | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g; s/"/\\&quot;/g')
            umask 077
            printf '%s' '<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>dev.aelab.daemon</string><key>ProgramArguments</key><array><string>'"$escaped"'/aelab-daemon</string><string>--home</string><string>'"$escaped"'</string><string>run</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>Umask</key><integer>63</integer><key>StandardErrorPath</key><string>'"$escaped"'/stderr.log</string><key>StandardOutPath</key><string>'"$escaped"'/stdout.log</string></dict></plist>' > "$temporary"
            \(publish)
            if ! launchctl print "gui/$(id -u)/dev.aelab.daemon" >/dev/null 2>&1; then launchctl bootstrap "gui/$(id -u)" "$p"; fi
            """
        }
        return """
        set -eu
        p="$HOME/.config/systemd/user/aelab-daemon.service"
        mkdir -p "$HOME/.config/systemd/user"
        umask 077
        daemon_home=${1:-"$HOME/.aelab/daemon"}
        temporary=$(mktemp "$p.XXXXXX")
        trap 'rm -f "$temporary"' EXIT HUP INT TERM
        chmod 600 "$temporary"
        # Escape systemd specifiers, variables, quotes and backslashes in literal paths.
        escaped=$(printf '%s' "$daemon_home" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/%/%%/g; s/\\$/$$/g')
        printf '%s\\n' '[Unit]' 'Description=aelab daemon' '[Service]' 'ExecStart="'"$escaped"'/aelab-daemon" --home "'"$escaped"'" run' 'Restart=on-failure' 'RestartSec=3' 'UMask=0077' '[Install]' 'WantedBy=default.target' > "$temporary"
        \(publish)
        systemctl --user daemon-reload
        systemctl --user enable --now aelab-daemon.service
        """
    }
}
