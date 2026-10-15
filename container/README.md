# How the Dev Container works

This folder holds everything that turns a computer with VS Code and a container
engine into the eVTOL development environment. This page explains what each
piece does and why. To build a similar setup for another project, read
[ADAPTING.md](ADAPTING.md) next.

```
container/
├── image/
│   ├── Dockerfile          ← the image: ROS 2, Gazebo, PX4, the agent, the underlay
│   └── deps.repos          ← third-party ROS packages built into the image
├── linux/devcontainer.json    ← template for Linux hosts
├── windows/devcontainer.json  ← template for Windows (WSL 2) hosts
└── xauth.sh                ← Linux only: gives the container access to your X server
```

Three layers make up the environment, from slowest to fastest to change:

| Layer | Defined in | Changes when | Shared by |
|---|---|---|---|
| **Image** | `image/Dockerfile`, `image/deps.repos` | a tool or dependency version changes | everyone |
| **Container** | `.devcontainer/devcontainer.json` | your GPU, display or OS differs | one machine |
| **Workspace** | this repo, bind-mounted | every day | one person |

The image is the same for everyone. The `devcontainer.json` holds what depends
on the machine, which is why it's a template you copy and edit, and why
`.devcontainer/` is git-ignored. The code lives on your computer, so it
survives anything that happens to the container.

## What happens on "Reopen in Container"

1. **`initializeCommand` runs on your computer** (Linux only): `xauth.sh`
   writes an X cookie (see [xauth.sh](#xauthsh)).
2. **The image is built** from `image/Dockerfile`, or pulled if `"image"`
   names a prebuilt one. Later builds reuse cached layers.
3. **Features are added** on top of the image: `gh`, Node.js and Claude Code,
   each pinned to a version.
4. **The user's uid/gid is adjusted** to match yours (`updateRemoteUserUID`),
   so files you create in the workspace are owned by you on the host.
5. **The container is created** with the `runArgs`, `mounts`, `containerEnv`
   and the workspace mount.
6. **`postCreateCommand` runs once** inside the container: it creates the
   links to evtol-dev's paths and refreshes the apt and rosdep caches.
7. **VS Code connects**, installs the listed extensions inside the container,
   and opens `dev/`.

Steps 2 to 4 produce images that the engine caches. A **Rebuild Container**
redoes steps 1 to 7; reopening an existing container only repeats 1 and 7.

## The image (`image/Dockerfile`)

### Base

```dockerfile
FROM docker.io/px4io/px4-dev-simulation-jammy@sha256:… AS base
```

PX4's own simulation image: Ubuntu 22.04 with Gazebo Garden, PX4's build
toolchain and a non-root `user` (uid 1001). It's pinned **by digest**, not by
tag, because tags on Docker Hub get overwritten; a digest always means the same
bytes.

The base also deletes `/etc/apt/apt.conf.d/docker-clean`, which normally throws
away downloaded `.deb` files. Without it, the apt cache mounts below would
always be empty.

### Three stages

The Dockerfile is a **multi-stage build**: two heavy compilations run in their
own stages, and the main stage copies only their results.

| Stage | Builds | Copied into the main stage |
|---|---|---|
| `xrce` | Micro XRCE-DDS Agent (`XRCE_AGENT_VERSION`, default v2.4.3) | `/usr/local/` |
| `px4` | PX4 SITL (`PX4_REF`, default v1.15.4) | `/opt/PX4-Autopilot` |
| main | ROS 2, the bridge, Python packages, the underlay | — |

Because `xrce` and `px4` don't depend on ROS, editing the main stage never
rebuilds them. Details worth knowing:

- **PX4 is built at its final path.** Its build records absolute paths, so it's
  cloned and built directly in `/opt/PX4-Autopilot` and copied to the same
  path.
- **PX4 skips the NuttX and VOXL2 submodules.** They're only for
  flight-controller hardware, and a shallow NuttX checkout breaks PX4's version
  script.
- **Each build ends with a `test`** (`test -x …/MicroXRCEAgent`,
  `test -e …/px4-gz_bridge`), so a broken build fails the image instead of
  shipping.
- **Versions are build arguments.** To match the team's flying machines, which
  use the agent v3.0.1, add `"args": { "XRCE_AGENT_VERSION": "v3.0.1" }` to
  `"build"` in `devcontainer.json`. The `*_BUILD_JOBS` arguments limit
  parallelism, since PX4 and the underlay can run out of RAM.

### Main stage, in order

Layers are ordered from least to most likely to change, so a change near the
end rebuilds only the end:

1. **ROS 2 Humble Desktop and `ros-dev-tools`**, from the ROS apt source.
2. **`rosdep init`** and a first `rosdep update` as `user`.
3. **Passwordless `sudo`** for `user`, for `apt-get` and `rosdep install`.
   **`safe.directory '*'`**: the checkouts in `/opt` belong to root, and git
   refuses to work in a repo owned by another user. PX4's build runs git, so
   without this it fails.
4. **The agent and PX4** copied from their stages.
5. **The ROS–Gazebo Garden bridge** (`ros-humble-ros-gzgarden-*`), plus
   `vision_msgs` and `cv_bridge`.
6. **Python packages**, pinned (`numpy<2`, OpenCV 4.11, MediaPipe 0.10.18), with
   an import check at the end. MediaPipe and OpenCV need these exact ranges.
7. **The underlay**: the third-party ROS packages in `deps.repos`
   (BehaviorTree.CPP, `px4_msgs`, px4-ros2-interface-lib) are built with colcon
   into `/opt/evtol_deps`. `EVTOL_UNDERLAY` points there, and
   `dev/scripts/ros_env.sh` sources it between ROS and the workspace. A package
   with the same name in `dev/src/` takes precedence. `px4_msgs` must match
   `PX4_REF`.
8. **Folders for the named volumes**, owned by `user` (see
   [Volumes](#volumes-and-what-survives-a-rebuild)).

### Build caches

`RUN --mount=type=cache,…` lines keep apt downloads, pip downloads and ccache
**on the host between builds**, without putting them in the image. Rebuilding
PX4 or the underlay after a small change is much faster because of ccache.
`podman system prune` or `buildah prune` (Docker: `docker builder prune`)
clears them.

## The container (`devcontainer.json`)

There's one template per host OS. You copy one to `.devcontainer/` and
uncomment the lines tagged with your GPU. Lines starting with `///` explain;
lines starting with `//` are options.

### Workspace mount

```jsonc
"workspaceMount": "type=bind,source=${localWorkspaceFolder},target=/workspaces/${localWorkspaceFolderBasename}",
"workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}/dev",
```

The whole repo is mounted, but VS Code opens `dev/`, the colcon workspace.
`PX4-gazebo-models/` and `mission_logs/` sit next to it, so colcon and VS Code
don't see them. `git.openRepositoryInParentFolders` lets the Git panel find the
repo one level up.

### Display (Gazebo, RViz, rqt)

GUI apps in the container draw on **your** screen through the X server.

| | Linux | Windows (WSLg) |
|---|---|---|
| X socket | `/tmp/.X11-unix` from the host | `/mnt/wslg/.X11-unix` from WSL |
| `DISPLAY` | copied from your session | `:0` |
| Cookie | written by `xauth.sh`, mounted as `/tmp/px4.xauth` | not needed |
| SELinux | `--security-opt=label=disable` (otherwise the socket is blocked) | — |

`QT_QPA_PLATFORM=xcb` makes Qt apps use X11, since no Wayland socket is
mounted.

### GPU

Pick one block in your copy:

| Tag | What it does |
|---|---|
| `[NVIDIA]` | `--device=nvidia.com/gpu=all` uses CDI: the NVIDIA Container Toolkit must have generated a CDI spec (`nvidia-ctk cdi generate`). Works with Podman, and Docker 25+. The `__NV_PRIME_*`/`__GLX_*` variables send rendering to the NVIDIA card on hybrid laptops. |
| `[Intel/AMD]` | `--device=/dev/dri`, plus the groups that own the render nodes: `keep-groups` with rootless Podman, or the numeric group ids with Docker. |
| `[GPU]` (Windows) | WSL's `/dev/dxg` device and driver libraries, used through Mesa's d3d12 driver. |
| `[No GPU]` | `LIBGL_ALWAYS_SOFTWARE=1`: works everywhere, but Gazebo is slow. |

### Network and shared memory

- **`--network=host`**: the container shares the host's network. DDS discovery
  (multicast), the XRCE-DDS Agent (UDP 8888) and QGroundControl on the host
  (UDP 14550) then work with no port mapping. On Windows this requires the
  engine inside WSL and WSL's mirrored networking (see the root README).
- **`--shm-size=1g`**: Fast DDS's shared-memory transport and Gazebo need more
  than the 64 MB default.

### Volumes and what survives a rebuild

| Data | Where | Survives |
|---|---|---|
| Code, `build/`, `install/`, models, mission logs | the repo (bind mount) | everything, and it's visible on the host |
| ccache, Gazebo Fuel downloads, `~/.ros`, Claude Code's login | named volumes `evtol-*` | rebuilds; deleted by `volume prune` |
| Anything else (apt installs, `~/.local`, files in `/tmp`) | the container | nothing: lost on rebuild |

A new named volume copies the ownership of the image folder it's mounted on.
The Dockerfile creates those folders owned by `user`, so the volumes need no
`chown`. The exception is `~/.claude`, which the image doesn't create:
`postCreateCommand` fixes its owner.

Mission logs could be a named volume too, but they live in the repo so they're
easy to open and back up from the host. See the root README's notes for the
trade-offs.

### Environment variables

| Variable | Why |
|---|---|
| `CCACHE_DIR`, `CCACHE_MAXSIZE` | colcon builds use the ccache volume, up to 10 GB |
| `PX4_GZ_MODELS` | where `simulate.sh` finds the team's models and worlds |
| `CLAUDE_CONFIG_DIR` | keeps Claude Code's login in its volume |
| `ROS_DISTRO`, `EVTOL_UNDERLAY` | set in the image, read by `ros_env.sh` |

### Lifecycle commands

- **`initializeCommand`** (host, before anything else): `bash container/xauth.sh`.
- **`postCreateCommand`** (container, once after creation):
  - fixes `~/.claude`'s owner;
  - links `~/PX4-gazebo-models`, `~/evtol/mission_logs` and `~/evtol/dev` to
    the repo's folders, so code written for evtol-dev's paths works unchanged;
  - runs `apt-get update` and `rosdep update`. Each one only warns if it fails,
    so the container still opens offline.

### User

`containerUser` and `remoteUser` are both the base image's `user`, never root.
`updateRemoteUserUID` changes its uid/gid to yours at creation. With rootless
Podman, the Dev Containers CLI also adds `--userns=keep-id`. This needs Dev
Containers CLI 0.76 or later, and VS Code set to `podman`, not a `docker`
alias.

## `xauth.sh`

An X server only accepts clients that show its **cookie**. The cookie in
`~/.Xauthority` is tied to your hostname, which differs inside the container.
The script:

1. extracts the cookie for `$DISPLAY` (`xauth nlist`);
2. replaces the address family with `ffff` ("any host"), so the cookie is valid
   from inside the container;
3. writes it to `$XDG_RUNTIME_DIR/px4-devcontainer.xauth`, a private per-user
   folder (`umask 077`).

The container mounts that file read-only and points `XAUTHORITY` at it. The
script runs again on every container start, so a new login session's cookie
is picked up.

If there's no cookie (some X servers don't use one), it writes an **empty
file** anyway: a bind mount fails when its source doesn't exist, and the
container wouldn't start.

## Prebuilt image

Building the image takes a while: PX4, the agent and the underlay compile from
source. To skip that, build it once, push it to a registry, and reference it
by digest in `"image"` instead of `"build"`:

```bash
podman build -t ghcr.io/<user>/evtol-devcontainer container/image   # or docker build
podman push ghcr.io/<user>/evtol-devcontainer
```

Features, the uid change and `postCreateCommand` still run on each machine:
they're not part of the image.
