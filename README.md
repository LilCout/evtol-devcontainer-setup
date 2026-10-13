# evtol-dev dev container

The workspace's whole environment, as one image: Ubuntu 22.04, ROS 2 Humble
Desktop, Gazebo Garden with the **Garden** ROS bridge (`ros-humble-ros-gzgarden-*`),
PX4 v1.15.4 SITL prebuilt, Micro XRCE-DDS Agent v2.4.3, the pinned pip packages
(numpy, OpenCV, mediapipe, setuptools, packaging), and the third-party ROS
packages prebuilt as an underlay. It replaces evtol-dev's `env/` profiles,
`doctor.sh` and `scripts/venv.sh`: instead of checking each machine against a
profile, everyone runs the same image. Every pin is explained in the
`Dockerfile`, next to the line that installs it.

## Layout on your computer

```
~/evtol/
├── dev/                  ← evtol-dev (this .devcontainer/ goes here); open this folder
└── PX4-gazebo-models/    ← the team's models repo at commit 492352b (mounted at ~/PX4-gazebo-models)
```

```bash
mkdir -p ~/evtol && cd ~/evtol
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git dev
git clone https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git   # must exist before the container starts
git -C PX4-gazebo-models checkout 492352b                             # has the `wanda` model (CBR phase 4)
# copy this .devcontainer/ folder into ~/evtol/dev/, apply the evtol-dev patches
# (see below), then open ~/evtol/dev and "Reopen in Container"
```

`devcontainer.json` works as shipped on Linux with an NVIDIA GPU. For an
Intel/AMD GPU, Windows (WSL2 + WSLg) or no GPU, comment/uncomment the lines
tagged `[Intel/AMD]`, `[Windows]` or `[No GPU]` in that file; its header lists
the tags.

## The evtol-dev patches

Apply both, in order, in the workspace root (`~/evtol/dev`). They are meant for
this container and are not compatible with upstream evtol-dev.

```bash
git apply upstream-patches/evtol-dev-underlay.patch    # 1
git apply upstream-patches/evtol-dev-simplify.patch    # 2, on top of 1
```

1. **underlay**: removes the three third-party repos from `evtol.repos` and makes
   `setup.sh` and `scripts/ros_env.sh` load `/opt/evtol_deps`.
2. **simplify**: removes what the image makes redundant: `doctor.sh`,
   `env/doctor.py`, `env/collect.sh`, the `env/*.yaml` profiles,
   `scripts/venv.sh`, `.evtol-profile`, the doctor's VS Code tasks and CI steps.
   `setup.sh` becomes import → environment tests → rosdep → build, and
   `ros_env.sh` just loads ROS, the underlay and `install/`. The two real
   environment tests move to `tests/` and run in `setup.sh`. `docs/SETUP.md` and
   the `README.md` describe the container setup. The onboard computer (Jetson),
   which is set up by hand, keeps working: without the underlay, `setup.sh`
   builds the three third-party packages from source.

If you had a native setup in this folder, `.venv/` and `.evtol-profile` are no
longer used and can be deleted.

## First run, inside the container (from the workspace root)

```bash
./setup.sh      # vcs import -> environment tests -> rosdep -> colcon build
```

After that, `docs/SETUP.md` section 4 and the VS Code tasks work as written
(`simulate.sh`, `agent.sh`, `image_bridge.sh`, `ros2 launch ...`). Run
QGroundControl on your computer, not in the container.

## Where things are

| The workspace expects | In the container |
|---|---|
| `~/PX4-Autopilot` (v1.15.4, built) | link to `/opt/PX4-Autopilot`, built into the image |
| `~/PX4-gazebo-models` (commit 492352b) | bind mount of `../PX4-gazebo-models` from your computer |
| `/usr/local/bin/MicroXRCEAgent` (v2.4.3) | built into the image |
| `ros-humble-ros-gzgarden-*`, `ros-humble-desktop`, vision_msgs, cv_bridge | installed from apt |
| numpy, opencv-contrib-python, mediapipe, setuptools, packaging | installed with pip, system-wide |
| `behaviortree_cpp`, `px4_msgs`, `px4_ros2_interface` | prebuilt underlay in `/opt/evtol_deps` |
| `src/`, `build/`, `install/` | in the workspace folder, so they survive rebuilds |

## Prebuilt third-party packages (underlay)

BehaviorTree.CPP, px4_msgs and px4-ros2-interface-lib are compiled into the
image at `/opt/evtol_deps`, so `colcon build` only compiles the team's own code.
Their versions are pinned in `.devcontainer/deps.repos` and nowhere else (the
underlay patch removes them from `evtol.repos`). `setup.sh` and
`scripts/ros_env.sh` load `/opt/evtol_deps/setup.bash` because the image sets
`EVTOL_UNDERLAY`, so the workspace finds them and `rosdep install --ignore-src`
counts them as installed.

To change one of their versions, edit `deps.repos` and rebuild the image.
`px4_msgs` must match the PX4 firmware (`PX4_REF` in the Dockerfile). To work
on one of them in the workspace, clone it into `src/`: the workspace's copy is
built and takes precedence over the image's.

## Notes

- `ROS_DOMAIN_ID` is left at the default (0), like the team's machines, so the
  ground station sees the drone's topics.
- `apt-get update` runs once when the container is created, because `setup.sh`'s
  `rosdep install` needs package lists and the image deletes them to stay small.
  If it fails (no network), container creation still succeeds with a warning;
  run `sudo apt-get update` before `setup.sh`.
- The image has Micro XRCE-DDS Agent **v2.4.3** (the version PX4's docs pair
  with PX4 1.15 and Humble). The team's flying machines use **v3.0.1**, and the
  onboard computer must run the same version as the simulation. For v3.0.1,
  build with `--build-arg XRCE_AGENT_VERSION=v3.0.1` (in `devcontainer.json`:
  `"build": { "dockerfile": "Dockerfile", "args": { "XRCE_AGENT_VERSION": "v3.0.1" } }`).
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
