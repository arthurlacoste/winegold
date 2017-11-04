#!/bin/sh
osascript -e '
on run {cmd}
  tell application "Terminal"
    activate
    to do script(cmd)
  end tell
end run'
