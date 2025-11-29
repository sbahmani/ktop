#!/bin/bash

# ktop - Kubernetes Node Resource Monitor
# Description: Display worker node resource allocation and usage with sorting options
# Version: 1.2.0
# Author: sbahmani

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# Version information
VERSION="1.3.0"

# Default settings (can be overridden by environment variables)
PARALLEL=${KTOP_PARALLEL:-8}
OUTPUT_FORMAT=${KTOP_FORMAT:-"table"}
SHOW_ALL=${KTOP_ALL:-false}
NO_COLOR=${KTOP_NO_COLOR:-false}
NO_SUM=${KTOP_NO_SUM:-false}
WATCH_INTERVAL=${KTOP_WATCH:-0}
SORT_BY=${KTOP_SORT:-"cpu-req"}  # Default sort by CPU requests
SORT_ORDER="desc"  # Default descending order
SHOW_CONDITIONS=${KTOP_SHOW_CONDITIONS:-false}  # Show detailed node conditions

# Help function
show_help() {
    echo -e "${BOLD}ktop - Kubernetes Worker Node Resource Monitor v${VERSION}${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    ktop [OPTIONS]"
    echo ""
    echo -e "${BOLD}DESCRIPTION:${NC}"
    echo "    Display Kubernetes worker nodes' CPU and memory allocation, usage, and capacity."
    echo "    Shows resource requests, limits, actual usage, percentages, and total capacity."
    echo ""
    echo -e "${BOLD}ENVIRONMENT VARIABLES:${NC}"
    echo "    KTOP_PARALLEL    Number of parallel queries (default: 8)"
    echo "    KTOP_FORMAT      Output format: table, csv, json (default: table)"
    echo "    KTOP_ALL         Include control-plane nodes (default: false)"
    echo "    KTOP_NO_COLOR    Disable color output (default: false)"
    echo "    KTOP_NO_SUM      Don't show summary totals (default: false)"
    echo "    KTOP_WATCH       Auto-refresh interval in seconds (default: 0)"
    echo "    KTOP_SORT        Default sort field (default: cpu-req)"
    echo "    KTOP_SHOW_CONDITIONS  Show detailed node conditions (default: false)"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help          Show this help message"
    echo "    -v, --version       Show version information"
    echo "    -P <num>            Number of parallel kubectl queries (default: 8)"
    echo "    -a, --all           Include control-plane nodes"
    echo "    -n, --no-color      Disable color output"
    echo "    -s, --no-sum        Don't show summary totals"
    echo "    -w, --watch <sec>   Auto-refresh every N seconds"
    echo "    -o, --output <fmt>  Output format: table (default), csv, json"
    echo "    -S, --sort <field>  Sort by field (default: cpu-req)"
    echo "    -r, --reverse       Reverse sort order (ascending)"
    echo "    -c, --show-conditions  Show detailed node conditions (Ready, MemoryPressure, etc.)"
    echo ""
    echo -e "${BOLD}SORT FIELDS:${NC}"
    echo "    name        Node name (alphabetical)"
    echo "    cpu-req     CPU requests (default)"
    echo "    cpu-lim     CPU limits"
    echo "    cpu-use     CPU usage"
    echo "    cpu-pct     CPU usage percentage"
    echo "    cpu-cap     CPU capacity"
    echo "    cpu-req-pct CPU requests percentage"
    echo "    mem-req     Memory requests"
    echo "    mem-lim     Memory limits"
    echo "    mem-use     Memory usage"
    echo "    mem-pct     Memory usage percentage"
    echo "    mem-cap     Memory capacity"
    echo "    mem-req-pct Memory requests percentage"
    echo "    pods        Total pod count"
    echo "    pods-ready  Ready pod count"
    echo "    status      Node status/conditions"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    ktop                        # Default: sort by CPU requests"
    echo "    ktop -S cpu-use             # Sort by CPU usage"
    echo "    ktop -S mem-pct             # Sort by memory usage percentage"
    echo "    ktop -S name -r             # Sort by name ascending"
    echo "    ktop --sort cpu-pct         # Sort by CPU percentage"
    echo "    ktop -S mem-use --all       # Sort by memory usage, include control-plane"
    echo "    ktop -S cpu-use -w 5        # Sort by CPU usage, refresh every 5s"
    echo "    ktop -P 12 -S cpu-pct       # Use 12 parallel queries, sort by CPU%"
    echo ""
    echo -e "${BOLD}OUTPUT COLUMNS:${NC}"
    echo "    WORKER_NODE    Node name"
    echo "    STATUS         Node health status (Ready/NotReady and conditions)"
    echo "    PODS           Total number of pods on the node"
    echo "    PODS_READY     Ready pods (format: ready/total)"
    echo "    CPU_REQ        CPU requests allocated to pods"
    echo "    CPU_LIM        CPU limits allocated to pods"
    echo "    CPU_USE        Actual CPU usage"
    echo "    CPU_%          CPU usage percentage of node capacity"
    echo "    CPU_CAP        Total CPU capacity (cores)"
    echo "    CPU_REQ_%      CPU requests percentage of node capacity"
    echo "    MEM_REQ        Memory requests allocated to pods (Gi)"
    echo "    MEM_LIM        Memory limits allocated to pods (Gi)"
    echo "    MEM_USE        Actual memory usage (Gi)"
    echo "    MEM_%          Memory usage percentage of node capacity"
    echo "    MEM_CAP        Total memory capacity (Gi)"
    echo "    MEM_REQ_%      Memory requests percentage of node capacity"
    echo ""
    echo -e "${BOLD}COLOR CODING:${NC}"
    echo -e "    ${GREEN}Green${NC}   0-59%  - Normal usage"
    echo -e "    ${YELLOW}Yellow${NC}  60-79% - Medium usage"
    echo -e "    ${RED}Red${NC}     80%+   - High usage"
    echo ""
    echo -e "${BOLD}NODE STATUS:${NC}"
    echo -e "    ${GREEN}Ready${NC}        Node is healthy and ready"
    echo -e "    ${RED}NotReady${NC}      Node is not ready"
    echo -e "    ${YELLOW}Pressure${NC}      Node has resource pressure (Memory/Disk/PID)"
    echo "    Use --show-conditions to see detailed condition information"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -P)
            if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 50 ]]; then
                echo "Error: -P requires a numeric value between 1 and 50"
                exit 1
            fi
            PARALLEL="$2"
            shift 2
            ;;
        -a|--all)
            SHOW_ALL=true
            shift
            ;;
        -n|--no-color)
            NO_COLOR=true
            RED=''; YELLOW=''; GREEN=''; BOLD=''; NC=''
            shift
            ;;
        -s|--no-sum)
            NO_SUM=true
            shift
            ;;
        -v|--version)
            echo "ktop version ${VERSION}"
            exit 0
            ;;
        -w|--watch)
            if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]]; then
                echo "Error: -w requires a positive numeric value (seconds)"
                exit 1
            fi
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -o|--output)
            if [[ ! "$2" =~ ^(table|csv|json)$ ]]; then
                echo "Error: Output format must be: table, csv, or json"
                exit 1
            fi
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -S|--sort)
            if [[ ! "$2" =~ ^(name|cpu-req|cpu-lim|cpu-use|cpu-pct|cpu-cap|cpu-req-pct|mem-req|mem-lim|mem-use|mem-pct|mem-cap|mem-req-pct|pods|pods-ready|status)$ ]]; then
                echo "Error: Invalid sort field. Use 'ktop -h' to see valid options"
                exit 1
            fi
            SORT_BY="$2"
            shift 2
            ;;
        -r|--reverse)
            SORT_ORDER="asc"
            shift
            ;;
        -c|--show-conditions)
            SHOW_CONDITIONS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use 'ktop -h' for help"
            exit 1
            ;;
    esac
done

# Function to retry kubectl commands with better error handling
kubectl_with_retry() {
    local max_retries=3
    local retry_count=0
    local delay=2
    local output
    local error_output
    local quiet_mode=${KTOP_QUIET_RETRY:-false}
    
    while [[ $retry_count -lt $max_retries ]]; do
        if output=$(kubectl "$@" 2>/dev/null); then
            echo "$output"
            return 0
        else
            error_output=$(kubectl "$@" 2>&1)
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            # Suppress retry warnings for:
            # - Node-level operations (get node, describe node, top node)
            # - Pod operations during parallel processing
            # - When in quiet mode
            local suppress_warning=false
            if [[ "$quiet_mode" == "true" ]] || \
               [[ "$*" == *"get nodes"* ]] || \
               [[ "$*" == *"top nodes"* ]] || \
               [[ "$*" == *"get node"* ]] || \
               [[ "$*" == *"describe node"* ]] || \
               [[ "$*" == *"top node"* ]] || \
               [[ "$*" == *"get pods"* ]]; then
                suppress_warning=true
            fi
            
            if [[ "$suppress_warning" == "false" ]]; then
                echo "Warning: kubectl command failed, retrying in ${delay}s... (attempt ${retry_count}/${max_retries})" >&2
            fi
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
    done
    
    # Only show final error if it's a critical operation or not in quiet mode
    local suppress_error=false
    if [[ "$quiet_mode" == "true" ]] || \
       [[ "$*" == *"get node"* ]] || \
       [[ "$*" == *"describe node"* ]] || \
       [[ "$*" == *"top node"* ]] || \
       [[ "$*" == *"get pods"* ]]; then
        suppress_error=true
    fi
    
    if [[ "$suppress_error" == "false" ]]; then
        echo "Error: kubectl command failed after ${max_retries} attempts: $error_output" >&2
    fi
    return 1
}

# Function to validate environment variables
validate_env_vars() {
    # Validate PARALLEL
    if [[ ! "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -lt 1 ]] || [[ "$PARALLEL" -gt 50 ]]; then
        echo "Warning: Invalid KTOP_PARALLEL value '$PARALLEL', using default 8"
        PARALLEL=8
    fi
    
    # Validate OUTPUT_FORMAT
    if [[ ! "$OUTPUT_FORMAT" =~ ^(table|csv|json)$ ]]; then
        echo "Warning: Invalid KTOP_FORMAT value '$OUTPUT_FORMAT', using default 'table'"
        OUTPUT_FORMAT="table"
    fi
    
    # Validate boolean variables
    if [[ "$SHOW_ALL" != "true" ]] && [[ "$SHOW_ALL" != "false" ]]; then
        echo "Warning: Invalid KTOP_ALL value '$SHOW_ALL', using default 'false'"
        SHOW_ALL=false
    fi
    
    if [[ "$NO_COLOR" != "true" ]] && [[ "$NO_COLOR" != "false" ]]; then
        echo "Warning: Invalid KTOP_NO_COLOR value '$NO_COLOR', using default 'false'"
        NO_COLOR=false
    fi
    
    if [[ "$NO_SUM" != "true" ]] && [[ "$NO_SUM" != "false" ]]; then
        echo "Warning: Invalid KTOP_NO_SUM value '$NO_SUM', using default 'false'"
        NO_SUM=false
    fi
    
    # Validate WATCH_INTERVAL
    if [[ ! "$WATCH_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$WATCH_INTERVAL" -lt 0 ]]; then
        echo "Warning: Invalid KTOP_WATCH value '$WATCH_INTERVAL', using default 0"
        WATCH_INTERVAL=0
    fi
    
    # Validate SORT_BY
    if [[ ! "$SORT_BY" =~ ^(name|cpu-req|cpu-lim|cpu-use|cpu-pct|cpu-cap|cpu-req-pct|mem-req|mem-lim|mem-use|mem-pct|mem-cap|mem-req-pct|pods|pods-ready|status)$ ]]; then
        echo "Warning: Invalid KTOP_SORT value '$SORT_BY', using default 'cpu-req'"
        SORT_BY="cpu-req"
    fi
    
    # Validate boolean variables
    if [[ "$SHOW_CONDITIONS" != "true" ]] && [[ "$SHOW_CONDITIONS" != "false" ]]; then
        echo "Warning: Invalid KTOP_SHOW_CONDITIONS value '$SHOW_CONDITIONS', using default 'false'"
        SHOW_CONDITIONS=false
    fi
}

# Check dependencies
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed or not in PATH"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "Error: bc is not installed or not in PATH"
    exit 1
fi

# Validate environment variables
validate_env_vars

# Check kubectl access
if ! kubectl_with_retry get nodes &> /dev/null; then
    echo "Error: Cannot access Kubernetes cluster. Check your kubeconfig and cluster connectivity."
    echo "Try: kubectl cluster-info"
    exit 1
fi

# Check metrics-server
if ! kubectl_with_retry top nodes &> /dev/null; then
    echo "Error: metrics-server is not installed or not working properly."
    echo "Install with: kubectl apply -f https://github.com/kubernetes-metrics/metrics-server/releases/latest/download/components.yaml"
    echo "Wait a few minutes for metrics-server to start collecting metrics."
    exit 1
fi

# Function to convert bytes/various formats to Gi
to_gi() {
    local value=$1
    
    # Handle corrupted memory values with 'm' suffix (Kubernetes bug)
    if [[ $value =~ ^[0-9]+m$ ]]; then
        local num_value=${value%m}
        # If it's a very large number (>10 digits), it's likely corrupted memory in bytes
        if [[ ${#num_value} -gt 10 ]]; then
            # Convert bytes to Gi
            local gi_value=$(echo "$num_value" | awk '{printf "%.1f", $1 / (1024*1024*1024)}')
            # Sanity check - if > 1000Gi, it's definitely corrupted
            if (( $(echo "$gi_value > 1000" | bc -l 2>/dev/null || echo 0) )); then
                echo "ERR"  # Mark as error to trigger pod calculation
                return
            fi
            echo "$gi_value"
            return
        else
            # Small number with 'm' - likely CPU millicores
            echo "0"
            return
        fi
    fi
    
    if [[ -z "$value" ]] || [[ "$value" == "0" ]]; then
        echo "0"
    elif [[ $value =~ ^[0-9]+$ ]]; then
        # Plain number - assume bytes and convert to Gi
        local gi_value=$(echo "$value" | awk '{printf "%.1f", $1 / (1024*1024*1024)}')
        # Sanity check
        if (( $(echo "$gi_value > 1000" | bc -l 2>/dev/null || echo 0) )); then
            echo "ERR"  # Mark as error
        else
            echo "$gi_value"
        fi
    elif [[ $value == *"Ti" ]]; then
        local num=${value%Ti}
        echo "$num" | awk '{printf "%.1f", $1 * 1024}'
    elif [[ $value == *"Gi" ]]; then
        echo "${value%Gi}"
    elif [[ $value == *"Mi" ]]; then
        local mi=${value%Mi}
        echo "$mi" | awk '{printf "%.1f", $1 / 1024}'
    elif [[ $value == *"Ki" ]]; then
        local ki=${value%Ki}
        echo "$ki" | awk '{printf "%.1f", $1 / (1024*1024)}'
    else
        echo "0"
    fi
}

# Function to convert Mi to Gi
mi_to_gi() {
    local mi=$1
    mi=${mi%Mi}  # Remove Mi suffix if present
    
    if [[ -z "$mi" ]] || [[ "$mi" == "0" ]]; then
        echo "0"
    else
        echo "$mi" | awk '{printf "%.1f", $1 / 1024}'
    fi
}

# Function to calculate memory requests from pods
calculate_mem_from_pods() {
    local node=$1
    
    kubectl_with_retry get pods --all-namespaces --field-selector spec.nodeName=$node -o json | \
        jq -r '[.items[].spec.containers[].resources.requests.memory // "0"] | 
            map(
                if test("Ti$") then (. | rtrimstr("Ti") | tonumber * 1024)
                elif test("Gi$") then (. | rtrimstr("Gi") | tonumber)
                elif test("Mi$") then (. | rtrimstr("Mi") | tonumber / 1024)
                elif test("Ki$") then (. | rtrimstr("Ki") | tonumber / 1024 / 1024)
                elif test("^[0-9]+$") then (. | tonumber / 1024 / 1024 / 1024)
                else 0 end
            ) | add // 0' | \
        awk '{printf "%.1f", $1}'
}

# Function to calculate memory limits from pods
calculate_mem_limits_from_pods() {
    local node=$1
    
    kubectl_with_retry get pods --all-namespaces --field-selector spec.nodeName=$node -o json | \
        jq -r '[.items[].spec.containers[].resources.limits.memory // "0"] | 
            map(
                if test("Ti$") then (. | rtrimstr("Ti") | tonumber * 1024)
                elif test("Gi$") then (. | rtrimstr("Gi") | tonumber)
                elif test("Mi$") then (. | rtrimstr("Mi") | tonumber / 1024)
                elif test("Ki$") then (. | rtrimstr("Ki") | tonumber / 1024 / 1024)
                elif test("^[0-9]+$") then (. | tonumber / 1024 / 1024 / 1024)
                else 0 end
            ) | add // 0' | \
        awk '{printf "%.1f", $1}'
}

# Function to get pod count and ready pod count for a node
get_pod_counts() {
    local node=$1
    
    # Get pods for this node
    local pods_json=$(kubectl_with_retry get pods --all-namespaces --field-selector spec.nodeName=$node -o json 2>/dev/null)
    
    if [[ -z "$pods_json" ]] || [[ "$pods_json" == "null" ]]; then
        echo "0|0"
        return
    fi
    
    # Count total pods
    local total_pods=$(echo "$pods_json" | jq -r '.items | length' 2>/dev/null || echo "0")
    
    # Count ready pods (pods where all containers are ready)
    local ready_pods=$(echo "$pods_json" | jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
    
    echo "${total_pods}|${ready_pods}"
}

# Function to get node conditions and status
get_node_status() {
    local node_json=$1
    local ready_status="Unknown"
    local conditions_summary=""
    local status_code=0  # 0=Ready, 1=NotReady, 2=Pressure
    
    # Get all conditions in one jq call (faster than multiple calls)
    local conditions=$(echo "$node_json" | jq -r '.status.conditions[] | "\(.type)|\(.status)"' 2>/dev/null)
    
    # Get Ready condition
    local ready_condition=$(echo "$conditions" | grep "^Ready|" | cut -d'|' -f2)
    
    if [[ "$ready_condition" == "True" ]]; then
        ready_status="Ready"
        status_code=0
    elif [[ "$ready_condition" == "False" ]]; then
        ready_status="NotReady"
        status_code=1
    else
        ready_status="Unknown"
        status_code=1
    fi
    
    # Check for pressure conditions if showing detailed conditions
    if [[ "$SHOW_CONDITIONS" == "true" ]]; then
        local pressures=()
        
        # Use pre-parsed conditions data (faster than multiple jq calls)
        local mem_pressure=$(echo "$conditions" | grep "^MemoryPressure|" | cut -d'|' -f2)
        if [[ "$mem_pressure" == "True" ]]; then
            pressures+=("Mem")
            status_code=2
        fi
        
        local disk_pressure=$(echo "$conditions" | grep "^DiskPressure|" | cut -d'|' -f2)
        if [[ "$disk_pressure" == "True" ]]; then
            pressures+=("Disk")
            status_code=2
        fi
        
        local pid_pressure=$(echo "$conditions" | grep "^PIDPressure|" | cut -d'|' -f2)
        if [[ "$pid_pressure" == "True" ]]; then
            pressures+=("PID")
            status_code=2
        fi
        
        local net_unavailable=$(echo "$conditions" | grep "^NetworkUnavailable|" | cut -d'|' -f2)
        if [[ "$net_unavailable" == "True" ]]; then
            pressures+=("Net")
            status_code=2
        fi
        
        # Build conditions summary
        if [[ ${#pressures[@]} -gt 0 ]]; then
            conditions_summary="${ready_status}($(IFS=','; echo "${pressures[*]}"))"
        else
            conditions_summary="$ready_status"
        fi
    else
        conditions_summary="$ready_status"
    fi
    
    echo "$status_code|$conditions_summary"
}

# Process function
process_node() {
    local node=$1
    
    # Extract node JSON from pre-fetched all nodes data file (much faster than per-node query)
    local node_json=""
    if [[ -n "$NODES_JSON_FILE" ]] && [[ -f "$NODES_JSON_FILE" ]]; then
        node_json=$(jq -r --arg node "$node" '.items[] | select(.metadata.name == $node)' "$NODES_JSON_FILE" 2>/dev/null)
    fi
    
    # Fallback to per-node query if not found in batch data
    if [[ -z "$node_json" ]] || [[ "$node_json" == "null" ]]; then
        node_json=$(kubectl_with_retry get node $node -o json 2>/dev/null)
    fi
    
    if [[ -z "$node_json" ]] || [[ "$node_json" == "null" ]]; then
        # If kubectl fails, return default values
        echo "0|$node|0m|0m|0m|0|0|0|0|0|0|0|0|0|1|Unknown|0|0"
        return
    fi
    
    # Get node status and conditions
    local status_info=$(get_node_status "$node_json")
    local status_code=$(echo "$status_info" | cut -d'|' -f1)
    local status_text=$(echo "$status_info" | cut -d'|' -f2)
    
    # Extract capacity data in one jq call (faster than multiple calls)
    local capacity_data=$(echo "$node_json" | jq -r '.status.allocatable | "\(.cpu)|\(.memory)"' 2>/dev/null)
    local cpu_capacity=$(echo "$capacity_data" | cut -d'|' -f1)
    local mem_capacity=$(echo "$capacity_data" | cut -d'|' -f2)
    
    # Convert CPU capacity to cores
    local cpu_total
    if [[ $cpu_capacity == *"m" ]]; then
        cpu_total=$(echo "${cpu_capacity%m}" | awk '{printf "%.1f", $1 / 1000}')
    else
        cpu_total=$cpu_capacity
    fi
    
    # Convert memory capacity to Gi
    local mem_total_gi=$(to_gi "$mem_capacity")
    
    # Handle ERR values for memory capacity
    if [[ "$mem_total_gi" == "ERR" ]]; then
        # Try to get memory from status.capacity instead of allocatable
        mem_capacity=$(echo "$node_json" | jq -r '.status.capacity.memory')
        mem_total_gi=$(to_gi "$mem_capacity")
        
        # If still error, set to 0
        if [[ "$mem_total_gi" == "ERR" ]]; then
            mem_total_gi="0"
        fi
    fi
    
    # Get allocated resources from describe
    # Note: Allocated resources are not stored in node JSON, only in describe output
    local describe=$(kubectl_with_retry describe node $node 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$describe" ]]; then
        # If describe fails, use default values
        cpu_req_raw="0m"
        cpu_lim_raw="0m"
        mem_req_raw="0"
        mem_lim_raw="0"
    else
        local allocated=$(echo "$describe" | grep -A 10 "Allocated resources:")
        
        # Extract CPU line
        local cpu_line=$(echo "$allocated" | grep "cpu" | head -1)
        cpu_req_raw=$(echo "$cpu_line" | awk '{print $2}')
        cpu_lim_raw=$(echo "$cpu_line" | awk '{print $4}')
        
        # Extract Memory line
        local mem_line=$(echo "$allocated" | grep "memory" | head -1)
        mem_req_raw=$(echo "$mem_line" | awk '{print $2}')
        mem_lim_raw=$(echo "$mem_line" | awk '{print $4}')
    fi
    
    # Default values if empty
    cpu_req=${cpu_req_raw:-0m}
    cpu_lim=${cpu_lim_raw:-0m}
    mem_req_raw=${mem_req_raw:-0}
    mem_lim_raw=${mem_lim_raw:-0}
    
    # Convert memory request to Gi
    local mem_req_gi=$(to_gi "$mem_req_raw")
    
    # If memory request conversion resulted in error or unreasonable value, calculate from pods
    if [[ "$mem_req_gi" == "ERR" ]] || [[ "$mem_req_raw" =~ ^[0-9]+m$ && ${#mem_req_raw} -gt 10 ]]; then
        mem_req_gi=$(calculate_mem_from_pods "$node")
    fi
    
    # Convert memory limit to Gi
    local mem_lim_gi=$(to_gi "$mem_lim_raw")
    
    # Only calculate from pods if the conversion resulted in an error (corrupted data)
    # If limit is 0, that's likely accurate - many pods don't set memory limits in Kubernetes
    # This avoids expensive pod queries for every node
    if [[ "$mem_lim_gi" == "ERR" ]]; then
        # Corrupted data - try to calculate from pods as fallback
        mem_lim_gi=$(calculate_mem_limits_from_pods "$node")
        [[ -z "$mem_lim_gi" ]] && mem_lim_gi="0"
    fi
    
    # Get actual usage from pre-fetched top data (much faster than per-node query)
    local top_line=$(echo "$TOP_DATA" | grep "^$node " | head -1)
    if [[ -n "$top_line" ]]; then
        local cpu_use=$(echo "$top_line" | awk '{print $2}')
        local cpu_use_pct=$(echo "$top_line" | awk '{print $3}' | tr -d '%')
        local mem_use_mi=$(echo "$top_line" | awk '{print $4}')
        local mem_use_pct=$(echo "$top_line" | awk '{print $5}' | tr -d '%')
    else
        # Fallback to per-node query if not in batch data
        local top=$(kubectl_with_retry top node $node --no-headers 2>/dev/null)
        if [[ -n "$top" ]]; then
            cpu_use=$(echo "$top" | awk '{print $2}')
            cpu_use_pct=$(echo "$top" | awk '{print $3}' | tr -d '%')
            mem_use_mi=$(echo "$top" | awk '{print $4}')
            mem_use_pct=$(echo "$top" | awk '{print $5}' | tr -d '%')
        else
            cpu_use="0m"
            cpu_use_pct="0"
            mem_use_mi="0Mi"
            mem_use_pct="0"
        fi
    fi
    
    # Default values if empty
    cpu_use=${cpu_use:-0m}
    cpu_use_pct=${cpu_use_pct:-0}
    mem_use_mi=${mem_use_mi:-0Mi}
    mem_use_pct=${mem_use_pct:-0}
    
    # Convert memory usage to Gi
    local mem_use_gi=$(mi_to_gi "$mem_use_mi")
    
    # Prepare sort values
    local cpu_req_m=${cpu_req%m}
    local cpu_lim_m=${cpu_lim%m}
    local cpu_use_m=${cpu_use%m}
    [[ -z "$cpu_req_m" ]] && cpu_req_m=0
    [[ -z "$cpu_lim_m" ]] && cpu_lim_m=0
    [[ -z "$cpu_use_m" ]] && cpu_use_m=0
    
    # Ensure all memory values are numeric (not "ERR")
    [[ "$mem_req_gi" == "ERR" ]] && mem_req_gi="0"
    [[ "$mem_lim_gi" == "ERR" ]] && mem_lim_gi="0"
    [[ "$mem_use_gi" == "ERR" ]] && mem_use_gi="0"
    [[ "$mem_total_gi" == "ERR" ]] && mem_total_gi="0"
    
    # Calculate CPU request percentage
    local cpu_req_pct="0"
    if [[ "$cpu_total" != "0" ]] && [[ "$cpu_total" != "" ]]; then
        cpu_req_pct=$(echo "scale=1; ($cpu_req_m * 100) / ($cpu_total * 1000)" | bc 2>/dev/null || echo "0")
    fi
    
    # Calculate Memory request percentage
    local mem_req_pct="0"
    if [[ "$mem_total_gi" != "0" ]] && [[ "$mem_total_gi" != "" ]]; then
        mem_req_pct=$(echo "scale=1; ($mem_req_gi * 100) / $mem_total_gi" | bc 2>/dev/null || echo "0")
    fi
    
    # Get pod counts
    local pod_counts=$(get_pod_counts "$node")
    local total_pods=$(echo "$pod_counts" | cut -d'|' -f1)
    local ready_pods=$(echo "$pod_counts" | cut -d'|' -f2)
    [[ -z "$total_pods" ]] && total_pods=0
    [[ -z "$ready_pods" ]] && ready_pods=0
    
    # Determine sort value
    local sort_value
    case "$SORT_BY" in
        name)       sort_value="$node" ;;
        cpu-req)    sort_value=$(printf "%010d" $cpu_req_m) ;;
        cpu-lim)    sort_value=$(printf "%010d" $cpu_lim_m) ;;
        cpu-use)    sort_value=$(printf "%010d" $cpu_use_m) ;;
        cpu-pct)    sort_value=$(printf "%010d" ${cpu_use_pct:-0}) ;;
        cpu-cap)    sort_value=$(printf "%010.1f" ${cpu_total:-0}) ;;
        cpu-req-pct) sort_value=$(printf "%010.1f" ${cpu_req_pct:-0}) ;;
        mem-req)    sort_value=$(printf "%010.1f" ${mem_req_gi:-0}) ;;
        mem-lim)    sort_value=$(printf "%010.1f" ${mem_lim_gi:-0}) ;;
        mem-use)    sort_value=$(printf "%010.1f" ${mem_use_gi:-0}) ;;
        mem-pct)    sort_value=$(printf "%010d" ${mem_use_pct:-0}) ;;
        mem-cap)    sort_value=$(printf "%010.1f" ${mem_total_gi:-0}) ;;
        mem-req-pct) sort_value=$(printf "%010.1f" ${mem_req_pct:-0}) ;;
        pods)       sort_value=$(printf "%010d" ${total_pods:-0}) ;;
        pods-ready) sort_value=$(printf "%010d" ${ready_pods:-0}) ;;
        status)     sort_value=$(printf "%010d" $status_code) ;;
        *)          sort_value=$(printf "%010d" $cpu_req_m) ;;
    esac
    
    echo "$sort_value|$node|$cpu_req|$cpu_lim|$cpu_use|$cpu_use_pct|$cpu_total|$mem_req_gi|$mem_lim_gi|$mem_use_gi|$mem_use_pct|$mem_total_gi|$cpu_req_pct|$mem_req_pct|$status_code|$status_text|$total_pods|$ready_pods"
}

# Main display function
display_resources() {
    # Show sort info if not default
    if [[ "$SORT_BY" != "cpu-req" ]] || [[ "$SORT_ORDER" == "asc" ]]; then
        echo -e "${BOLD}Sorted by: ${SORT_BY} (${SORT_ORDER}ending)${NC}"
    fi
    
    # Show configuration info in verbose mode
    if [[ "${KTOP_VERBOSE:-false}" == "true" ]]; then
        echo -e "${BOLD}Configuration:${NC} Parallel: ${PARALLEL}, Format: ${OUTPUT_FORMAT}, All nodes: ${SHOW_ALL}"
    fi
    
    # Prepare data
    temp_file=$(mktemp)
    
    export -f process_node
    export -f to_gi
    export -f mi_to_gi
    export -f calculate_mem_from_pods
    export -f calculate_mem_limits_from_pods
    export -f get_pod_counts
    export -f kubectl_with_retry
    export -f get_node_status
    export SORT_BY
    export SHOW_CONDITIONS
    export KTOP_QUIET_RETRY=true  # Suppress retry warnings during parallel processing
    export TOP_DATA  # Pre-fetched top data for all nodes
    export NODES_JSON_FILE  # Temp file with pre-fetched JSON for all nodes
    
    # Selector for nodes
    if [[ "$SHOW_ALL" == true ]]; then
        SELECTOR=""
    else
        SELECTOR="--selector=!node-role.kubernetes.io/control-plane"
    fi
    
    # Get all node usage data at once (much faster than per-node queries)
    local top_data=$(kubectl_with_retry top nodes $SELECTOR --no-headers 2>/dev/null)
    export TOP_DATA="$top_data"
    
    # Get all nodes JSON at once and save to temp file (avoids "argument list too long" error)
    local nodes_json_file=$(mktemp)
    kubectl_with_retry get nodes $SELECTOR -o json > "$nodes_json_file" 2>/dev/null
    export NODES_JSON_FILE="$nodes_json_file"
    
    # Get nodes and process in parallel
    kubectl_with_retry get nodes $SELECTOR -o name | \
        sed 's|node/||' | \
        xargs -P $PARALLEL -I {} bash -c 'process_node "$@"' _ {} > $temp_file
    
    # Clean up nodes JSON temp file
    rm -f "$nodes_json_file"
    
    # Initialize totals
    total_cpu_req=0
    total_cpu_lim=0
    total_cpu_use=0
    total_cpu_cap=0
    total_mem_req=0
    total_mem_lim=0
    total_mem_use=0
    total_mem_cap=0
    total_pods=0
    total_ready_pods=0
    node_count=0
    
    # Determine sort options
    if [[ "$SORT_BY" == "name" ]]; then
        SORT_CMD="sort -t'|' -k1"
    else
        SORT_CMD="sort -t'|' -k1 -n"
    fi
    
    if [[ "$SORT_ORDER" == "desc" ]]; then
        SORT_CMD="$SORT_CMD -r"
    fi
    
    # Output based on format
    case "$OUTPUT_FORMAT" in
        csv)
            echo "NODE,STATUS,PODS,PODS_READY,CPU_REQ,CPU_LIM,CPU_USE,CPU_%,CPU_TOTAL,CPU_REQ_%,MEM_REQ,MEM_LIM,MEM_USE,MEM_%,MEM_TOTAL,MEM_REQ_%"
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi cpu_req_pct mem_req_pct status_code status_text node_pods node_ready_pods; do
                if [[ "$node_pods" == "0" ]]; then
                    pods_ready_display="0/0"
                else
                    pods_ready_display="${node_ready_pods}/${node_pods}"
                fi
                echo "$node,$status_text,$node_pods,$pods_ready_display,$cpu_req,$cpu_lim,$cpu_use,$cpu_pct%,$cpu_total,$cpu_req_pct%,${mem_req_gi}Gi,${mem_lim_gi}Gi,${mem_use_gi}Gi,$mem_pct%,${mem_total_gi}Gi,$mem_req_pct%"
            done
            ;;
            
        json)
            echo "{"
            echo '  "timestamp": "'$(date -Iseconds)'",'
            echo '  "sort_by": "'$SORT_BY'",'
            echo '  "sort_order": "'$SORT_ORDER'",'
            echo '  "nodes": ['
            first=true
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi cpu_req_pct mem_req_pct status_code status_text node_pods node_ready_pods; do
                [[ "$first" == false ]] && echo ","
                echo -n '    {"name":"'$node'","status":"'$status_text'","status_code":'$status_code',"pods":'$node_pods',"pods_ready":'$node_ready_pods',"cpu_req":"'$cpu_req'","cpu_lim":"'$cpu_lim'","cpu_use":"'$cpu_use'","cpu_pct":'$cpu_pct',"cpu_total":'$cpu_total',"cpu_req_pct":'$cpu_req_pct',"mem_req_gi":'$mem_req_gi',"mem_lim_gi":'$mem_lim_gi',"mem_use_gi":'$mem_use_gi',"mem_pct":'$mem_pct',"mem_total_gi":'$mem_total_gi',"mem_req_pct":'$mem_req_pct'}'
                first=false
            done
            echo ""
            echo "  ]"
            echo "}"
            ;;
            
        table|*)
            # Header
            printf "%-24s    %-10s %-6s %-10s %-8s %-8s %-8s %-6s %-8s %-7s | %-8s %-8s %-8s %-6s %-8s %-6s\n" \
                "WORKER_NODE" "STATUS" "PODS" "PODS_READY" "CPU_REQ" "CPU_LIM" "CPU_USE" "CPU_%" "CPU_CAP" "CPU_REQ_%" "MEM_REQ" "MEM_LIM" "MEM_USE" "MEM_%" "MEM_CAP" "MEM_REQ_%"
            echo "=========================================================================================================================================================================="
            
            # Sort and display
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi cpu_req_pct mem_req_pct status_code status_text node_pods node_ready_pods; do
                # Update totals
                cpu_req_val=${cpu_req%m}
                cpu_lim_val=${cpu_lim%m}
                cpu_use_val=${cpu_use%m}
                [[ -z "$cpu_req_val" ]] && cpu_req_val=0
                [[ -z "$cpu_lim_val" ]] && cpu_lim_val=0
                [[ -z "$cpu_use_val" ]] && cpu_use_val=0
                
                total_cpu_req=$((total_cpu_req + cpu_req_val))
                total_cpu_lim=$((total_cpu_lim + cpu_lim_val))
                total_cpu_use=$((total_cpu_use + cpu_use_val))
                total_cpu_cap=$(echo "$total_cpu_cap + $cpu_total" | bc 2>/dev/null || echo $total_cpu_cap)
                total_mem_req=$(echo "$total_mem_req + $mem_req_gi" | bc 2>/dev/null || echo $total_mem_req)
                total_mem_lim=$(echo "$total_mem_lim + $mem_lim_gi" | bc 2>/dev/null || echo $total_mem_lim)
                total_mem_use=$(echo "$total_mem_use + $mem_use_gi" | bc 2>/dev/null || echo $total_mem_use)
                total_mem_cap=$(echo "$total_mem_cap + $mem_total_gi" | bc 2>/dev/null || echo $total_mem_cap)
                total_pods=$((total_pods + node_pods))
                total_ready_pods=$((total_ready_pods + node_ready_pods))
                node_count=$((node_count + 1))
                
                # Save totals to temp file (including pod counts)
                echo "$total_cpu_req $total_cpu_lim $total_cpu_use $total_cpu_cap $total_mem_req $total_mem_lim $total_mem_use $total_mem_cap $total_pods $total_ready_pods $node_count" > ${temp_file}.totals
                
                # Color code percentages and status
                if [[ "$NO_COLOR" == false ]]; then
                    if [[ ${cpu_pct%.*} -ge 80 ]]; then
                        cpu_color="${RED}"
                    elif [[ ${cpu_pct%.*} -ge 60 ]]; then
                        cpu_color="${YELLOW}"
                    else
                        cpu_color="${GREEN}"
                    fi
                    
                    if [[ ${mem_pct%.*} -ge 80 ]]; then
                        mem_color="${RED}"
                    elif [[ ${mem_pct%.*} -ge 60 ]]; then
                        mem_color="${YELLOW}"
                    else
                        mem_color="${GREEN}"
                    fi
                    
                    # Color code status
                    if [[ "$status_code" == "0" ]]; then
                        status_color="${GREEN}"
                    elif [[ "$status_code" == "1" ]]; then
                        status_color="${RED}"
                    elif [[ "$status_code" == "2" ]]; then
                        status_color="${YELLOW}"
                    else
                        status_color=""
                    fi
                else
                    cpu_color=""
                    mem_color=""
                    status_color=""
                fi
                
                # Format display values
                mem_req_display="${mem_req_gi}Gi"
                mem_lim_display="${mem_lim_gi}Gi"
                mem_use_display="${mem_use_gi}Gi"
                mem_cap_display="${mem_total_gi}Gi"
                
                # Format pod counts
                pods_display="$node_pods"
                if [[ "$node_pods" == "0" ]]; then
                    pods_ready_display="0/0"
                else
                    pods_ready_display="${node_ready_pods}/${node_pods}"
                fi
                
                # Truncate node name if too long (24 char column: 22 chars + ".." = 24)
                if [[ ${#node} -gt 24 ]]; then
                    node_display="${node:0:22}.."
                else
                    node_display="$node"
                fi
                
                # Truncate status text if too long
                if [[ ${#status_text} -gt 10 ]]; then
                    status_display="${status_text:0:9}.."
                else
                    status_display="$status_text"
                fi
                
                printf "%-24s    ${status_color}%-10s${NC} %-6s %-10s %-8s %-8s %-8s ${cpu_color}%-6s${NC} %-8s ${cpu_color}%-7s${NC}   | %-8s %-8s %-8s ${mem_color}%-6s${NC} %-8s ${mem_color}%-6s${NC}\n" \
                    "$node_display" "$status_display" "$pods_display" "$pods_ready_display" "$cpu_req" "$cpu_lim" "$cpu_use" "${cpu_pct}%" "$cpu_total" "${cpu_req_pct}%" \
                    "${mem_req_display:0:8}" "${mem_lim_display:0:8}" "${mem_use_display:0:8}" "${mem_pct}%" "${mem_cap_display:0:8}" "${mem_req_pct}%"
            done
            
            # Show totals unless disabled
            if [[ "$NO_SUM" == false ]] && [[ -f ${temp_file}.totals ]]; then
                read total_cpu_req total_cpu_lim total_cpu_use total_cpu_cap total_mem_req total_mem_lim total_mem_use total_mem_cap total_pods total_ready_pods node_count < ${temp_file}.totals
                
                echo "=========================================================================================================================================================================="
                
                # Format CPU totals
                if [[ $total_cpu_req -ge 1000 ]]; then
                    total_cpu_req_fmt="$(echo "scale=1; $total_cpu_req/1000" | bc 2>/dev/null)"
                else
                    total_cpu_req_fmt="${total_cpu_req}m"
                fi
                
                if [[ $total_cpu_lim -ge 1000 ]]; then
                    total_cpu_lim_fmt="$(echo "scale=1; $total_cpu_lim/1000" | bc 2>/dev/null)"
                else
                    total_cpu_lim_fmt="${total_cpu_lim}m"
                fi
                
                if [[ $total_cpu_use -ge 1000 ]]; then
                    total_cpu_use_fmt="$(echo "scale=1; $total_cpu_use/1000" | bc 2>/dev/null)"
                else
                    total_cpu_use_fmt="${total_cpu_use}m"
                fi
                
                # Format memory totals
                total_mem_req_fmt="${total_mem_req}Gi"
                total_mem_lim_fmt="${total_mem_lim}Gi"
                total_mem_use_fmt="${total_mem_use}Gi"
                total_mem_cap_fmt="${total_mem_cap}Gi"
                
                # Format pod totals
                total_pods_display="$total_pods"
                if [[ "$total_pods" == "0" ]]; then
                    total_pods_ready_display="0/0"
                else
                    total_pods_ready_display="${total_ready_pods}/${total_pods}"
                fi
                
                printf "${BOLD}%-24s    %-10s %-6s %-10s %-8s %-8s %-8s %-6s %-8s %-7s   | %-8s %-8s %-8s %-6s %-8s %-6s${NC}\n" \
                    "TOTAL ($node_count)" "-" "$total_pods_display" "$total_pods_ready_display" \
                    "${total_cpu_req_fmt:0:8}" "${total_cpu_lim_fmt:0:8}" "${total_cpu_use_fmt:0:8}" "-" "${total_cpu_cap}" "-" \
                    "${total_mem_req_fmt:0:8}" "${total_mem_lim_fmt:0:8}" "${total_mem_use_fmt:0:8}" "-" "${total_mem_cap_fmt:0:8}" "-"
                
                rm -f ${temp_file}.totals
            fi
            ;;
    esac
    
    rm -f $temp_file
}

# Cleanup function
cleanup() {
    # Clean up any temporary files
    rm -f /tmp/ktop.* 2>/dev/null
}

# Main execution
if [[ $WATCH_INTERVAL -gt 0 ]]; then
    # Trap Ctrl+C for clean exit
    trap 'cleanup; echo -e "\nExiting..."; exit 0' INT TERM
    
    while true; do
        clear
        echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC} - Refreshing every ${WATCH_INTERVAL}s (Ctrl+C to stop)"
        echo
        display_resources
        sleep $WATCH_INTERVAL
    done
else
    # Single run mode
    display_resources
    cleanup
fi

