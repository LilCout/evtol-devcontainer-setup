# Making a setup like this one

What we learned building this Dev Container, written to be reused for other
projects: another ROS distro, another simulator, or a different team. For how
*this* setup works, see [README.md](README.md).

## 1. Split by how often things change

| Put it in | When it is |
|---|---|
| the **image** (`Dockerfile`) | the same for everyone and slow to install: compilers, ROS, simulators, prebuilt dependencies |
| **`devcontainer.json`** | different per machine: GPU, display, OS, network |
| the **workspace** (bind mount) | edited by people: code, configs, data you care about |

If a step takes minutes and rarely changes, it belongs in the image. If two
teammates would need different values, it belongs in `devcontainer.json`, and
each person keeps a local copy of a shared template (`.devcontainer/` is
git-ignored here).

## 2. Write the Dockerfile for rebuilds

- **Pin everything.** Base image by digest, every `git clone --branch`, every
  pip package, every feature version. An unpinned image changes under you, and
  "it worked last week" becomes impossible to debug.
- **Order layers from stable to volatile.** Docker rebuilds from the first
  changed line down. Put the system packages first and your own fast-changing
  things last.
- **Use stages for heavy, independent builds.** Here PX4 and the XRCE-DDS Agent
  build in their own stages, so changing a Python package doesn't recompile PX4.
- **Use cache mounts** (`RUN --mount=type=cache`) for apt, pip and ccache. They
  speed up rebuilds without growing the image. For apt, delete
  `/etc/apt/apt.conf.d/docker-clean` first, or the cache stays empty.
- **Build at the final path** when the tool records absolute paths, like PX4.
  Copying a build to a new path breaks it.
- **End each build with a check** (`test -x`, an import), so a silent failure
  breaks the image build instead of reaching users.
- **Prebuild third-party packages as an underlay** (a colcon install in `/opt`)
  instead of making everyone build them in their workspace. Keep their versions
  in a manifest file (`deps.repos`) copied into the image.
- **Expose versions as `ARG`s** so a machine can override one from
  `devcontainer.json` without editing the Dockerfile.

## 3. Run as a normal user

- Use a non-root user, and set both `containerUser` and `remoteUser` to it.
- Set `updateRemoteUserUID: true`, so the user gets your uid/gid on Linux and
  files in the bind mount stay yours.
- Give it passwordless `sudo` for package installs.
- Add `git config --system --add safe.directory '*'` if the image has repos
  owned by root that tools will run git in.

## 4. Decide where every piece of data lives

| Kind of data | Where | Why |
|---|---|---|
| Code, and data you must keep (logs, recordings) | bind mount (the workspace) | visible and backed up from the host |
| Caches and logins (ccache, downloads, tokens) | named volume | survives rebuilds; you don't need it on the host |
| Everything else | the container | thrown away on rebuild, on purpose |

Two traps:

- **A bind mount's source must exist** before the container starts, or the
  container doesn't start. Avoid mounts of folders that people create by hand.
  Mount the workspace, and put extra folders inside it, created or cloned by a
  setup script. If a mounted file may legitimately be missing, create an empty
  one first, as `xauth.sh` does.
- **A named volume takes the ownership of the image folder it's mounted on.**
  Create that folder in the Dockerfile, owned by the user, or the volume is
  owned by root.

If the code expects fixed paths (here, evtol-dev's `~/evtol/dev` and
`~/evtol/mission_logs`), add symlinks in `postCreateCommand` instead of
changing the code.

## 5. GUI apps

- Mount the X socket (`/tmp/.X11-unix`) and set `DISPLAY`.
- Pass a cookie whose family is `ffff` ("any host"); see `xauth.sh`. Mounting
  the whole `~/.Xauthority` can fail, because its entries are tied to the
  host's name, which the container doesn't always share.
- On SELinux distros (Fedora, RHEL), add `--security-opt=label=disable`, or the
  socket is blocked.
- Set `QT_QPA_PLATFORM=xcb` when only X11 is available.
- On Windows, WSLg already provides an X server at `/mnt/wslg/.X11-unix`, with
  `DISPLAY=:0` and no cookie.

## 6. GPU

Keep each vendor's lines in the template, commented and tagged, and let each
person uncomment theirs:

- **NVIDIA:** CDI (`--device=nvidia.com/gpu=all`) works with Podman and Docker
  25+, after `nvidia-ctk cdi generate`. Laptops with two GPUs also need the
  PRIME offload variables.
- **Intel/AMD:** `--device=/dev/dri`, plus the groups that own the render
  nodes.
- **WSL:** `/dev/dxg` and `/usr/lib/wsl`, through Mesa's d3d12 driver.
- **No GPU:** `LIBGL_ALWAYS_SOFTWARE=1` as a fallback.

## 7. Network

ROS 2 discovery uses multicast, and tools on the host (QGroundControl) talk
over UDP. `--network=host` is the simplest way to make all of it work. On
Windows it only works with the engine installed inside WSL, not Docker
Desktop, and with WSL's mirrored networking. Also raise `--shm-size`: DDS and
simulators exceed the 64 MB default.

## 8. Lifecycle commands

- **`initializeCommand`** runs on the host before every start: prepare files the
  container mounts (like the X cookie).
- **`postCreateCommand`** runs once in a new container: links, ownership fixes,
  cache refreshes.
- Make commands that need the network **warn instead of fail**
  (`cmd || echo "…"`), or the container can't open offline.
- Use **features** for developer tools that aren't part of the environment
  itself (`gh`, Node.js, editors' CLIs), pinned to a version.

## 9. Keep the workspace tools out of the container's way

- Open a subfolder (`workspaceFolder`) when the repo holds things your tools
  shouldn't crawl. Here colcon would try to build the models repo's
  `CMakeLists.txt`, and VS Code would index gigabytes of rosbags.
- Never run `git clean -fdx` at the root of a repo that keeps ignored data
  inside it.

## Checklist for a new setup

- [ ] Base image pinned by digest
- [ ] Every version pinned: clones, pip, features, manifests
- [ ] Heavy builds in their own stages, with a check at the end
- [ ] Cache mounts for apt, pip and ccache
- [ ] Non-root user with `updateRemoteUserUID`
- [ ] Each piece of data assigned: workspace, named volume or disposable
- [ ] No bind mount of a folder that might not exist
- [ ] Display works (socket, `DISPLAY`, cookie, SELinux)
- [ ] One commented block per GPU vendor, plus a software fallback
- [ ] Network and shared memory sized for DDS
- [ ] `postCreateCommand` works offline
- [ ] Templates committed, the local `.devcontainer/` ignored
- [ ] A one-command setup script for the workspace (`dev/scripts/setup.sh` here)
