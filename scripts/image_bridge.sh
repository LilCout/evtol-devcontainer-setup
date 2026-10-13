#!/bin/bash
# ==========================================================
# image_bridge.sh — Generic
# Bridges Gazebo camera images to ROS2 topics.
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/ros_env.sh
source "$WORKSPACE_DIR/scripts/ros_env.sh"

echo "Starting ros_gz_image bridge (vertical_camera & horizontal_camera → ROS2)"
ros2 run ros_gz_image image_bridge /vertical_camera /horizontal_camera --ros-args -p transport:=compressed
