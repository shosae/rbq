#!/bin/bash

# Stops everything launched by scripts/sim.bash.
# The start_*.bash wrappers restart their app in a loop, so the wrappers are killed first,
# then the apps (SIGINT -> SIGTERM -> SIGKILL).

WRAPPERS=(
    "scripts/start_motion.bash"
    "scripts/start_mujoco.bash"
    "scripts/start_mediamtx.bash"
    "scripts/start_vision.bash"
    "scripts/start_slam.bash"
    "scripts/start_rviz.bash"
    "scripts/start_gui.bash"
)

# Apps started by the wrappers, plus the modules Motion spawns from bin/.
APPS=(
    "GUI" "Vision" "SLAMNAV_3D" "mediamtx" "Mujoco" "Motion"
    "Network" "HAL" "QuadWalk" "RLWalk" "WalkReady" "ManiControl"
    "Heightmap" "Cctv" "Ptz" "Thermal" "Streamer" "Handeye"
)

ROS_PATTERNS=(
    "ros2 launch rbq_description"
    "rviz2"
    "robot_state_publisher"
    "joint_state_publisher"
)

print_help() {
    echo "Usage: bash scripts/stop_sim.bash [OPTIONS]"
    echo "Options:"
    echo "  --help    Display this help message and exit."
    echo "  -t <sec>  Seconds to wait for graceful shutdown before SIGKILL. DEFAULT 5"
}

TIMEOUT=5
while [[ $# -gt 0 ]]; do
    case $1 in
        --help) print_help; exit 0 ;;
        -t) TIMEOUT="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

# Motion and Mujoco run as root, so get sudo credentials up front.
sudo -v || { echo "sudo is required to stop root processes."; exit 1; }

collect_pids() {
    local pids=()
    for w in "${WRAPPERS[@]}"; do pids+=($(pgrep -f "bash $w")); done
    echo "${pids[@]}"
}

collect_app_pids() {
    local pids=()
    for a in "${APPS[@]}"; do pids+=($(pgrep -x "$a")); done
    for p in "${ROS_PATTERNS[@]}"; do pids+=($(pgrep -f "$p")); done
    echo "${pids[@]}"
}

# 1. Stop the restart loops.
WRAPPER_PIDS=$(collect_pids)
if [ -n "$WRAPPER_PIDS" ]; then
    echo "Stopping wrappers: $WRAPPER_PIDS"
    sudo kill -TERM $WRAPPER_PIDS 2>/dev/null
fi

# 2. Stop the apps gracefully, escalating if needed.
APP_PIDS=$(collect_app_pids)
if [ -z "$APP_PIDS" ]; then
    tmux kill-session -t rbq_sim 2>/dev/null
    echo "No sim processes running."
    exit 0
fi

echo "Stopping apps: $APP_PIDS"
sudo kill -INT $APP_PIDS 2>/dev/null

for sig in TERM KILL; do
    for ((i = 0; i < TIMEOUT * 2; i++)); do
        APP_PIDS=$(collect_app_pids)
        [ -z "$APP_PIDS" ] && break 2
        sleep 0.5
    done
    echo "Still running ($APP_PIDS), sending SIG$sig"
    sudo kill -$sig $APP_PIDS 2>/dev/null
done

# Wrappers may have been blocked on a foreground app; make sure they are gone too.
WRAPPER_PIDS=$(collect_pids)
[ -n "$WRAPPER_PIDS" ] && sudo kill -KILL $WRAPPER_PIDS 2>/dev/null

tmux kill-session -t rbq_sim 2>/dev/null

echo "All sim processes stopped."
