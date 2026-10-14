This is a project that tries to implement Docker containers to the eVTOL dev workspace, featuring ROS 2 Humble, PX4 1.15, Micro XRCE DDS Agent and Gazebo Garden.

It is based on the evtol-dev GitHub repo (https://github.com/Equipe-eVTOL-ITA/evtol-dev), but tries to get rid of a lot of the health checks and test that Dev Containers make pointless. The objetive is to simplify the infraestructure as much as possible, but maintaining the functionality of the development workspace itself.

https://github.com/LilCout/evtol-devcontainer-setup features the Dockerfile and other files I used to build the image. This project is using Linux with an NVIDIA card as an example, by the general intent is to be able to use the Dev Container on Windows and other graphics cards, too, through the files in the evtol-devcontainer-setup repo.

The evtol-devcontainer-setup repo mentions evtol-dev patches, but this project is built from the ground up. Just the scripts folder, the tasks.json file, evtol.repos and .gitignore were copied from evtol-dev, with many changes to fulfill my objective. `scripts/setup.sh` is new: it sets up the workspace for the first time.

Notes:
- `src/` holds the team's repos (each its own git repo, ignored here). Fixes to them are pushed to their own remotes, not committed here.
- Inside the container, only this folder is on the host. The Gazebo models repo is cloned into `PX4-gazebo-models/` by `sim.repos` (`$PX4_GZ_MODELS`; `~/PX4-gazebo-models` is a link to it). Anything else outside the named volumes is lost on rebuild.
- Scripts that use ROS source `scripts/ros_env.sh` (ROS, the `/opt/evtol_deps` underlay, `install/`). `rosdep` needs it too, or it can't find `px4_msgs`.
- On the host, the repo is managed with jj (colocated with git). jj tracks every new file not yet in `.gitignore`, so add ignore rules before creating the files, and untrack with `jj file untrack`, not `git rm --cached`.

Here's the link to the chat I've been having with Claude on the browser: https://claude.ai/share/2a8013b9-2f57-470f-aa31-c804fe5ee4f6.

Also, try to avoid long comments.