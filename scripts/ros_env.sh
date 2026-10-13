#!/usr/bin/env bash
# =============================================================================
# ros_env.sh — carrega o ROS, o underlay e o install/ do workspace.
# =============================================================================
#
#   source scripts/ros_env.sh
#
# ROS_DISTRO e EVTOL_UNDERLAY vêm da imagem do devcontainer.
# =============================================================================

# shellcheck shell=bash

_evtol_ros_env() {
    local ws_root had_u=0

    ws_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Os setup.bash do ROS leem variáveis que podem não existir, e quem nos
    # chama costuma estar com `set -u`.
    [[ $- == *u* ]] && had_u=1
    set +u

    # shellcheck disable=SC1090
    source "/opt/ros/$ROS_DISTRO/setup.bash"
    # shellcheck disable=SC1091
    source "$EVTOL_UNDERLAY/setup.bash"

    if [[ -f "$ws_root/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "$ws_root/install/setup.bash"
    fi

    (( had_u )) && set -u

    return 0
}

_evtol_ros_env
