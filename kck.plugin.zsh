# kck - Kubernetes 配置管理工具
#
# Usage:
#   kck [--list|-l]                 显示所有可用配置
#   kck <配置名>                     切换到指定配置（仅设置环境变量）
#   kck [--set-default|-d] <配置名>  切换配置并设置为默认（修改软链接）
#   kck --current|-c                显示当前激活的配置
#   kck --help|-h                   显示此帮助信息

# Add completion to fpath
local _kck_fn_dir="${0:A:h}/functions"
(( ${fpath[(Ie)$_kck_fn_dir]} )) || fpath=("$_kck_fn_dir" $fpath)

# Register completion if compinit has already run (late-load scenario)
if (( $+functions[compdef] )); then
  autoload -Uz _kck
  compdef _kck kck
fi

_kck_log_info() {
    printf "\033[32m%s\033[0m\n" "$*"
}

_kck_log_error() {
    printf "\033[31m%s\033[0m\n" "$*"
}

_kck_help() {
    cat << 'EOF'
kck - Kubernetes 配置管理工具

用法:
  kck [--list|-l]                 显示所有可用配置
  kck <配置名>                     切换到指定配置（仅设置环境变量）
  kck [--set-default|-d] <配置名>  切换配置并设置为默认（修改软链接）
  kck --current|-c                显示当前激活的配置
  kck --help|-h                   显示此帮助信息

示例:
  kck                            # 列出所有配置
  kck production                 # 临时切换到 production 配置
  kck --set-default production   # 切换到 production 并设为默认
  kck --current                  # 显示当前配置

符号说明:
  >  当前激活的配置（绿色高亮）
  *  config 软链接指向的配置
EOF
}

_kck_get_current_name() {
    local kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"

    if [ ! -e "$kubeconfig" ]; then
        if [ "$1" = "--log" ]; then
            echo
            _kck_log_error "错误: 当前配置文件 $kubeconfig 不存在" >&2
            return 1
        fi
        return
    fi

    if [ -L "$kubeconfig" ]; then
        local target
        target=$(readlink "$kubeconfig")
        basename "$target" .kubeconfig
    else
        basename "$kubeconfig" .kubeconfig
    fi
}

_kck_get_config_link_name() {
    local kubeconfig_default="${HOME}/.kube/config"
    local target

    if [ -L "$kubeconfig_default" ]; then
        target="$(readlink "$kubeconfig_default")"
        basename "$target" .kubeconfig
    else
        echo ""
    fi
}

_kck_get_max_name_length() {
    local kube_dir="$1"
    local max_length=0
    local name
    local length

    for file in "$kube_dir"/*.kubeconfig "$kube_dir"/config; do
        [ -f "$file" ] || continue

        name="$(basename "$file" .kubeconfig)"
        length="${#name}"

        if (( length > max_length )); then
            max_length=$length
        fi
    done

    echo "$max_length"
}



_kck_list() {
    # Zsh 兼容：防止无 *.kubeconfig 时报错
    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt local_options null_glob
    else
        local nullglob_was_set=0
        shopt -q nullglob && nullglob_was_set=1
        shopt -s nullglob
    fi

    local kube_dir="${HOME}/.kube"
    local kubeconfig_default="${kube_dir}/config"

    if [ ! -d "$kube_dir" ]; then
        echo "错误: $kube_dir 目录不存在" >&2
        return 1
    fi

    local current_name
    if ! current_name=$(_kck_get_current_name); then
        return 1
    fi

    local config_link_name
    config_link_name=$(_kck_get_config_link_name)

    local max_length
    max_length=$(_kck_get_max_name_length "$kube_dir")

    local configs=()
    local file config

    for file in "$kube_dir"/*.kubeconfig; do
        [ -f "$file" ] && configs+=("${file##*/}")
    done

    # Bash 下恢复 nullglob 状态
    if [ -z "${ZSH_VERSION:-}" ] && (( ! nullglob_was_set )); then
        shopt -u nullglob
    fi

    if [ -f "$kubeconfig_default" ] && [ ! -L "$kubeconfig_default" ]; then
        configs+=("config")
    fi

    if (( ${#configs[@]} == 0 )); then
        echo "未找到任何 kubeconfig 文件" >&2
        return 1
    fi

    echo "可用的 Kubernetes 配置:"
    echo

    local name formatted_name file_path prefix suffix use_color
    for config in "${configs[@]}"; do
        name="${config%.kubeconfig}"
        file_path="${kube_dir}/${config}"
        prefix="  "
        suffix=""
        use_color=false

        printf -v formatted_name "%-${max_length}s" "$name"

        if [ "$current_name" = "$name" ]; then
            prefix="> "
            use_color=true
        fi

        if [ -n "$config_link_name" ] && [ "$config_link_name" = "$name" ]; then
            suffix=" *"
        fi

        if [ "$use_color" = true ]; then
            _kck_log_info "${prefix}${formatted_name} ${file_path}${suffix}"
        else
            echo "${prefix}${formatted_name} ${file_path}${suffix}"
        fi
    done

    if [ -z "$current_name" ]; then
        _kck_get_current_name --log
    fi
}

_kck_switch() {
    local kube_dir="${HOME}/.kube"
    local kubeconfig_default="${kube_dir}/config"
    local set_default=false
    local target_name

    if [ "$1" = "--set-default" ] || [ "$1" = "-d" ]; then
        set_default=true
        target_name="$2"
    else
        target_name="$1"
    fi

    if [ -z "$target_name" ]; then
        _kck_help
        return 1
    fi

    if [ "$2" = "--set-default" ]; then
        set_default=true
    fi

    local target_file=""

    if [ "$target_name" = "config" ] && [ -f "${kube_dir}/config.kubeconfig" ]; then
        target_file="${kube_dir}/config.kubeconfig"
    elif [ -f "${kube_dir}/${target_name}.kubeconfig" ]; then
        target_file="${kube_dir}/${target_name}.kubeconfig"
    elif [ "$target_name" = "config" ] && [ -f "$kubeconfig_default" ]; then
        target_file="$kubeconfig_default"
    else
        echo "错误: 找不到配置 '${target_name}'" >&2
        echo "使用 kck --list 查看可用配置" >&2
        return 1
    fi

    export KUBECONFIG="$target_file"
    _kck_log_info "已设置环境变量 KUBECONFIG: ${target_file}"

    if [ "$set_default" = true ]; then
        if [ ! "$target_file" = "$kubeconfig_default" ]; then
            if [ -L "$kubeconfig_default" ] || [ ! -e "$kubeconfig_default" ]; then
                ln -sf "$target_file" "$kubeconfig_default"
                _kck_log_info "已设置默认配置软链接: ${target_name}"
            else
                echo "警告: ${kubeconfig_default} 是普通文件，无法创建软链接" >&2
                echo "请手动备份并删除该文件，然后重试" >&2
                return 1
            fi
        else
            _kck_log_info "目标配置就是默认配置文件，无需创建软链接"
        fi
    fi
}

_kck_current() {
    local kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"

    if [ ! -e "$kubeconfig" ]; then
        _kck_log_error "错误: 当前配置文件 $kubeconfig 不存在" >&2
        return 1
    fi

    local name
    if [ -L "$kubeconfig" ]; then
        local target
        target=$(readlink "$kubeconfig")
        name=$(basename "$target" .kubeconfig)
    else
        name=$(basename "$kubeconfig" .kubeconfig)
    fi

    _kck_log_info "${name} ${kubeconfig}"
}

kck() {
    local first_arg="$1"
    local second_arg="$2"

    if [ $# -eq 0 ]; then
        _kck_list
        return $?
    fi

    case "$first_arg" in
        --list|-l)
            _kck_list
            return $?
            ;;
        --current|-c)
            _kck_current
            return $?
            ;;
        --help|-h)
            _kck_help
            return 0
            ;;
        --set-default|-d)
            _kck_switch "$first_arg" "$second_arg"
            return 0
            ;;
        -*)
            echo "错误: 未知选项 '$first_arg'" >&2
            _kck_help
            return 1
            ;;
        *)
            _kck_switch "$first_arg"
            ;;
    esac
}
