# evtol-dev dev container

A container matching `env/desktop-humble.yaml`: Ubuntu 22.04, ROS 2 Humble
Desktop, Gazebo Garden with the **Garden** ROS bridge (`ros-humble-ros-gzgarden-*`),
PX4 v1.15.4 SITL prebuilt, and Micro XRCE-DDS Agent v2.4.3 (the profile pins v3.0.1; see Notes).

## Layout on your computer

```
~/evtol/
├── dev/                  ← evtol-dev (this .devcontainer/ goes here); open this folder
└── PX4-gazebo-models/    ← the team's models repo, cloned once (mounted at ~/PX4-gazebo-models)
```

```bash
mkdir -p ~/evtol && cd ~/evtol
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git dev
git clone https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git   # must exist before the container starts
# copy this .devcontainer/ folder into ~/evtol/dev/, then open ~/evtol/dev and "Reopen in Container"
```

`devcontainer.json` works as shipped on Linux with an NVIDIA GPU. For an
Intel/AMD GPU, Windows (WSL2 + WSLg) or no GPU, comment/uncomment the lines
tagged `[Intel/AMD]`, `[Windows]` or `[No GPU]` in that file; its header lists
the tags.

## First run, inside the container (from the workspace root)

```bash
./scripts/venv.sh --profile desktop-humble    # the profile's pip packages, in .venv
./setup.sh --profile desktop-humble           # doctor -> vcs import -> rosdep -> colcon build
```

After that, everything in docs/SETUP.md section 7 and the VS Code tasks work as
written (`simulate.sh`, `agent.sh`, `image_bridge.sh`, `ros2 launch ...`).
Run QGroundControl on your computer, not in the container.

## Where things are

| The workspace expects | In the container |
|---|---|
| `~/PX4-Autopilot` (v1.15.4, built) | link to `/opt/PX4-Autopilot`, built into the image |
| `~/PX4-gazebo-models` (pinned commit) | bind mount of `../PX4-gazebo-models` from your computer |
| `~/Micro-XRCE-DDS-Agent` (v2.4.3) + `/usr/local/bin/MicroXRCEAgent` | built into the image |
| `ros-humble-ros-gzgarden-*`, `ros-humble-desktop`, vision_msgs, cv_bridge | installed from apt |
| `.venv`, `src/`, `install/`, `.evtol-profile` | in the workspace folder, so they survive rebuilds |

## Notes

- `ROS_DOMAIN_ID` is left at the default (0), like the team's machines, so the
  ground station sees the drone's topics.
- `apt-get update` runs once when the container is created, because `setup.sh`'s
  `rosdep install` needs package lists and the image deletes them to stay small.
  If it fails (no network), container creation still succeeds with a warning;
  run `sudo apt-get update` before `setup.sh`.
- The image has Micro XRCE-DDS Agent **v2.4.3** (the version PX4's docs pair
  with PX4 1.15 and Humble), but `env/desktop-humble.yaml` pins **v3.0.1**, the
  version on the team's flying machines. Until the profile changes, the doctor
  reports a mismatch for `~/Micro-XRCE-DDS-Agent`, and `setup.sh` stops there.
  For the profile's version, build with `--build-arg XRCE_AGENT_VERSION=v3.0.1`
  (in `devcontainer.json`: `"build": { "dockerfile": "Dockerfile", "args":
  { "XRCE_AGENT_VERSION": "v3.0.1" } }`).
- Three named volumes keep caches across image rebuilds: `evtol-ccache`
  (`~/.ccache`, compiled objects), `evtol-gz-fuel` (`~/.gz/fuel`, Gazebo Fuel
  downloads) and `evtol-ros-home` (`~/.ros`, ROS logs and rosdep data).
  `rosdep update` also runs on container creation, so the volume never serves
  an old rosdep cache. Check usage with `ccache -s`; start over with
  `podman volume rm evtol-ccache` (container stopped).
- Worlds linked by `simulate.sh` go into the image's PX4 tree and are re-linked
  automatically after a container rebuild.
- The container runs as the non-root `user` (home `/home/user`, passwordless
  `sudo`). On Linux the Dev Containers CLI gives it your uid/gid, so files
  created in the workspace are owned by you with Docker as well as with rootless
  Podman (for Podman the CLI adds `--userns=keep-id` itself; that needs Dev
  Containers CLI 0.76 or newer, and VS Code set to `podman` rather than a
  `docker` → podman alias). If you used an earlier root version of this
  container with Docker, delete the three cache volumes once, since they
  belong to root.
- `/opt/PX4-Autopilot` is writable by everyone, because your uid is only known
  when the container is created and SITL writes its logs and parameters there.
