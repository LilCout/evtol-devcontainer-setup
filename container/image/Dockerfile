# Pinned by digest: to move to a newer base, look up the new tag's digest on Docker Hub
FROM docker.io/px4io/px4-dev-simulation-jammy@sha256:3b1bbb3c7b86150bdd916a22e3c2faa9276555bc9e89d2bd73ef53cf039f506a AS base

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ROS_DISTRO=humble

# Keep downloaded .debs, so the apt cache mounts below have something to reuse
RUN rm -f /etc/apt/apt.conf.d/docker-clean

# Build caches (RUN --mount=type=cache) stay on the host between builds and never
# enter the image. `podman system prune` / `buildah prune` clear them.

# Micro XRCE-DDS Agent, built in its own stage and copied to /usr/local/.
FROM base AS xrce
ARG XRCE_AGENT_VERSION=v2.4.3
ARG XRCE_BUILD_JOBS=4
RUN --mount=type=cache,id=evtol-build-ccache,target=/root/.ccache \
    git clone --depth 1 --branch "${XRCE_AGENT_VERSION}" \
        https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /tmp/agent \
    && cmake -S /tmp/agent -B /tmp/agent/build \
    && CCACHE_DIR=/root/.ccache cmake --build /tmp/agent/build --parallel "${XRCE_BUILD_JOBS}" \
    && DESTDIR=/out cmake --install /tmp/agent/build \
    && test -x /out/usr/local/bin/MicroXRCEAgent

# PX4 SITL, prebuilt at its final path (the build records absolute paths).
# Doesn't need ROS: changes to the main stage don't rebuild it.
# Shallow clone; skips the NuttX submodules (only for flight-controller builds;
# a shallow NuttX checkout breaks PX4's version script) and ModalAI's VOXL2 one.
FROM base AS px4
ARG PX4_REF=v1.15.4
ARG PX4_BUILD_JOBS=4
RUN --mount=type=cache,id=evtol-build-ccache,target=/root/.ccache \
    git clone --depth 1 --branch "${PX4_REF}" \
        https://github.com/PX4/PX4-Autopilot.git /opt/PX4-Autopilot \
    && git -C /opt/PX4-Autopilot \
        -c submodule.platforms/nuttx/NuttX/nuttx.update=none \
        -c submodule.platforms/nuttx/NuttX/apps.update=none \
        -c submodule.boards/modalai/voxl2/libfc-sensor-api.update=none \
        submodule update --init --recursive --depth 1 --jobs 8 \
    && cd /opt/PX4-Autopilot \
    && CCACHE_DIR=/root/.ccache make px4_sitl_default j="${PX4_BUILD_JOBS}" \
    && test -e build/px4_sitl_default/bin/px4-gz_bridge \
    && chmod -R a+rwX /opt/PX4-Autopilot

# Main image. Layers go from least to most likely to change.
FROM base

# ROS 2 Humble Desktop
ARG ROS_APT_SOURCE_VERSION=1.2.0
RUN --mount=type=cache,id=evtol-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=evtol-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends curl software-properties-common \
    && add-apt-repository -y universe \
    && curl -fsSL -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.jammy_all.deb" \
    && apt-get install -y --no-install-recommends /tmp/ros2-apt-source.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends ros-humble-desktop ros-dev-tools sudo \
    && rm /tmp/ros2-apt-source.deb

RUN rosdep init \
    && su user -c 'rosdep update --rosdistro humble'

# Non-root user: the dev container runs as the base image's `user` (uid 1001).
# On Linux the Dev Containers CLI changes its uid/gid to yours when it creates
# the container (updateRemoteUserUID), so files made in the workspace belong to
# you, with Docker too; with rootless Podman it also adds --userns=keep-id.
#   - passwordless sudo, for apt-get and `rosdep install`
#   - safe.directory: the checkouts in /opt belong to root, and the user's uid is
#     only known when the container is created; without it git (and so PX4's
#     build) refuses to work in them
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
    && chmod 0440 /etc/sudoers.d/user \
    && git config --system --add safe.directory '*'

COPY --from=xrce /out/usr/local/ /usr/local/
RUN ldconfig /usr/local/lib/
COPY --from=px4 /opt/PX4-Autopilot /opt/PX4-Autopilot

# ROS <-> Gazebo Garden bridge
RUN --mount=type=cache,id=evtol-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=evtol-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ros-humble-ros-gzgarden-image ros-humble-ros-gzgarden-bridge \
        ros-humble-ros-gzgarden-sim ros-humble-ros-gzgarden-interfaces \
        ros-humble-vision-msgs ros-humble-cv-bridge

# Python packages
RUN --mount=type=cache,id=evtol-pip,target=/root/.cache/pip \
    python3 -m pip install -U \
        empy==3.3.4 pyros-genmsg 'setuptools<80' 'packaging>=23' \
        'numpy>=1.24,<2' opencv-contrib-python==4.11.0.86 mediapipe==0.10.18 \
    && python3 -c "import cv2, numpy, mediapipe; assert numpy.__version__.startswith('1.'), numpy.__version__; print('cv2', cv2.__version__, 'numpy', numpy.__version__)"

# Underlay: the workspace's third-party ROS 2 packages (BehaviorTree.CPP,
# px4_msgs, px4-ros2-interface-lib), prebuilt in /opt/evtol_deps.
# Requires source /opt/evtol_deps/setup.bash
ARG DEPS_BUILD_JOBS=4
COPY deps.repos /opt/evtol_deps/deps.repos
RUN --mount=type=cache,id=evtol-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=evtol-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=evtol-build-ccache,target=/root/.ccache \
    mkdir -p /tmp/deps/src \
    && vcs import /tmp/deps/src < /opt/evtol_deps/deps.repos \
    && apt-get update \
    && rosdep update --rosdistro humble \
    && rosdep install --from-paths /tmp/deps/src --ignore-src -y --rosdistro humble \
    && rm -rf /root/.ros \
    && cd /tmp/deps \
    && . /opt/ros/humble/setup.sh \
    && CCACHE_DIR=/root/.ccache MAKEFLAGS="-j${DEPS_BUILD_JOBS}" colcon build \
        --merge-install --install-base /opt/evtol_deps --executor sequential \
    && test -f /opt/evtol_deps/setup.bash \
    && rm -rf /tmp/deps
ENV EVTOL_UNDERLAY=/opt/evtol_deps

# Folders for the named volumes in devcontainer.json, owned by `user`: a new
# volume takes their ownership, so it needs no chown.
RUN ln -s /opt/PX4-Autopilot /home/user/PX4-Autopilot \
    && mkdir -p /home/user/.ccache /home/user/.gz/fuel /home/user/.ros \
        /home/user/evtol/mission_logs \
    && chown -R user:user /home/user
