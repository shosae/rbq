#!/bin/bash

IFACE_ARGS=()
ROBOT_ARGS=()
SIM_ARGS=()
MOTION_ENABLED=true
SIM_ENABLED=true
VISION_ENABLED=false
SLAM_ENABLED=false
RVIZ_ENABLED=false
GUI_ENABLED=true
USE_TMUX=false

print_help() {
    echo "Usage: bash scripts/sim.bash [OPTIONS]"
    echo "Options:"
    echo "  --help                  Display this help message and exit."
    echo "  -i, --interface <name>  CycloneDDS network interface. DEFAULT lo"
    echo "  -r, --robot <flag>      Robot variant flag: --rb1 | --wheel | --lims_ex (per README; passed through to start_motion)"
    echo "  --no-motion             Skip the Motion."
    echo "  --no-sim                Skip the Mujoco simulator."
    echo "  --vision                Run vision modules."
    echo "  --slam                  Run SLAM."
    echo "  --rviz                  Run Rviz."
    echo "  --no-gui                Skip the GUI."
    echo "  --tmux                  Run everything in a single tmux window instead of gnome-terminal tabs."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help) print_help; exit 0 ;;
        -i|--interface) IFACE_ARGS=("--interface" "$2"); shift 2 ;;
        -r|--robot)     ROBOT_ARGS=("--$2"); shift 2 ;;
        --no-motion)    MOTION_ENABLED=false; shift ;;
        --no-sim)       SIM_ENABLED=false; shift ;;
        --vision)       VISION_ENABLED=true; SIM_ARGS=("--vision"); shift ;;
        --slam)         SLAM_ENABLED=true; shift ;;
        --rviz)         RVIZ_ENABLED=true; shift ;;
        --no-gui)       GUI_ENABLED=false; shift ;;
        --tmux)         USE_TMUX=true; shift ;;
        *) echo "Unknown argument: $1"; print_help; exit 1 ;;
    esac
done

SESSION="rbq_sim"
TITLES=()
CMDS=()

# add_app <title> <script> [args...]
add_app() {
    local title="$1"; shift
    TITLES+=("$title")
    CMDS+=("$(printf '%q ' bash "$@")")
}

if [ "$MOTION_ENABLED" = "true" ]; then
    add_app "Motion"   scripts/start_motion.bash --sim "${IFACE_ARGS[@]}" "${ROBOT_ARGS[@]}"
fi
if [ "$SIM_ENABLED" = "true" ]; then
    add_app "Mujoco"   scripts/start_mujoco.bash "${IFACE_ARGS[@]}" "${SIM_ARGS[@]}" "${ROBOT_ARGS[@]}"
fi
if [ "$VISION_ENABLED" = "true" ]; then
    add_app "mediamtx" scripts/start_mediamtx.bash
    add_app "Vision"   scripts/start_vision.bash --sim "${IFACE_ARGS[@]}"
fi
if [ "$SLAM_ENABLED" = "true" ]; then
    add_app "SLAM"     scripts/start_slam.bash "${IFACE_ARGS[@]}"
fi
if [ "$RVIZ_ENABLED" = "true" ]; then
    add_app "RBQ Rviz" scripts/start_rviz.bash "${IFACE_ARGS[@]}" "${ROBOT_ARGS[@]}"
fi
if [ "$GUI_ENABLED" = "true" ]; then
    add_app "RBQ GUI"  scripts/start_gui.bash --sim "${ROBOT_ARGS[@]}"
fi

if [ ${#CMDS[@]} -eq 0 ]; then
    echo "Nothing to run."
    exit 0
fi

if [ "$USE_TMUX" = "true" ] && ! command -v tmux > /dev/null; then
    echo "tmux not found. Install it first: sudo apt install tmux"
    exit 1
fi

if [ "$USE_TMUX" = "true" ]; then
    if tmux has-session -t "$SESSION" 2> /dev/null; then
        echo "tmux session '$SESSION' already exists. Run 'bash scripts/stop_sim.bash' first."
        exit 1
    fi

    # All apps as panes of a single tmux window.
    tmux new-session -d -s "$SESSION" -n sim -c "$PWD" "bash -i -c ${CMDS[0]@Q}"
    tmux select-pane -t "$SESSION" -T "${TITLES[0]}"
    for ((i = 1; i < ${#CMDS[@]}; i++)); do
        tmux split-window -t "$SESSION" -c "$PWD" "bash -i -c ${CMDS[$i]@Q}"
        tmux select-pane -t "$SESSION" -T "${TITLES[$i]}"
        tmux select-layout -t "$SESSION" tiled > /dev/null
    done
    tmux set-option -t "$SESSION" mouse on > /dev/null
    tmux set-option -t "$SESSION" pane-border-status top > /dev/null
    tmux set-option -t "$SESSION" pane-border-format " #{pane_index}: #{pane_title} " > /dev/null
    # Keep pane titles fixed; the start scripts set the terminal title themselves.
    tmux set-option -t "$SESSION" allow-rename off > /dev/null
    tmux select-pane -t "$SESSION:sim.0"

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$SESSION"
    elif [ -t 1 ]; then
        tmux attach-session -t "$SESSION"
    else
        gnome-terminal --title="RBQ Sim" -- tmux attach-session -t "$SESSION"
    fi
else
    for ((i = 0; i < ${#CMDS[@]}; i++)); do
        gnome-terminal --tab --title="${TITLES[$i]}" -- bash -i -c "${CMDS[$i]}"
    done
fi
