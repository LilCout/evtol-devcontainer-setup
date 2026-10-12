# Dev container for the eVTOL ITA workspace (evtol-dev), matching its
# env/desktop-humble.yaml profile: Ubuntu 22.04, ROS 2 Humble Desktop,
# Gazebo Garden + the Garden ROS bridge, PX4 v1.15.4 SITL (prebuilt in
# /opt/PX4-Autopilot, linked at ~/PX4-Autopilot) and Micro XRCE-DDS Agent v2.4.3.
# The base image is PX4's own (PX4-containers, Dockerfile_simulation-jammy) and
# already contains gz-garden and every PX4 build dependency.
# Pinned by digest: a tag can be re-pushed, a digest can't. This is the tag
# 2024-05-18 (amd64, the only platform it ships). To move to a newer base, look up
# the new tag's digest on Docker Hub or with:
#   skopeo inspect docker://docker.io/px4io/px4-dev-simulation-jammy:<tag> | grep Digest
FROM docker.io/px4io/px4-dev-simulation-jammy@sha256:3b1bbb3c7b86150bdd916a22e3c2faa9276555bc9e89d2bd73ef53cf039f506a

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ROS_DISTRO=humble

# ROS 2 Humble Desktop, following the official "Ubuntu (deb packages)" guide:
#   - locale: UTF-8 (set via LANG/LC_ALL above)
#   - Ubuntu universe: already enabled in the Ubuntu base image
#   - ros2-apt-source package (version pinned for reproducible builds)
#   - ros-humble-desktop (ROS, RViz, demos, tutorials) + ros-dev-tools
#   - sudo (the container runs as `user`) and python3-venv, which evtol-dev's
#     scripts/venv.sh needs and the pinned base image doesn't have
#   - no `apt-get upgrade`: it would pull whatever Ubuntu shipped on the day
#     of the build into every base-image package; only what is listed here
#     (and its dependencies) is installed or updated
ARG ROS_APT_SOURCE_VERSION=1.2.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl software-properties-common \
    && add-apt-repository -y universe \
    && curl -fsSL -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.jammy_all.deb" \
    && apt-get install -y --no-install-recommends /tmp/ros2-apt-source.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends ros-humble-desktop ros-dev-tools sudo python3-venv \
    && rm -rf /var/lib/apt/lists/* /tmp/ros2-apt-source.deb

# Pinned Python packages for ROS 2 / PX4 builds, and rosdep set up once.
# (git, cmake, colcon, vcstool and rosdep already come from ros-dev-tools above.)
#   empy 3.3.4: the version both ROS 2 Humble and PX4 1.15 code generation need
#   setuptools<80: newer versions break colcon builds of Python packages on Humble
RUN python3 -m pip install --no-cache-dir -U \
        empy==3.3.4 pyros-genmsg 'setuptools<80' 'packaging>=23' \
    && rosdep init \
    && su user -c 'rosdep update --rosdistro humble'

# Non-root user: the dev container runs as the base image's `user` (uid 1001).
# On Linux the Dev Containers CLI changes its uid/gid to yours when it creates
# the container (updateRemoteUserUID), so files made in the workspace belong to
# you, with Docker too; with rootless Podman it also adds --userns=keep-id.
#   - passwordless sudo, for apt-get and `rosdep install`
#   - safe.directory: the checkouts in /opt belong to root, and the user's uid is
#     only known when the container is created; without it git (and so PX4's
#     build and the evtol doctor) refuses to work in them
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
    && chmod 0440 /etc/sudoers.d/user \
    && git config --system --add safe.directory '*'

# Micro XRCE-DDS Agent v2.4.3, the version PX4's uXRCE-DDS docs pair with PX4
# 1.15 and ROS 2 Humble (latest 2.x release).
# NOTE: evtol-dev's env/desktop-humble.yaml still pins v3.0.1 (what the team's
# machines fly with), so its doctor reports a version mismatch for
# ~/Micro-XRCE-DDS-Agent until the profile is changed too. To build the
# profile's version instead: --build-arg XRCE_AGENT_VERSION=v3.0.1
# The source checkout is linked at ~/Micro-XRCE-DDS-Agent (below) because the
# profile's doctor checks `git describe` there; installs to /usr/local/bin as it expects.
ARG XRCE_AGENT_VERSION=v2.4.3
RUN git clone --depth 1 --branch "${XRCE_AGENT_VERSION}" \
        https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /opt/Micro-XRCE-DDS-Agent \
    && cmake -S /opt/Micro-XRCE-DDS-Agent -B /opt/Micro-XRCE-DDS-Agent/build \
    && cmake --build /opt/Micro-XRCE-DDS-Agent/build --parallel 4 \
    && cmake --install /opt/Micro-XRCE-DDS-Agent/build \
    && ldconfig /usr/local/lib/ \
    && rm -rf /opt/Micro-XRCE-DDS-Agent/build

# ROS <-> Gazebo Garden bridge, as the desktop-humble profile requires: the
# GARDEN builds (ros-humble-ros-gzgarden-*, from the OSRF Gazebo repo the base
# image already configures). The unsuffixed ros-humble-ros-gz-* packages are
# Fortress builds and are on the profile's forbidden list: they install and run
# but never see a Gazebo topic. Also the profile's vision_msgs and cv_bridge.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ros-humble-ros-gzgarden-image ros-humble-ros-gzgarden-bridge \
        ros-humble-ros-gzgarden-sim ros-humble-ros-gzgarden-interfaces \
        ros-humble-vision-msgs ros-humble-cv-bridge \
    && rm -rf /var/lib/apt/lists/*

# PX4 SITL, prebuilt at its final path (the build records absolute paths).
# Shallow clone; skips the NuttX submodules (only for flight-controller builds;
# a shallow NuttX checkout breaks PX4's version script) and ModalAI's VOXL2 one.
ARG PX4_REF=v1.15.4
ARG PX4_BUILD_JOBS=4
RUN git clone --depth 1 --branch "${PX4_REF}" \
        https://github.com/PX4/PX4-Autopilot.git /opt/PX4-Autopilot \
    && git -C /opt/PX4-Autopilot \
        -c submodule.platforms/nuttx/NuttX/nuttx.update=none \
        -c submodule.platforms/nuttx/NuttX/apps.update=none \
        -c submodule.boards/modalai/voxl2/libfc-sensor-api.update=none \
        submodule update --init --recursive --depth 1 --jobs 8 \
    && cd /opt/PX4-Autopilot \
    && CCACHE_DISABLE=1 make px4_sitl_default j="${PX4_BUILD_JOBS}" \
    && test -e build/px4_sitl_default/bin/px4-gz_bridge \
    && chmod -R a+rwX /opt/PX4-Autopilot

# The cache folders (named volumes in devcontainer.json) are created here and
# owned by `user`, so a new volume mounted on one starts out owned by `user` too.
RUN ln -s /opt/PX4-Autopilot /home/user/PX4-Autopilot \
    && ln -s /opt/Micro-XRCE-DDS-Agent /home/user/Micro-XRCE-DDS-Agent \
    && mkdir -p /home/user/.ccache /home/user/.gz/fuel /home/user/.ros \
    && chown -R user:user /home/user

# evtol-dev's scripts and doctor look for PX4 at ~/PX4-Autopilot and the Agent
# at ~/Micro-XRCE-DDS-Agent (~ = /home/user; linked above, so the builds keep
# their real /opt paths) and the team's models at ~/PX4-gazebo-models
# (bind-mounted from your computer by devcontainer.json).
