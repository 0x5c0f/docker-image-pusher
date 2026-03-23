#!/usr/bin/bash
#################################################
#   author      0x5c0f
#   date        2024-06-19
#   email       mail@0x5c0f.cc
#   web         tools.0x5c0f.cc
#   version     1.2.0
#   last update 2025-03-23
#   descript    Use : ./docker-image-pusher.sh -h
#################################################

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

BASEDIR=$(dirname "$(readlink -f "$0")")

LOG_LEVEL="${LOG_LEVEL:-INFO}"

HUB_IMAGE_TAG="${HUB_IMAGE_TAG:-}"
NEW_IMAGE_TAG="${NEW_IMAGE_TAG:-}"

IMAGES_FILE="${IMAGES_FILE:-${BASEDIR}/images.ini}"
IMAGES_CLEAN_FLAG="${IMAGES_CLEAN_FLAG:-1}"

PRIVATE_REGISTRY_URLS="${PRIVATE_REGISTRY_URLS:-}"
PRIVATE_REGISTRY_USERNAME="${PRIVATE_REGISTRY_USERNAME:-}"
PRIVATE_REGISTRY_PASSWORD="${PRIVATE_REGISTRY_PASSWORD:-}"

SOURCE_REGISTRY_URLS="${SOURCE_REGISTRY_URLS:-}"
SOURCE_REGISTRY_USERNAME="${SOURCE_REGISTRY_USERNAME:-}"
SOURCE_REGISTRY_PASSWORD="${SOURCE_REGISTRY_PASSWORD:-}"

declare -i SYNC_SUCCESS_COUNT=0
declare -i SYNC_FAILED_COUNT=0
FAILED_IMAGES=""

## __SAY__ [info|success|error|warn|debug] <message>
## __SAY__ [info|success|error|warn|debug] bg <message>

__SAY__() {
    local LOG_LEVEL="${LOG_LEVEL:-INFO}"

    local -r ENDCOLOR="\033[0m"
    local -r INFOCOLOR="\033[1;34m"
    local -r SUCCESSCOLOR="\033[0;32m"
    local -r ERRORCOLOR="\033[0;31m"
    local -r WARNCOLOR="\033[0;33m"
    local -r DEBUGCOLOR="\033[0;35m"

    local LOGTYPE="INFOCOLOR"
    local msg_level="INFO"

    # 检查第一个参数是否是日志级别(不区分大小写)
    case "$1" in
        [Dd][Ee][Bb][Uu][Gg])
            msg_level="DEBUG"
            LOGTYPE="DEBUGCOLOR"
            shift
            ;;
        [Ii][Nn][Ff][Oo])
            msg_level="INFO"
            LOGTYPE="INFOCOLOR"
            shift
            ;;
        [Ss][Uu][Cc][Cc][Ee][Ss][Ss])
            msg_level="SUCCESS"
            LOGTYPE="SUCCESSCOLOR"
            shift
            ;;
        [Ww][Aa][Rr][Nn])
            msg_level="WARN"
            LOGTYPE="WARNCOLOR"
            shift
            ;;
        [Ee][Rr][Rr][Oo][Rr])
            msg_level="ERROR"
            LOGTYPE="ERRORCOLOR"
            shift
            ;;
    esac

    # 日志级别过滤：INFO=1 < WARN=2 < ERROR=3 < DEBUG=4
    local current_priority=1 msg_priority=1

    case "$LOG_LEVEL" in
        [Ii][Nn][Ff][Oo]|[Ss][Uu][Cc][Cc][Ee][Ss][Ss]) current_priority=1 ;;
        [Ww][Aa][Rr][Nn]) current_priority=2 ;;
        [Ee][Rr][Rr][Oo][Rr]) current_priority=3 ;;
        [Dd][Ee][Bb][Uu][Gg]) current_priority=4 ;;
    esac

    case "$msg_level" in
        INFO|SUCCESS) msg_priority=1 ;;
        WARN) msg_priority=2 ;;
        ERROR) msg_priority=3 ;;
        DEBUG) msg_priority=4 ;;
    esac

    # 消息级别高于设置级别则不显示
    [ "$msg_priority" -gt "$current_priority" ] && return 0

    # 构建消息
    local MESSAGE="$*"

    # bg 模式
    if [ "$1" = "bg" ]; then
        shift
        MESSAGE="${!LOGTYPE}$*${ENDCOLOR}"
    fi

    echo -e "[$(date '+%Y-%m-%d_%H:%M:%S')] [${!LOGTYPE}${msg_level}${ENDCOLOR}] ${MESSAGE}"
}

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_registry_url() {
    local registry
    registry="$(trim "${1:-}")"
    registry="${registry#http://}"
    registry="${registry#https://}"
    registry="${registry%/}"
    printf '%s' "$registry"
}

normalize_image_ref() {
    local image
    image="$(trim "${1:-}")"
    image="${image#-}"
    image="${image#http://}"
    image="${image#https://}"
    printf '%s' "$image"
}

has_registry_prefix() {
    local image
    image="$(normalize_image_ref "${1:-}")"
    local first_segment="${image%%/*}"

    if [ "$first_segment" = "$image" ]; then
        return 1
    fi

    case "$first_segment" in
        *.*|*:*|localhost)
            return 0
            ;;
    esac

    return 1
}

image_registry() {
    local image
    image="$(normalize_image_ref "${1:-}")"
    if has_registry_prefix "$image"; then
        printf '%s' "${image%%/*}"
    fi
}

split_to_array() {
    local raw="${1:-}"
    local array_name="${2}"
    local item
    local -a temp=()

    IFS='|' read -ra temp <<<"$raw"
    eval "$array_name=()"
    for item in "${temp[@]}"; do
        item="$(trim "$item")"
        [ -n "$item" ] || continue
        eval "$array_name+=(\"\$item\")"
    done
}

load_registry_auth_config() {
    split_to_array "$PRIVATE_REGISTRY_URLS" PRIVATE_REGISTRY_URLS_ARR
    split_to_array "$PRIVATE_REGISTRY_USERNAME" PRIVATE_REGISTRY_USERNAME_ARR
    split_to_array "$PRIVATE_REGISTRY_PASSWORD" PRIVATE_REGISTRY_PASSWORD_ARR

    split_to_array "$SOURCE_REGISTRY_URLS" SOURCE_REGISTRY_URLS_ARR
    split_to_array "$SOURCE_REGISTRY_USERNAME" SOURCE_REGISTRY_USERNAME_ARR
    split_to_array "$SOURCE_REGISTRY_PASSWORD" SOURCE_REGISTRY_PASSWORD_ARR
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        __SAY__ error "未找到命令: $1"
        exit 1
    }
}

docker_login_with_password_stdin() {
    local registry="$1"
    local username="$2"
    local password="$3"

    if [ -z "$registry" ] || [ -z "$username" ] || [ -z "$password" ]; then
        __SAY__ warn "跳过登录，认证信息不完整: ${registry:-unknown}"
        return 0
    fi

    __SAY__ info "开始登录: ${registry}"
    printf '%s' "$password" | docker login "$registry" --username "$username" --password-stdin >/dev/null || {
        __SAY__ error "登录失败: ${registry}"
        return 1
    }
}

is_docker_hub_registry() {
    case "${1:-}" in
        ""|docker.io|index.docker.io|registry-1.docker.io)
            return 0
            ;;
    esac
    return 1
}

resolve_source_credentials() {
    local source_registry="$1"
    local i registry username password

    if [ "${#SOURCE_REGISTRY_URLS_ARR[@]}" -eq 0 ]; then
        if is_docker_hub_registry "$source_registry" &&
           [ -n "$SOURCE_REGISTRY_USERNAME" ] &&
           [ -n "$SOURCE_REGISTRY_PASSWORD" ]; then
            printf '%s\n%s\n' "$SOURCE_REGISTRY_USERNAME" "$SOURCE_REGISTRY_PASSWORD"
            return 0
        fi
        return 1
    fi

    for ((i=0; i<${#SOURCE_REGISTRY_URLS_ARR[@]}; i++)); do
        registry="$(normalize_registry_url "${SOURCE_REGISTRY_URLS_ARR[$i]}")"
        username="${SOURCE_REGISTRY_USERNAME_ARR[$i]:-}"
        password="${SOURCE_REGISTRY_PASSWORD_ARR[$i]:-}"
        [ -n "$registry" ] || continue
        [ "$registry" = "$source_registry" ] || continue
        [ -n "$username" ] || return 1
        [ -n "$password" ] || return 1
        printf '%s\n%s\n' "$username" "$password"
        return 0
    done

    return 1
}

login_source_registry_if_needed() {
    local source_image="$1"
    local source_registry=""
    local creds=""
    local source_username=""
    local source_password=""

    source_registry="$(image_registry "$source_image")"
    [ -n "$source_registry" ] || source_registry="docker.io"

    creds="$(resolve_source_credentials "$source_registry" || true)"
    if [ -n "$creds" ]; then
        source_username="$(printf '%s\n' "$creds" | sed -n '1p')"
        source_password="$(printf '%s\n' "$creds" | sed -n '2p')"
    fi

    if [ -n "$source_username" ] && [ -n "$source_password" ]; then
        docker_login_with_password_stdin "$source_registry" "$source_username" "$source_password"
    fi
}

login_private_registries() {
    local i registry username password

    for ((i=0; i<${#PRIVATE_REGISTRY_URLS_ARR[@]}; i++)); do
        registry="$(normalize_registry_url "${PRIVATE_REGISTRY_URLS_ARR[$i]}")"
        username="${PRIVATE_REGISTRY_USERNAME_ARR[$i]:-}"
        password="${PRIVATE_REGISTRY_PASSWORD_ARR[$i]:-}"
        [ -n "$registry" ] || continue
        docker_login_with_password_stdin "$registry" "$username" "$password" || return 1
    done
}

login_target_registry_if_needed() {
    local target_image="$1"
    local target_registry=""
    local i registry username password

    target_registry="$(image_registry "$target_image")"
    [ -n "$target_registry" ] || return 0

    for ((i=0; i<${#PRIVATE_REGISTRY_URLS_ARR[@]}; i++)); do
        registry="$(normalize_registry_url "${PRIVATE_REGISTRY_URLS_ARR[$i]}")"
        username="${PRIVATE_REGISTRY_USERNAME_ARR[$i]:-}"
        password="${PRIVATE_REGISTRY_PASSWORD_ARR[$i]:-}"
        [ "$registry" = "$target_registry" ] || continue
        docker_login_with_password_stdin "$registry" "$username" "$password" || return 1
        return 0
    done

    __SAY__ warn "目标仓库未在 PRIVATE_REGISTRY_URLS 中声明，跳过预登录: ${target_registry}"
    return 0
}

resolve_targets() {
    local target="$1"
    local clean_target registry

    clean_target="$(normalize_image_ref "$target")"
    [ -n "$clean_target" ] || return 1

    if has_registry_prefix "$clean_target"; then
        printf '%s\n' "$clean_target"
        return 0
    fi

    if [ "${#PRIVATE_REGISTRY_URLS_ARR[@]}" -eq 0 ]; then
        __SAY__ error "目标镜像未指定仓库地址，且未配置 PRIVATE_REGISTRY_URLS"
        return 1
    fi

    for registry in "${PRIVATE_REGISTRY_URLS_ARR[@]}"; do
        registry="$(normalize_registry_url "$registry")"
        [ -n "$registry" ] || continue
        printf '%s\n' "${registry}/${clean_target}"
    done
}

cleanup_image() {
    local image="$1"

    [ "${IMAGES_CLEAN_FLAG}" = "1" ] || return 0
    [ -n "$image" ] || return 0

    docker rmi "$image" >/dev/null 2>&1 || true
}

record_sync_failure() {
    local source_image="$1"
    local target_desc="$2"

    SYNC_FAILED_COUNT=$((SYNC_FAILED_COUNT + 1))
    FAILED_IMAGES="${FAILED_IMAGES}${source_image} -> ${target_desc}"$'\n'
}

record_sync_success() {
    SYNC_SUCCESS_COUNT=$((SYNC_SUCCESS_COUNT + 1))
}

append_unique_target() {
    local value="$1"
    shift
    local item

    for item in "$@"; do
        [ "$item" = "$value" ] && return 0
    done

    return 1
}

sync_image_targets() {
    local source_image="$1"
    shift
    local -a target_specs=("$@")
    local -a targets=()
    local target_spec target_ref

    source_image="$(normalize_image_ref "$source_image")"

    if [ -z "$source_image" ] || [ "${#target_specs[@]}" -eq 0 ]; then
        __SAY__ error "镜像配置不完整: ${source_image}"
        return 1
    fi

    for target_spec in "${target_specs[@]}"; do
        target_spec="$(normalize_image_ref "$target_spec")"
        [ -n "$target_spec" ] || continue

        while IFS= read -r target_ref || [ -n "$target_ref" ]; do
            [ -n "$target_ref" ] || continue
            append_unique_target "$target_ref" "${targets[@]}" || targets+=("$target_ref")
        done < <(resolve_targets "$target_spec") || return 1
    done

    [ "${#targets[@]}" -gt 0 ] || {
        __SAY__ error "未解析到有效目标镜像: ${source_image}"
        return 1
    }

    login_source_registry_if_needed "$source_image" || return 1
    __SAY__ info "拉取镜像: ${source_image}"
    docker pull "$source_image" || {
        __SAY__ error "镜像拉取失败: ${source_image}"
        return 1
    }

    for target_ref in "${targets[@]}"; do
        login_target_registry_if_needed "$target_ref" || return 1
        __SAY__ info "同步镜像: ${source_image} -> ${target_ref}"
        docker tag "$source_image" "$target_ref" || {
            __SAY__ error "镜像标记失败: ${target_ref}"
            cleanup_image "$source_image"
            return 1
        }
        docker push "$target_ref" || {
            __SAY__ error "镜像推送失败: ${target_ref}"
            __SAY__ error "请检查目标仓库地址、账号密码以及命名空间是否正确: $(image_registry "$target_ref")"
            cleanup_image "$target_ref"
            cleanup_image "$source_image"
            return 1
        }
        cleanup_image "$target_ref"
    done

    cleanup_image "$source_image"
    __SAY__ success "镜像同步完成: ${source_image}"
    return 0
}

sync_image() {
    local source_image target_image

    source_image="$(normalize_image_ref "${HUB_IMAGE_TAG:-$1}")"
    target_image="$(normalize_image_ref "${NEW_IMAGE_TAG:-$2}")"

    if [ -z "$source_image" ] || [ -z "$target_image" ]; then
        __SAY__ error "镜像配置不完整: ${source_image} -> ${target_image}"
        return 1
    fi

    sync_image_targets "$source_image" "$target_image"
}

parse_images_file() {
    local line source_image target_image targets_raw
    local -a target_specs=()

    [ -f "$IMAGES_FILE" ] || {
        __SAY__ error "${IMAGES_FILE} not exist"
        exit 1
    }

    __SAY__ info "开始读取同步镜像信息: ${IMAGES_FILE}"

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(trim "$line")"
        [ -n "$line" ] || continue
        case "$line" in
            \#*) continue ;;
        esac

        source_image="$(trim "${line%%=*}")"
        targets_raw="$(trim "${line#*=}")"

        if [ "$source_image" = "$line" ] || [ -z "$source_image" ] || [ -z "$targets_raw" ]; then
            __SAY__ warn "跳过无效配置: ${line}"
            continue
        fi

        target_specs=()
        IFS=',' read -ra target_specs <<<"$targets_raw"
        if sync_image_targets "$source_image" "${target_specs[@]}"; then
            record_sync_success
        else
            record_sync_failure "$source_image" "$targets_raw"
        fi
    done <"$IMAGES_FILE"
}

load_env_overrides() {
    local raw="${1:-}"
    local pair key value
    local -a env_arr=()

    [ -n "$raw" ] || return 0

    IFS=',' read -ra env_arr <<<"$raw"
    for pair in "${env_arr[@]}"; do
        pair="$(trim "$pair")"
        [ -n "$pair" ] || continue
        key="$(trim "${pair%%=*}")"
        value="${pair#*=}"
        [ -n "$key" ] || continue
        printf -v "$key" '%s' "$value"
        export "$key"
    done
}

precheck() {
    require_command docker
    load_registry_auth_config
    login_private_registries || exit 1
}

main() {
    if [ -n "$HUB_IMAGE_TAG" ] || [ -n "$NEW_IMAGE_TAG" ]; then
        if [ -z "$HUB_IMAGE_TAG" ] || [ -z "$NEW_IMAGE_TAG" ]; then
            __SAY__ error "单镜像同步时必须同时指定 -s 和 -t"
            exit 1
        fi
        if sync_image "$HUB_IMAGE_TAG" "$NEW_IMAGE_TAG"; then
            record_sync_success
        else
            record_sync_failure "$HUB_IMAGE_TAG" "$NEW_IMAGE_TAG"
        fi
        return
    fi

    parse_images_file
}

print_summary() {
    __SAY__ info "同步结果汇总: 成功 ${SYNC_SUCCESS_COUNT}，失败 ${SYNC_FAILED_COUNT}"
    if [ -n "$FAILED_IMAGES" ]; then
        __SAY__ info "失败列表:"
        while IFS= read -r failed_line || [ -n "$failed_line" ]; do
            [ -n "$failed_line" ] || continue
            __SAY__ info "  ${failed_line}"
        done <<EOF
${FAILED_IMAGES}
EOF
    fi
}

__HELP__() {
    echo "Usage: $(basename "$0") [-h] [-c images_file] [-s source_tag] [-t target_tag] [-e environment]"
    echo ""
    echo "Options:"
    echo "  -h                                  展示帮助文档并退出."
    echo "  -c images_file                      指定同步配置文件, 默认 ${IMAGES_FILE}."
    echo "  -s source_tag                       单镜像同步时，指定源镜像，支持任意 Registry 地址."
    echo "  -t target_tag                       单镜像同步时，指定目标镜像，支持任意 Registry 地址."
    echo "  -e environment                      指定环境变量, 用以覆盖内置变量(key=value,key=value)."
    echo ""
    echo "Image_file:"
    echo "      配置文件格式:"
    echo "          源镜像=目标镜像1,目标镜像2,目标镜像3"
    echo "      配置文件示例:"
    echo "          nginx=base/nginx"
    echo "          registry.example.com/team/nginx:1.27=harbor-a.example.com/base/nginx:1.27,harbor-b.example.com/base/nginx:1.27"
    echo ""
    echo "Target_tag:"
    echo "      目标镜像支持两种形式:"
    echo "          1. 完整镜像地址: harbor.example.com/base/nginx:latest"
    echo "          2. 仓库内路径:   base/nginx:latest"
    echo "             当使用仓库内路径时，会自动拼接 PRIVATE_REGISTRY_URLS 中的每个仓库地址."
    echo "Result:"
    echo "      批量模式下，单个镜像失败不会中断后续同步."
    echo "      脚本结束时会输出成功/失败汇总；若存在失败项，退出码为非 0."
    echo ""
    echo "Environment:"
    echo "      参数优先级: 命令行 > -e > 系统环境变量 > .env > 默认值"
    echo "系统变量:"
    echo "      LOG_LEVEL                       日志级别, 默认 ${LOG_LEVEL}(INFO/WARN/DEBUG/ERROR)"
    echo "      IMAGES_FILE                     指定同步配置文件, 默认 ${IMAGES_FILE}"
    echo "      HUB_IMAGE_TAG                   指定同步的源镜像"
    echo "      NEW_IMAGE_TAG                   指定同步的目标镜像"
    echo "      IMAGES_CLEAN_FLAG               是否清理镜像, 默认 ${IMAGES_CLEAN_FLAG} (1: 每次推送后立即清理, 0: 不清理)"
    echo "      PRIVATE_REGISTRY_URLS           目标仓库地址, 多个地址用 '|' 分隔"
    echo "      PRIVATE_REGISTRY_USERNAME       目标仓库用户名, 多个用 '|' 分隔，顺序对应 PRIVATE_REGISTRY_URLS"
    echo "      PRIVATE_REGISTRY_PASSWORD       目标仓库密码, 多个用 '|' 分隔，顺序对应 PRIVATE_REGISTRY_URLS"
    echo "      SOURCE_REGISTRY_URLS            源仓库地址, 非必填; 支持多个地址用 '|' 分隔; 留空时默认按 Docker Hub 处理"
    echo "      SOURCE_REGISTRY_USERNAME        源仓库用户名, 非必填; 支持多个用 '|' 分隔，顺序对应 SOURCE_REGISTRY_URLS"
    echo "      SOURCE_REGISTRY_PASSWORD        源仓库密码, 非必填; 支持多个用 '|' 分隔，顺序对应 SOURCE_REGISTRY_URLS"
}

ENV_VARS=""

for arg in "$@"; do
    [ "$arg" = "--" ] || continue
    echo "Invalid option: --" >&2
    exit 1
done

while getopts "hc:s:t:e:" opt; do
    case "$opt" in
        h)
            __HELP__
            exit 0
            ;;
        c)
            IMAGES_FILE="$OPTARG"
            ;;
        s)
            HUB_IMAGE_TAG="$OPTARG"
            ;;
        t)
            NEW_IMAGE_TAG="$OPTARG"
            ;;
        e)
            ENV_VARS="$OPTARG"
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

[ $# -eq 0 ] || {
    echo "Invalid argument: $1" >&2
    exit 1
}

if [ -f "${BASEDIR}/.env" ]; then
    __SAY__ info "检查到环境变量配置文件(${BASEDIR}/.env),开始加载..."
    # shellcheck disable=SC1091
    source "${BASEDIR}/.env"
fi

load_env_overrides "$ENV_VARS"

precheck
main
print_summary
[ "$SYNC_FAILED_COUNT" -eq 0 ]
