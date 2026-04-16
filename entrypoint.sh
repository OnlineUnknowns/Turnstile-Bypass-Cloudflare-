#!/bin/bash

declare -r TARGET_USER="root"
#declare -r WORKSPACE="/${TARGET_USER}/Desktop"
declare -r REPO_URL="https://github.com/odell0111/turnstile_solver.git"

start_vnc_server() {
  # Kill any previous previous session
  vncserver -kill "$VNC_DISPLAY" > /dev/null 2>&1

  # Build the base command arguments
  CMD="vncserver $VNC_DISPLAY \
    -httpport $VNC_PORT \
    -geometry $VNC_GEOMETRY \
    -dpi $VNC_DPI \
    -depth $VNC_DEPTH"
  echo "Starting VNC server with command: \"$CMD\""

  # Generate input sequence (password x2 + confirm)
  INPUT_FEED=$(printf "%s\r\n%s\r\n\ry\r\n" "$VNC_PASSWORD" "$VNC_PASSWORD")

  # Execute and capture output
eval "$CMD" <<EOF 2>&1
$INPUT_FEED
EOF
}

start_xrdp() {
    # Clean PIDs
    find /var/run -name '*xrdp*.pid' -delete
    # Update port
    sed -E -i "s/port=[0-9]+/port=${XRDP_PORT}/g" /etc/xrdp/xrdp.ini
    xrdp-sesman & xrdp -n &
}

service_init() {

    if [ "$REMOTE_DESKTOP_PROTOCOL" = "RDP" ]; then
      (start_xrdp && echo "Xrdp running on port: ${XRDP_PORT}") || {
        echo "Xrdp failed to start"
        return 2
      }
    elif [ "$REMOTE_DESKTOP_PROTOCOL" = "VNC" ]; then
      (start_vnc_server && echo "TightVNC server running on port: ${VNC_SERVER_PORT}") || {
        echo "TightVNC server setup failed"
        return 3
      }
    fi

    # Wait up to 20s fot Xorg to start
    local timeout=20

    while ((timeout-- > 0)); do
        pgrep -x Xorg && {
          echo "Xorg started"
          return 0
        }
        sleep 1
    done
    echo "Xorg not started after 20s"
    return 1
}

user_setup() {
    if ! id "${TARGET_USER}" &>/dev/null; then
        getent group "${TARGET_USER}" || groupadd "${TARGET_USER}"
        useradd -mUs "/bin/bash" -G "${TARGET_USER},sudo" "${TARGET_USER}" || return 1
    fi
    echo "${TARGET_USER}:${TARGET_USER}" | chpasswd || return 1
}

env_config() {
    [[ -n "${TZ}" ]] && {
        ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
        echo "${TZ}" >/etc/timezone
    }
#    mkdir -p "${WORKSPACE}"
}

repo_setup() {
#    ( cd "${WORKSPACE}" && git clone -q "${REPO_URL}" && cd turnstile_solver || exit 2
#    pip3 install -r requirements.txt --break-system-packages )
    pip3 install "git+${REPO_URL}@main" --no-cache-dir --break-system-packages || {
      echo "Repo setup failed"
      return 2
    }
    echo "repo set-up done"
}

install_patchright() {
  # Install patchright (with PEP 668 workaround)
  pip3 install --no-cache-dir --break-system-packages patchright || {
      echo "Failed to install patchright"
      return 3
  }

  # Install browser
#  patchright install --force "$SOLVER_BROWSER" || {
#      echo "Failed to install Patchright browser: $SOLVER_BROWSER"
#      return 4
#  }
  echo "Patchright installed"
}

# Execution flow
user_setup || { echo "User config failed"; exit 1; }
env_config || exit 2
repo_setup || exit 3
install_patchright || exit 4
service_init || exit 6

if [ "$START_SERVER" = "true" ]; then
  echo "Starting server in headful mode..."
  xvfb-run -a python3 solver --browser "${SOLVER_BROWSER}" --port "${SOLVER_SERVER_PORT}"
#  xvfb-run -a python3 "${WORKSPACE}/turnstile_solver/main.py"
fi
