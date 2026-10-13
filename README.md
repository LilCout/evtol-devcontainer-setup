# evtol-devcontainer-setup

The eVTOL ITA ROS 2 workspace in a Dev Container: Ubuntu 22.04, ROS 2 Humble
Desktop, Gazebo Garden with its ROS bridge, PX4 v1.15.4 SITL prebuilt, Micro
XRCE-DDS Agent v2.4.3, the pinned pip packages and the third-party ROS packages
prebuilt as an underlay. It is based on
[evtol-dev](https://github.com/Equipe-eVTOL-ITA/evtol-dev), but the image
replaces its environment profiles and health checks: everyone runs the same image.

This repo is the workspace root. `container/` holds the image (`Dockerfile`,
`deps.repos`) and the `devcontainer.json` templates.

## Setup

```
~/evtol/
├── dev/                  ← this repo; open this folder in VS Code
└── PX4-gazebo-models/    ← the team's models repo (mounted at ~/PX4-gazebo-models)
```

```bash
mkdir -p ~/evtol && cd ~/evtol
git clone https://github.com/LilCout/evtol-devcontainer-setup.git dev
git clone https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git   # must exist before the container starts
git -C PX4-gazebo-models checkout 492352b                             # has the `wanda` model
mkdir -p dev/.devcontainer
cp dev/container/linux/devcontainer.json dev/.devcontainer/           # or container/windows/ (WSL 2 + WSLg)
```

In `.devcontainer/devcontainer.json`, uncomment the lines tagged with your GPU
(`[NVIDIA]`, `[Intel/AMD]`, `[GPU]` on Windows, or `[No GPU]`). Then open
`~/evtol/dev` and run **Reopen in Container**. To skip building the image, set
`"image"` to a prebuilt one instead of `"build"`.

Inside the container, from the workspace root:

```bash
vcs import src < evtol.repos
rosdep install --from-paths src --ignore-src -y
./scripts/build.sh all
```

The VS Code tasks (`.vscode/tasks.json`) cover simulation, builds and flight.
Run QGroundControl on your computer, not in the container.

## Where things are

| What | In the container |
|---|---|
| PX4 v1.15.4, built | `/opt/PX4-Autopilot`, linked at `~/PX4-Autopilot` |
| `MicroXRCEAgent` v2.4.3 | `/usr/local/bin` |
| BehaviorTree.CPP, px4_msgs, px4-ros2-interface-lib | underlay in `/opt/evtol_deps`, pinned in `container/deps.repos` |
| `gh`, Node.js, Claude Code | Dev Container features, installed when the container is created |
| `src/`, `build/`, `install/` | the workspace folder, so they survive rebuilds |

Named volumes survive container rebuilds: `evtol-ccache` (`~/.ccache`),
`evtol-gz-fuel` (Gazebo Fuel downloads), `evtol-ros-home` (`~/.ros`),
`evtol-mission-logs` (`~/evtol/mission_logs`, mission rosbags) and
`evtol-claude` (Claude Code's login and settings).

## Notes

- To change an underlay package, edit `container/deps.repos` and rebuild the
  image. `px4_msgs` must match `PX4_REF` in the `Dockerfile`. A copy cloned
  into `src/` takes precedence over the image's.
- The team's flying machines use XRCE-DDS Agent v3.0.1. To match them, build with
  `"args": { "XRCE_AGENT_VERSION": "v3.0.1" }` in `"build"`.
- The container runs as the non-root `user` with passwordless `sudo`. On Linux
  it gets your uid/gid, so workspace files stay yours. With rootless Podman this
  needs Dev Containers CLI 0.76+ and VS Code set to `podman`, not a `docker`
  alias.
- `ROS_DOMAIN_ID` is left at 0, like the team's machines.
