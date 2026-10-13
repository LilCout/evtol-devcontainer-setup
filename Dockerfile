# Dev container for the eVTOL ITA workspace (evtol-dev). This file IS the
# workspace's environment (it replaced the env/ profiles and the doctor):
# Ubuntu 22.04, ROS 2 Humble Desktop, Gazebo Garden + the Garden ROS bridge,
# PX4 v1.15.4 SITL (prebuilt in /opt/PX4-Autopilot, linked at ~/PX4-Autopilot),
# Micro XRCE-DDS Agent v2.4.3, the pinned pip packages, and the third-party ROS
# packages prebuilt in /opt/evtol_deps. Each pin says why, next to its line.
# The base image is PX4's own (PX4-containers, Dockerfile_simulation-jammy) and
# already contains gz-garden and every PX4 build dependency.
# Pinned by digest: a tag can be re-pushed, a digest can't. This is the tag
# 2024-05-18 (amd64, the only platform it ships). To move to a newer base, look up
# the new tag's digest on Docker Hub or with:
#   skopeo inspect docker://docker.io/px4io/px4-dev-simulation-jammy:<tag> | grep Digest
FROM docker.io/px4io/px4-dev-simulation-jammy@sha256:3b1bbb3c7b86150bdd916a22e3c2faa9276555bc9e89d2bd73ef53cf039f506a

# No ROS_DISTRO here: sourcing /opt/ros/humble/setup.bash sets it, so tools
# (evtol-dev's setup.sh among them) read a set ROS_DISTRO as "ROS is already
# loaded" and skip sourcing it, and colcon then can't find ament_cmake.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ROS 2 Humble Desktop, following the official "Ubuntu (deb packages)" guide:
#   - locale: UTF-8 (set via LANG/LC_ALL above)
#   - Ubuntu universe: already enabled in the Ubuntu base image
#   - ros2-apt-source package (version pinned for reproducible builds)
#   - ros-humble-desktop (ROS, RViz, demos, tutorials) + ros-dev-tools
#   - sudo (the container runs as `user`)
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
    && apt-get install -y --no-install-recommends ros-humble-desktop ros-dev-tools sudo \
    && rm -rf /var/lib/apt/lists/* /tmp/ros2-apt-source.deb

# Pinned Python build tools for ROS 2 / PX4, and rosdep set up once.
# (git, cmake, colcon, vcstool and rosdep already come from ros-dev-tools above.)
#   empy 3.3.4: the version both ROS 2 Humble and PX4 1.15 code generation need.
#   setuptools <80: `colcon build --symlink-install` installs ament_python
#     packages with `setup.py develop --editable`, and setuptools 80.0.0 removed
#     --editable ("error: option --editable not recognized"; colcon aborts at
#     the first Python package). Measured 2026-08-09 with colcon's real command:
#     59.6.0 / 70.0.0 / 75.6.0 / 79.0.0 OK, 80.0.0 / 83.0.0 FAIL.
#   packaging >=23: from setuptools 71 on, it calls
#     packaging.utils.canonicalize_version(..., strip_trailing_zero=...), which
#     needs packaging >=22 (complete in 23). Ubuntu 22.04's apt has 21.3, and
#     the build dies at the first ament_python package with "TypeError:
#     canonicalize_version() got an unexpected keyword argument
#     'strip_trailing_zero'". Measured: setuptools <=70.3 + packaging 21.3 OK;
#     71-79 + 21.3 FAIL; 71-79 + >=23 OK; >=80 FAIL with anything.
#   The constraint is a RELATION between the two, which no single version check
#   catches; evtol-dev's tests/build_smoke.py (run by setup.sh) tests it for real.
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
#     build) refuses to work in them
#   - /usr/lib/wsl/lib in the library loader's search path: on Windows,
#     devcontainer.json mounts WSL's GPU driver libraries there (libd3d12,
#     libdxcore) for Mesa's d3d12 driver. Registered the same way WSL's own
#     Ubuntu does it (ld.so.conf.d), and not with a container-wide
#     LD_LIBRARY_PATH, which would put them ahead of every library for every
#     process. postStartCommand runs ldconfig once they are mounted; on Linux
#     the folder doesn't exist and this changes nothing.
RUN echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
    && chmod 0440 /etc/sudoers.d/user \
    && git config --system --add safe.directory '*' \
    && echo /usr/lib/wsl/lib > /etc/ld.so.conf.d/ld.wsl.conf

# Micro XRCE-DDS Agent v2.4.3, the version PX4's uXRCE-DDS docs pair with PX4
# 1.15 and ROS 2 Humble (latest 2.x release), installed to /usr/local/bin.
# NOTE: the team's machines that fly use v3.0.1 (it was pinned in evtol-dev's
# former env/desktop-humble.yaml, which said a move back to 2.x must be
# validated in simulation first). For that version:
#   --build-arg XRCE_AGENT_VERSION=v3.0.1
# The onboard computer must run the same version as this image.
ARG XRCE_AGENT_VERSION=v2.4.3
RUN git clone --depth 1 --branch "${XRCE_AGENT_VERSION}" \
        https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /tmp/agent \
    && cmake -S /tmp/agent -B /tmp/agent/build \
    && cmake --build /tmp/agent/build --parallel 4 \
    && cmake --install /tmp/agent/build \
    && ldconfig /usr/local/lib/ \
    && rm -rf /tmp/agent

# ROS <-> Gazebo bridge: the GARDEN builds (ros-humble-ros-gzgarden-*, from the
# OSRF Gazebo repo the base image already configures). This has cost the team
# days of debugging: the bridge must be built against the same gz-transport as
# the Gazebo in use (Garden = gz-sim7 + gz-transport12, which PX4 v1.15.4's
# Tools/setup/ubuntu.sh installs). NEVER add any of these:
#   ros-humble-ros-gz-{image,bridge,sim}  FORTRESS builds (gz-transport11): they
#                       install and run without errors and simply never see a
#                       Gazebo topic. A silent failure.
#   ros-humble-ros-gzharmonic-*, gz-harmonic  HARMONIC: conflicts with Garden.
#   ros-humble-behaviortree-cpp(-v3)  the v4 apt package (4.9.1) is BROKEN: it
#                       installs the library in lib/x86_64-linux-gnu/ while its
#                       CMake export looks in lib/, so find_package aborts; the
#                       -v3 one is the incompatible v3 API. BehaviorTree.CPP is
#                       built from source in the underlay below.
# Also vision_msgs and cv_bridge, which the team's vision nodes use.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ros-humble-ros-gzgarden-image ros-humble-ros-gzgarden-bridge \
        ros-humble-ros-gzgarden-sim ros-humble-ros-gzgarden-interfaces \
        ros-humble-vision-msgs ros-humble-cv-bridge \
    && rm -rf /var/lib/apt/lists/*

# Python packages for the vision and gesture nodes. Installed system-wide (pip
# puts them in /usr/local, ahead of the apt ones): on personal machines they
# lived in a venv because ~/.local had conflicting packages, which a container
# doesn't have.
#   numpy >=1.24,<2: ROS 2 Humble's cv_bridge is a Boost.Python extension built
#     against the numpy 1.x ABI. With numpy 2, imgmsg_to_cv2 (the first thing
#     every vision node does with an image) fails with "SystemError:
#     <Boost.Python.function object ...> returned a result with an exception
#     set", a message that never mentions numpy. Measured 2026-08-09, same cv2:
#     numpy 1.26.4 OK, 2.2.6 SystemError.
#   opencv-contrib-python 4.11.0.86: the CEILING comes from numpy: from 4.12 on
#     the wheel REQUIRES numpy >=2 (4.12.0.88 / 4.13.0.92 + numpy<2 ->
#     ResolutionImpossible). The FLOOR is ArUco's API, changed incompatibly in
#     4.7 (ArucoDetector), which our code uses. `contrib` and not plain
#     opencv-python because mediapipe depends on it; the two install the same
#     cv2 module and must never coexist (never add opencv-python). contrib is a
#     superset: same version, same abi3 wheel. Validated: ArUco end to end and
#     cv_bridge.imgmsg_to_cv2 with numpy 1.26.4.
#   mediapipe 0.10.18: the newest version that BOTH has aarch64 wheels (the
#     Jetson and the Raspberry Pi, where phase 3 flies) AND pins numpy <2
#     itself. Measured on PyPI 2026-08-12: 1.0.0 aarch64 but numpy unpinned;
#     0.10.35 / 0.10.21 / 0.10.20 no aarch64 (0.10.21 would pass every desktop
#     test and fail on the drone); 0.10.18 aarch64 + numpy <2. It needs
#     protobuf <5: with protobuf 7, GestureRecognizer.create_from_options fails
#     with "MessageFactory object has no attribute GetPrototype".
#   Resolution verified in a clean venv (2026-08-12): mediapipe==0.10.18 +
#   opencv-contrib-python==4.11.0.86 + numpy>=1.24,<2 -> numpy 1.26.4.
RUN python3 -m pip install --no-cache-dir \
        'numpy>=1.24,<2' opencv-contrib-python==4.11.0.86 mediapipe==0.10.18 \
    && python3 -c "import cv2, numpy, mediapipe; assert numpy.__version__.startswith('1.'), numpy.__version__; print('cv2', cv2.__version__, 'numpy', numpy.__version__)"

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

# Underlay: the workspace's third-party ROS 2 packages (BehaviorTree.CPP,
# px4_msgs, px4-ros2-interface-lib), prebuilt in /opt/evtol_deps. They are NOT
# in the workspace's evtol.repos (see upstream-patches/evtol-dev-underlay.patch);
# deps.repos is the only place their versions are pinned.
# EVTOL_UNDERLAY tells the patched setup.sh and scripts/ros_env.sh to source
# /opt/evtol_deps/setup.bash, so the workspace builds against these packages
# and rosdep counts them as installed.
ARG DEPS_BUILD_JOBS=4
COPY deps.repos /opt/evtol_deps/deps.repos
RUN mkdir -p /tmp/deps/src \
    && vcs import /tmp/deps/src < /opt/evtol_deps/deps.repos \
    && apt-get update \
    && rosdep update --rosdistro humble \
    && rosdep install --from-paths /tmp/deps/src --ignore-src -y --rosdistro humble \
    && rm -rf /var/lib/apt/lists/* /root/.ros \
    && cd /tmp/deps \
    && . /opt/ros/humble/setup.sh \
    && CCACHE_DISABLE=1 MAKEFLAGS="-j${DEPS_BUILD_JOBS}" colcon build \
        --merge-install --install-base /opt/evtol_deps --executor sequential \
    && test -f /opt/evtol_deps/setup.bash \
    && rm -rf /tmp/deps
ENV EVTOL_UNDERLAY=/opt/evtol_deps

# The cache folders (named volumes in devcontainer.json) are created here and
# owned by `user`, so a new volume mounted on one starts out owned by `user` too.
RUN ln -s /opt/PX4-Autopilot /home/user/PX4-Autopilot \
    && mkdir -p /home/user/.ccache /home/user/.gz/fuel /home/user/.ros \
    && chown -R user:user /home/user

# evtol-dev's simulate.sh scripts look for PX4 at ~/PX4-Autopilot (~ =
# /home/user; linked above, so the build keeps its real /opt path) and for the
# team's models at ~/PX4-gazebo-models (bind-mounted from your computer by
# devcontainer.json; checked out at the commit docs/SETUP.md gives).
