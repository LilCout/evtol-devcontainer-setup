#!/usr/bin/env bash
# =============================================================================
# setup.sh — prepara o workspace pela primeira vez, dentro do container.
# =============================================================================
#
#   ./scripts/setup.sh              clona o evtol.repos e o ../sim.repos, instala as dependências
#                                   e compila tudo
#   ./scripts/setup.sh --sem-build  só clona e instala as dependências
#
# Pode rodar de novo: repositórios que já estão em src/ não são mexidos.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"
cd "$ws_root"

# Sem o underlay, o rosdep não acha o px4_msgs e o BehaviorTree.CPP da imagem.
# shellcheck source=scripts/ros_env.sh
source "$script_dir/ros_env.sh"

compilar=1
case "${1:-}" in
    "")          ;;
    --sem-build) compilar=0 ;;
    *)           echo "setup.sh: opção desconhecida: $1" >&2; exit 2 ;;
esac

echo "==> Clonando os repositórios do evtol.repos em src/"
mkdir -p src
vcs import --skip-existing src < evtol.repos

echo "==> Clonando os modelos do Gazebo (sim.repos)"
vcs import --skip-existing .. < ../sim.repos

# O postCreateCommand roda o apt-get update, mas pode ter falhado sem rede.
if ! compgen -G "/var/lib/apt/lists/*_Packages*" > /dev/null; then
    echo "==> Atualizando as listas do apt"
    sudo apt-get update
fi

echo "==> Instalando as dependências (rosdep)"
rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO"

if (( compilar )); then
    echo "==> Compilando o workspace"
    "$script_dir/build.sh" all
fi
