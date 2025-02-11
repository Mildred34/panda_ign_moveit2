#!/usr/bin/env bash

TAG="andrejorsula/panda_ign_moveit2"

## Forward custom volumes and environment variables
CUSTOM_VOLUMES=()
CUSTOM_ENVS=()
while getopts ":v:e:" opt; do
    case "${opt}" in
        v) CUSTOM_VOLUMES+=("${OPTARG}") ;;
        e) CUSTOM_ENVS+=("${OPTARG}") ;;
        *)
            echo >&2 "Usage: ${0} [-v VOLUME] [-e ENV] [TAG] [CMD]"
            exit 2
            ;;
    esac
done
shift "$((OPTIND - 1))"

## Determine TAG and CMD positional arguments
if [ "${#}" -gt "0" ]; then
    if [[ $(docker images --format "{{.Tag}}" "${TAG}") =~ (^|[[:space:]])${1}($|[[:space:]]) || $(wget -q https://registry.hub.docker.com/v2/repositories/${TAG}/tags -O - | grep -Poe '(?<=(\"name\":\")).*?(?=\")') =~ (^|[[:space:]])${1}($|[[:space:]]) ]]; then
        # Use the first argument as a tag is such tag exists either locally or on the remote registry
        TAG="${TAG}:${1}"
        CMD=${*:2}
    else
        CMD=${*:1}
    fi
fi

## GPU
LS_HW_DISPLAY=$(lshw -short -C display 2> /dev/null | grep display)
if [[ ${LS_HW_DISPLAY^^} =~ NVIDIA ]]; then
    # Enable GPU either via NVIDIA Container Toolkit or NVIDIA Docker (depending on Docker version)
    if dpkg --compare-versions "$(docker version --format '{{.Server.Version}}')" gt "19.3"; then
        GPU_OPT="--gpus all"
    else
        GPU_OPT="--runtime nvidia"
    fi
    GPU_ENVS=(
        NVIDIA_VISIBLE_DEVICES="all"
        NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"
    )
fi

## GUI
# To enable GUI, make sure processes in the container can connect to the x server
XAUTH=/tmp/.docker.xauth
if [ ! -f ${XAUTH} ]; then
    touch ${XAUTH}
    chmod a+r ${XAUTH}

    XAUTH_LIST=$(xauth nlist "${DISPLAY}")
    if [ -n "${XAUTH_LIST}" ]; then
        # shellcheck disable=SC2001
        XAUTH_LIST=$(sed -e 's/^..../ffff/' <<<"${XAUTH_LIST}")
        echo "${XAUTH_LIST}" | xauth -f ${XAUTH} nmerge -
    fi
fi
# GUI-enabling volumes
GUI_VOLUMES=(
    "${XAUTH}:${XAUTH}"
    "/tmp/.X11-unix:/tmp/.X11-unix"
    "/dev/input:/dev/input"
)
# GUI-enabling environment variables
GUI_ENVS=(
    XAUTHORITY="${XAUTH}"
    QT_X11_NO_MITSHM=1
    DISPLAY="${DISPLAY}"
)

## Additional volumes
# Synchronize timezone with host
CUSTOM_VOLUMES+=("/etc/localtime:/etc/localtime:ro")

## Additional environment variables
# Synchronize ROS_DOMAIN_ID with host
if [ -n "${ROS_DOMAIN_ID}" ]; then
    CUSTOM_ENVS+=("ROS_DOMAIN_ID=${ROS_DOMAIN_ID}")
fi
# Synchronize IGN_PARTITION with host
if [ -n "${IGN_PARTITION}" ]; then
    CUSTOM_ENVS+=("IGN_PARTITION=${IGN_PARTITION}")
fi
# Synchronize RMW configuration with host
if [ -n "${RMW_IMPLEMENTATION}" ]; then
    CUSTOM_ENVS+=("RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}")
fi
if [ -n "${CYCLONEDDS_URI}" ]; then
    CUSTOM_ENVS+=("CYCLONEDDS_URI=${CYCLONEDDS_URI}")
    CUSTOM_VOLUMES+=("${CYCLONEDDS_URI//file:\/\//}:${CYCLONEDDS_URI//file:\/\//}:ro")
fi
if [ -n "${FASTRTPS_DEFAULT_PROFILES_FILE}" ]; then
    CUSTOM_ENVS+=("FASTRTPS_DEFAULT_PROFILES_FILE=${FASTRTPS_DEFAULT_PROFILES_FILE}")
    CUSTOM_VOLUMES+=("${FASTRTPS_DEFAULT_PROFILES_FILE}:${FASTRTPS_DEFAULT_PROFILES_FILE}:ro")
fi

DOCKER_RUN_CMD=(
    docker run
    --interactive
    --tty
    --rm
    --network host
    --ipc host
    --privileged
    --security-opt "seccomp=unconfined"
    "${GUI_VOLUMES[@]/#/"--volume "}"
    "${GUI_ENVS[@]/#/"--env "}"
    "${GPU_OPT}"
    "${GPU_ENVS[@]/#/"--env "}"
    "${CUSTOM_VOLUMES[@]/#/"--volume "}"
    "${CUSTOM_ENVS[@]/#/"--env "}"
    "${TAG}"
    "${CMD}"
)

echo -e "\033[1;30m${DOCKER_RUN_CMD[*]}\033[0m" | xargs

# shellcheck disable=SC2048
exec ${DOCKER_RUN_CMD[*]}
