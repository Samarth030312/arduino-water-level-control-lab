# Sourced by the scripts in scripts/setup and scripts/validation (bash, Linux and macOS).
# Same folders as levellab.tools.paths in MATLAB; LEVELLAB_TOOLS overrides the default.
#   LEVELLAB_ROOT   repository root
#   LEVELLAB_CLI    arduino-cli executable of this project
# and exports the ARDUINO_DIRECTORIES_* variables, so arduino-cli and the Arduino IDE
# use this project's own cores and libraries (the global ~/.arduino15 is never touched).
LEVELLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${LEVELLAB_TOOLS:-}" ]; then
  case "$(uname -s)" in
    Darwin) LEVELLAB_TOOLS="$HOME/Library/Application Support/arduino-lab-tools" ;;
    *) LEVELLAB_TOOLS="$HOME/.local/share/arduino-lab-tools" ;;
  esac
fi
LEVELLAB_CLI="$LEVELLAB_TOOLS/arduino-cli/arduino-cli"
export ARDUINO_DIRECTORIES_DATA="$LEVELLAB_TOOLS/arduino/data"
export ARDUINO_DIRECTORIES_DOWNLOADS="$LEVELLAB_TOOLS/arduino/downloads"
export ARDUINO_DIRECTORIES_USER="$LEVELLAB_TOOLS/arduino/user"
export ARDUINO_UPDATER_ENABLE_NOTIFICATION=false
