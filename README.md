# evtol-devcontainer-setup

The eVTOL ITA ROS 2 workspace in a Dev Container: Ubuntu 22.04, ROS 2 Humble
Desktop, Gazebo Garden with its ROS bridge, PX4 v1.15.4 SITL prebuilt, Micro
XRCE-DDS Agent v2.4.3, the pinned pip packages and the third-party ROS packages
prebuilt as an underlay. It is based on
[evtol-dev](https://github.com/Equipe-eVTOL-ITA/evtol-dev), but the image
replaces its environment profiles and health checks: everyone runs the same image.

```
evtol/                  ← this repo; open it in VS Code on your computer
├── container/          ← the image (image/) and the devcontainer.json templates
├── dev/                ← the colcon workspace, opened in the container
│   ├── scripts/  templates/  evtol.repos  .vscode/tasks.json
│   └── src/  build/  install/  log/
├── PX4-gazebo-models/  ← the team's models and worlds, cloned from sim.repos
└── mission_logs/       ← rosbags and mission outputs, at ~/evtol/mission_logs
```

`container/image/` is the image's build context (`Dockerfile`, `deps.repos`);
`container/linux/` and `container/windows/` hold the `devcontainer.json`
templates, which run `container/xauth.sh` on Linux.

## Setup

```bash
git clone https://github.com/LilCout/evtol-devcontainer-setup.git evtol
mkdir -p evtol/.devcontainer
cp evtol/container/linux/devcontainer.json evtol/.devcontainer/   # or container/windows/ (WSL 2 + WSLg)
```

### Windows

The container uses `--network=host`, so that ROS 2, the XRCE-DDS Agent and
QGroundControl on Windows see each other. On Windows this only works with:

- **Docker Engine or Podman installed inside your WSL 2 distro**, not Docker
  Desktop. With Podman, set VS Code's `dev.containers.dockerPath` to `podman`.
- **WSL's mirrored networking.** Add this to `%UserProfile%\.wslconfig`, then
  run `wsl --shutdown`:

  ```ini
  [wsl2]
  networkingMode=mirrored
  ```

Clone the repo inside the WSL file system (for example `~/evtol` in your distro),
not under `/mnt/c`: writing rosbags there is slow. Open it from WSL
(`code ~/evtol`), so Dev Containers uses the engine installed there.

In `.devcontainer/devcontainer.json`, uncomment the lines tagged with your GPU
(`[NVIDIA]`, `[Intel/AMD]`, `[GPU]` on Windows, or `[No GPU]`). Then open
`evtol` and run **Reopen in Container**. To skip building the image, set
`"image"` to a prebuilt one instead of `"build"`.

Inside the container, VS Code opens `dev/`. From there:

```bash
./scripts/setup.sh    # vcs import, rosdep install, then ./scripts/build.sh all
```

`setup.sh` also clones the team's Gazebo models and worlds into
`PX4-gazebo-models/`, tracking `main` as listed in `sim.repos`. `$PX4_GZ_MODELS`
points there, and `~/PX4-gazebo-models` links to it for scripts that still use
that path.

`--sem-build` skips the build. It is safe to run again: repos already in `src/`
are left as they are.

The scripts and tasks load ROS on their own. In a terminal where you run `ros2`
by hand, first run `source scripts/ros_env.sh` (ROS, the underlay and `install/`).

The VS Code tasks (`.vscode/tasks.json`) cover simulation, builds and flight.
Run QGroundControl on your computer, not in the container.

## Where things are

| What | In the container |
|---|---|
| PX4 v1.15.4, built | `/opt/PX4-Autopilot`, linked at `~/PX4-Autopilot` |
| `MicroXRCEAgent` v2.4.3 | `/usr/local/bin` |
| BehaviorTree.CPP, px4_msgs, px4-ros2-interface-lib | underlay in `/opt/evtol_deps`, pinned in `container/image/deps.repos` |
| `gh`, Node.js, Claude Code | Dev Container features, installed when the container is created |
| This repo, with `dev/`, `PX4-gazebo-models/` and `mission_logs/` | `/workspaces/<repo folder>`, on your computer, so it survives rebuilds |
| Mission rosbags and outputs | `mission_logs/`, linked at `~/evtol/mission_logs` |
| evtol-dev's paths | `~/evtol/dev`, `~/evtol/mission_logs` and `~/PX4-gazebo-models` are links to the folders above |

Named volumes survive container rebuilds: `evtol-ccache` (`~/.ccache`),
`evtol-gz-fuel` (Gazebo Fuel downloads), `evtol-ros-home` (`~/.ros`) and
`evtol-claude` (Claude Code's login and settings).

## Notes

- `PX4-gazebo-models/` and `mission_logs/` are inside this repo but ignored by
  git. `git clean -fdx` at the repo root deletes them, flight logs included, and
  so does deleting the clone. To start a build over, remove `dev/build/`,
  `dev/install/` and `dev/log/` instead.
- The container's VS Code shows only `dev/`, so it doesn't watch or search the
  models and logs. Open `../PX4-gazebo-models` with **File > Add Folder to
  Workspace** to edit models, and edit the root files (`README.md`,
  `container/`) on your computer.
- To change an underlay package, edit `container/image/deps.repos` and rebuild
  the image. `px4_msgs` must match `PX4_REF` in the `Dockerfile`. A copy cloned
  into `src/` takes precedence over the image's.
- The team's flying machines use XRCE-DDS Agent v3.0.1. To match them, build with
  `"args": { "XRCE_AGENT_VERSION": "v3.0.1" }` in `"build"`.
- The container runs as the non-root `user` with passwordless `sudo`. On Linux
  it gets your uid/gid, so workspace files stay yours. With rootless Podman this
  needs Dev Containers CLI 0.76+ and VS Code set to `podman`, not a `docker`
  alias.
- `ROS_DOMAIN_ID` is left at 0, like the team's machines.
